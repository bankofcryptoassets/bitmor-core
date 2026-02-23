// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

import {ILoan} from "../../interfaces/ILoan.sol";

import {Errors} from "../helpers/Errors.sol";
import {OracleLib} from "../helpers/OracleLib.sol";
import {DataTypes} from "../types/DataTypes.sol";

import {AavePoolLogic} from "./AavePoolLogic.sol";
import {BTCVaultLogic} from "./BTCVaultLogic.sol";
import {BitmorLendingPoolLogic} from "./BitmorLendingPoolLogic.sol";

/**
 * @title CloseLoanLogic
 * @author Bitmor Protocol
 * @notice Library for loan closure logic and calculations
 * @dev Handles the complex flow of closing a loan including fee calculations and flash loan initiation.
 *
 * ## Close Loan Flow
 * 1. Validates loan ownership and existence
 * 2. Fetches current positions and prices from oracles
 * 3. Calculates pre-closure fee and flash loan premium
 * 4. Validates sufficient collateral to cover all costs
 * 5. Initiates flash loan to repay debt
 * 6. Transfers remaining assets to borrower
 *
 * ## Withdrawal Options
 * - `withdrawInBTC = true`: User receives remaining cbBTC after debt repayment
 * - `withdrawInBTC = false`: User receives USDC (all collateral swapped)
 */
