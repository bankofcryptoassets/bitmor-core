// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {DataTypes} from "../types/DataTypes.sol";
import {ILoan} from "../../interfaces/ILoan.sol";
import {Errors} from "../helpers/Errors.sol";
import {BitmorLendingPoolLogic} from "./BitmorLendingPoolLogic.sol";
import {IERC20} from "../../dependencies/openzeppelin/IERC20.sol";
import {IERC20Metadata} from "../../dependencies/openzeppelin/IERC20Metadata.sol";
import {SafeERC20} from "../../dependencies/openzeppelin/SafeERC20.sol";
import {IPriceOracleGetter} from "../../interfaces/IPriceOracleGetter.sol";
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
        uint256 collateralAssetDecimals; /**
                                          * @dev Collateral asset decimal multiplier (10^8 for cbBTC)
                                          */
        uint256 debtAssetDecimals; /**
                                    * @dev Debt asset decimal multiplier (10^6 for USDC)
                                    */
        uint256 collateralAmt; /**
                                * @dev Amount of aTokens (collateral) held by LSA
                                */
        uint256 preClosureFee; /**
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
        uint256 remainingCollateralAssetBal; /**
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

        (vars.totalCollateralUSD, vars.totalDebtUSD) =
            BitmorLendingPoolLogic.getUserPositions(ctx.bitmorPool, params.lsa);

        vars.collateralAssetPrice = IPriceOracleGetter(ctx.oracle).getAssetPrice(ctx.collateralAsset);
        vars.debtAssetPrice = IPriceOracleGetter(ctx.oracle).getAssetPrice(ctx.debtAsset);

        vars.collateralAssetDecimals = 10 ** (IERC20Metadata(ctx.collateralAsset).decimals());
        vars.debtAssetDecimals = 10 ** (IERC20Metadata(ctx.debtAsset).decimals());

        vars.collateralAmt = BitmorLendingPoolLogic.getATokenAmount(ctx.bitmorPool, ctx.collateralAsset, params.lsa);

        vars.preClosureFee = (vars.collateralAmt * ctx.preClosureFeeBps) / BASIS_POINTS;

        vars.preClosureFeeUSD = (vars.preClosureFee * vars.collateralAssetPrice) / vars.collateralAssetDecimals;

        vars.debtAmt = BitmorLendingPoolLogic.getVDTTokenAmount(ctx.bitmorPool, ctx.debtAsset, params.lsa);

        vars.flashLoanPremiumBps = AavePoolLogic.getFlashLoanPremium(ctx.aavePool);

        vars.flashLoanPremiumAmount = (vars.debtAmt * vars.flashLoanPremiumBps) / BASIS_POINTS;
        vars.flashLoanPremiumAmountUSD = (vars.flashLoanPremiumAmount * vars.debtAssetPrice) / vars.debtAssetDecimals;

        if (vars.preClosureFeeUSD + vars.flashLoanPremiumAmountUSD + vars.totalDebtUSD > vars.totalCollateralUSD) {
            revert Errors.InsufficientCollateral();
        }

        if (params.withdrawInCollateralAsset) {
            // Only swap enough collateral to repay flash loan (debt + premium in debt asset terms)
            uint256 flashLoanRepaymentAmount = vars.debtAmt + vars.flashLoanPremiumAmount;
            vars.totalCollateralAmtToSwap =
                (flashLoanRepaymentAmount * vars.debtAssetPrice * vars.collateralAssetDecimals)
                    / (vars.collateralAssetPrice * vars.debtAssetDecimals);
        } else {
            // Swap all collateral minus pre-closure fee to debt asset
            vars.totalCollateralAmtToSwap = vars.collateralAmt - vars.preClosureFee;
        }

        bool initializingLoan = false;

        bytes memory flData =
            abi.encode(params.lsa, params.withdrawInCollateralAsset, vars.totalCollateralAmtToSwap, vars.preClosureFee);
        bytes memory paramsForFL = abi.encode(initializingLoan, flData);

        AavePoolLogic.executeFlashLoan(ctx.aavePool, address(this), ctx.debtAsset, vars.debtAmt, paramsForFL);

        vars.remainingCollateralAssetBal = IERC20(ctx.collateralAsset).balanceOf(address(this));
        vars.remainingDebtAssetBal = IERC20(ctx.debtAsset).balanceOf(address(this));

        if (vars.remainingCollateralAssetBal > 0) {
            IERC20(ctx.collateralAsset).safeTransfer(loan.borrower, vars.remainingCollateralAssetBal);
        }
        if (vars.remainingDebtAssetBal > 0) {
            IERC20(ctx.debtAsset).safeTransfer(loan.borrower, vars.remainingDebtAssetBal);
        }

        emit ILoan.Loan__ClosedLoan(params.lsa);
    }
}
