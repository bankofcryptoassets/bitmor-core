// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

import {IPriceOracleGetter} from "../../interfaces/IPriceOracleGetter.sol";
import {ILoan} from "../../interfaces/ILoan.sol";

import {Errors} from "../helpers/Errors.sol";
import {DataTypes} from "../types/DataTypes.sol";

import {BitmorLendingPoolLogic} from "./BitmorLendingPoolLogic.sol";
import {AavePoolLogic} from "./AavePoolLogic.sol";

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
 * - `withdrawInCollateralAsset = true`: User receives remaining cbBTC after debt repayment
 * - `withdrawInCollateralAsset = false`: User receives USDC (all collateral swapped)
 */
library CloseLoanLogic {
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;
    using BitmorLendingPoolLogic for address;
    using AavePoolLogic for address;

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
        uint256 totalCollateralUSD; /**
                                     * @dev Total collateral value in USD
                                     */
        uint256 totalDebtUSD; /**
                               * @dev Total debt value in USD
                               */
        uint256 collateralAssetPrice; /**
                                       * @dev Current cbBTC price in USD (8 decimals)
                                       */
        uint256 debtAssetPrice; /**
                                 * @dev Current USDC price in USD (8 decimals)
                                 */
        uint256 collateralAmt; /**
                                * @dev Amount of aTokens (collateral) held by LSA
                                */
        uint256 preClosureFeeAmt; /**
                                   * @dev Pre-closure fee in collateral asset
                                   */
        uint256 preClosureFeeUSD; /**
                                   * @dev Pre-closure fee in USD
                                   */
        uint256 debtAmt; /**
                          * @dev Total debt amount (vdtToken balance)
                          */
        uint256 flashLoanPremiumBps; /**
                                      * @dev Aave flash loan premium in basis points
                                      */
        uint256 flashLoanPremiumAmount; /**
                                         * @dev Flash loan premium in debt asset
                                         */
        uint256 flashLoanPremiumAmountUSD; /**
                                            * @dev Flash loan premium in USD
                                            */
        uint256 totalCollateralAmtToSwap; /**
                                           * @dev Amount of collateral to swap for debt repayment
                                           */
        uint256 remainingBTCAmt; /**
                                  * @dev Remaining collateral after operations
                                  */
        uint256 remainingDebtAssetBal; /**
                                        * @dev Remaining debt asset after operations
                                        */
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

        (vars.totalCollateralUSD, vars.totalDebtUSD) = ctx.bitmorPool.getUserPositions(params.lsa);

        /**
         * @dev `collateralAssetPrice` is the price of `bvBTC` shares.
         * It is calculated by converting 1 `bvBTC` share into BTC and mutiplying it by `BTC` price.
         */
        vars.collateralAssetPrice = IPriceOracleGetter(ctx.oracle).getAssetPrice(ctx.collateralAsset);
        vars.debtAssetPrice = IPriceOracleGetter(ctx.oracle).getAssetPrice(ctx.debtAsset);

        vars.collateralAmt = ctx.bitmorPool.getATokenAmount(ctx.collateralAsset, params.lsa);

        vars.preClosureFeeAmt = vars.collateralAmt.mulDivUp(ctx.preClosureFeeBps, BASIS_POINTS);

        vars.preClosureFeeUSD = vars.preClosureFeeAmt.mulDivUp(vars.collateralAssetPrice, PRICE_PRECISION);

        vars.debtAmt = ctx.bitmorPool.getVDTTokenAmount(ctx.debtAsset, params.lsa);

        vars.flashLoanPremiumBps = ctx.aavePool.getFlashLoanPremium();

        vars.flashLoanPremiumAmount = vars.debtAmt.mulDivUp(vars.flashLoanPremiumBps, BASIS_POINTS);

        vars.flashLoanPremiumAmountUSD = vars.flashLoanPremiumAmount.mulDivUp(vars.debtAssetPrice, PRICE_PRECISION);

        if (vars.preClosureFeeUSD + vars.flashLoanPremiumAmountUSD + vars.totalDebtUSD > vars.totalCollateralUSD) {
            revert Errors.InsufficientCollateral();
        }

        if (params.withdrawInCollateralAsset) {
            // Only swap enough collateral to repay flash loan (debt + premium in debt asset terms)
            uint256 flashLoanRepaymentAmount = vars.debtAmt + vars.flashLoanPremiumAmount;
            vars.totalCollateralAmtToSwap =
                flashLoanRepaymentAmount.mulDiv(vars.debtAssetPrice, vars.collateralAssetPrice);
        } else {
            // Swap all collateral minus pre-closure fee to debt asset
            vars.totalCollateralAmtToSwap = vars.collateralAmt - vars.preClosureFeeAmt;
        }

        bool initializingLoan = false;

        bytes memory flData = abi.encode(params.lsa, params.withdrawInCollateralAsset, ctx.preClosureFeeBps);
        bytes memory paramsForFL = abi.encode(initializingLoan, flData);

        ctx.aavePool.executeFlashLoan(address(this), ctx.debtAsset, vars.debtAmt, paramsForFL);

        vars.remainingBTCAmt = IERC20(ctx.btc).balanceOf(address(this));
        vars.remainingDebtAssetBal = IERC20(ctx.debtAsset).balanceOf(address(this));

        if (vars.remainingBTCAmt > 0) {
            IERC20(ctx.btc).safeTransfer(loan.borrower, vars.remainingBTCAmt);
        }
        if (vars.remainingDebtAssetBal > 0) {
            IERC20(ctx.debtAsset).safeTransfer(loan.borrower, vars.remainingDebtAssetBal);
        }

        emit ILoan.Loan__ClosedLoan(params.lsa);
    }
}