library CloseLoanLogic {
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;
    using BitmorLendingPoolLogic for address;
    using AavePoolLogic for address;
    using BTCVaultLogic for address;
    /**
     * @dev Oracle price precision (8 decimals)
     */

    uint256 private constant PRICE_PRECISION = 1e8;

    /**
     * @dev Basis points denominator (100% = 10000)
     */
    uint256 private constant BASIS_POINTS = 100_00;

    /**
     * @notice Local variables for close loan calculations to avoid stack too deep
     * @dev Used internally to organize intermediate calculation values
     */
    struct LocalVarsCloseLoan {
        /// @dev Total collateral value in USD (8 decimals from Chainlink)
        uint256 totalCollateralUSD;
        /// @dev Total debt value in USD (8 decimals from Chainlink)
        uint256 totalDebtUSD;
        /// @dev Current USDC price in USD (8 decimals)
        uint256 debtAssetPrice;
        /// @dev Current cbBTC price in USD (8 decimals)
        uint256 btcPrice;
        /// @dev Amount of aTokens (bvBTC collateral) held by LSA
        uint256 collateralAmt;
        /// @dev Collateral amount converted to underlying cbBTC
        uint256 collateralAmtInBTC;
        /// @dev Pre-closure fee denominated in cbBTC
        uint256 preClosureFeeAmtInBTC;
        /// @dev Pre-closure fee denominated in USD
        uint256 preClosureFeeUSD;
        /// @dev Total outstanding debt (variable debt token balance)
        uint256 debtAmt;
        /// @dev Aave flash loan premium in basis points
        uint256 flashLoanPremiumBps;
        /// @dev Flash loan premium in debt asset (USDC)
        uint256 flashLoanPremiumAmount;
        /// @dev Flash loan premium converted to cbBTC
        uint256 flashLoanPremiumAmountInBTC;
        /// @dev Flash loan premium in USD
        uint256 flashLoanPremiumAmountUSD;
        /// @dev Amount of cbBTC to swap for debt repayment
        uint256 totalBTCAmtToSwap;
        /// @dev Remaining cbBTC after all operations
        uint256 remainingBTCAmt;
        /// @dev Remaining debt asset (USDC) after all operations
        uint256 remainingDebtAssetBal;
    }

    /**
     * @notice Executes the loan closure process
     * @dev Validates ownership, calculates fees, and initiates flash loan for debt repayment.
     * Remaining funds are transferred to the borrower after all operations complete.
     *
     * ## Requirements
     * - Caller must be the loan borrower
     * - Collateral must cover debt + flash loan premium + pre-closure fee
     *
     * ## Close Loan Invariants (Invariant 2.2)
     * - MUST transfer all LSA bvBTC shares to borrower (as USDC or cbBTC based on `withdrawInBTC`)
     * - LSA bvBTC share balance MUST be 0 after close
     * - All remaining cbBTC and USDC on the Loan contract (above pre-snapshot balances) MUST be
     *   forwarded to the borrower
     *
     * @param ctx Context containing protocol addresses and configuration
     * @param params Parameters including LSA and withdrawal preference
     * @param loansByLSA Storage mapping of all loans by LSA
     */
    function executeCloseLoan(
        DataTypes.ExecuteCloseLoanContext memory ctx,
        DataTypes.ExecuteCloseLoanParams memory params,
        mapping(address => DataTypes.LoanData) storage loansByLSA
    ) internal {
        LocalVarsCloseLoan memory vars;

        if (params.lsa == address(0)) revert Errors.ZeroAddress();

        DataTypes.LoanData memory loan = loansByLSA[params.lsa];

        if (loan.borrower == address(0)) revert Errors.LoanDoesNotExists();
        if (loan.borrower != msg.sender) revert Errors.UnauthorizedCaller();
        if (loan.status != DataTypes.LoanStatus.Active) revert Errors.LoanIsNotActive();

        /// @dev Price is in 8 decimals as per Chainlink Price Feed.
        (vars.totalCollateralUSD, vars.totalDebtUSD) = ctx.bitmorPool.getUserPositions(params.lsa);

        vars.debtAssetPrice = OracleLib.getPrice(ctx.oracle, ctx.debtAsset, ctx.maxOracleStaleness);
        vars.btcPrice = OracleLib.getPrice(ctx.oracle, ctx.btc, ctx.maxOracleStaleness);

        if (vars.debtAssetPrice == 0 || vars.btcPrice == 0) revert Errors.InvalidAssetPrice();

        /// @dev Here the decimals will be
        /// decimals = IERC20Metadata(ctx.collateralAsset).decimals();
        vars.collateralAmt = ctx.bitmorPool.getATokenAmount(ctx.collateralAsset, params.lsa);

        /// @dev Here the decimals will be
        /// decimals = IERC20Metadata(ctx.btc).decimals();
        vars.collateralAmtInBTC = ctx.collateralAsset.previewRedeem(vars.collateralAmt);

        /// @dev Here the decimals will be same as `vars.collateralAmtInBTC`
        /// @dev Pre Closure Fee amount needs to be calculated in terms of `ctx.btc`
        vars.preClosureFeeAmtInBTC = vars.collateralAmtInBTC.mulDivUp(ctx.preClosureFeeBps, BASIS_POINTS);

        /// @dev Decimal Calulation
        /// decimals = 8, as its provided by Chainlink Price Feed.
        vars.preClosureFeeUSD =
            vars.preClosureFeeAmtInBTC.mulDivUp(vars.btcPrice, 10 ** IERC20Metadata(ctx.btc).decimals());

        /// @dev Here the decimals will be
        /// decimals = IERC20Metadata(ctx.debtAsset).decimals();
        vars.debtAmt = ctx.bitmorPool.getVDTTokenAmount(ctx.debtAsset, params.lsa);

        vars.flashLoanPremiumBps = ctx.aavePool.getFlashLoanPremium();

        /// @dev Flash Loan Premium Amount is calculated on the flash loan asset.
        /// In this case its: `ctx.debtAsset`
        /// @dev Here the decimals will be same as `vars.debtAmt`
        vars.flashLoanPremiumAmount = vars.debtAmt.mulDivUp(vars.flashLoanPremiumBps, BASIS_POINTS);

        /// @dev Decimal Calculation
        /// decimals = 8, as its provided by Chainlink Price Feed.
        vars.flashLoanPremiumAmountUSD =
            vars.flashLoanPremiumAmount.mulDivUp(vars.debtAssetPrice, 10 ** IERC20Metadata(ctx.debtAsset).decimals());

        /// @dev This is to calculate the `vars.totalBTCAmtToSwap` which is in terms of `ctx.btc`
        /// @dev Decimal Calculation
        /// decimals = IERC20Metadata(ctx.btc).decimals()
        vars.flashLoanPremiumAmountInBTC =
            vars.flashLoanPremiumAmountUSD.mulDivUp(10 ** IERC20Metadata(ctx.btc).decimals(), vars.btcPrice);

        if (vars.preClosureFeeUSD + vars.flashLoanPremiumAmountUSD + vars.totalDebtUSD > vars.totalCollateralUSD) {
            revert Errors.InsufficientCollateral();
        }

        if (params.withdrawInBTC) {
            // Only swap enough BTC to repay flash loan (debt + premium in debt asset terms)

            /// @dev Here decimals will be same as `ctx.debtAsset`
            uint256 flashLoanRepaymentAmount = vars.debtAmt + vars.flashLoanPremiumAmount;

            /// @dev Convert the `flashLoanRepaymentAmount` in `ctx.debtAsset` to `ctx.btc`
            vars.totalBTCAmtToSwap = _convertFromAssetAToAssetB(
                flashLoanRepaymentAmount,
                vars.debtAssetPrice,
                vars.btcPrice,
                IERC20Metadata(ctx.debtAsset).decimals(),
                IERC20Metadata(ctx.btc).decimals()
            );
        } else {
            // Swap all collateral minus pre-closure fee to debt asset
            vars.totalBTCAmtToSwap = vars.collateralAmtInBTC - vars.preClosureFeeAmtInBTC;
        }

        bool initializingLoan = false;

        bytes memory flData =
            abi.encode(params.lsa, params.withdrawInBTC, vars.totalBTCAmtToSwap, vars.preClosureFeeAmtInBTC);
        bytes memory paramsForFL = abi.encode(initializingLoan, flData);

        /// @dev Snapshot balances before flash loan to isolate this closure's surplus
        uint256 debtAssetBalBefore = IERC20(ctx.debtAsset).balanceOf(address(this));
        uint256 btcBalBefore = IERC20(ctx.btc).balanceOf(address(this));

        ctx.aavePool.executeFlashLoan(address(this), ctx.debtAsset, vars.debtAmt, paramsForFL);

        vars.remainingDebtAssetBal = IERC20(ctx.debtAsset).balanceOf(address(this)) - debtAssetBalBefore;
        vars.remainingBTCAmt = IERC20(ctx.btc).balanceOf(address(this)) - btcBalBefore;

        if (vars.remainingBTCAmt > 0) {
            IERC20(ctx.btc).safeTransfer(loan.borrower, vars.remainingBTCAmt);
        }
        if (vars.remainingDebtAssetBal > 0) {
            IERC20(ctx.debtAsset).safeTransfer(loan.borrower, vars.remainingDebtAssetBal);
        }

        emit ILoan.Loan__ClosedLoan(params.lsa);
    }

    /**
     * @notice Converts an amount of one asset to the equivalent amount of another using oracle prices
     * @dev Assumes both `assetAPrice` and `assetBPrice` have the same decimal precision (8 decimals from Chainlink).
     * Uses `mulDivUp` for rounding up to ensure sufficient coverage in debt repayment scenarios.
     * @param assetAAmt Amount of asset A to convert
     * @param assetAPrice Unit price of asset A (8 decimals)
     * @param assetBPrice Unit price of asset B (8 decimals)
     * @param assetADecimals Decimal precision of asset A token
     * @param assetBDecimals Decimal precision of asset B token
     * @return The equivalent amount of asset B
     */
    function _convertFromAssetAToAssetB(
        uint256 assetAAmt,
        uint256 assetAPrice,
        uint256 assetBPrice,
        uint256 assetADecimals,
        uint256 assetBDecimals
    ) internal pure returns (uint256) {
        return assetAAmt.mulDivUp(assetAPrice * (10 ** assetBDecimals), assetBPrice * (10 ** assetADecimals));
    }
}
