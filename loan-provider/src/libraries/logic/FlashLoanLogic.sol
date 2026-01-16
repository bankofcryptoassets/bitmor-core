// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;
import {DataTypes} from "../types/DataTypes.sol";
import {LSALogic} from "./LSALogic.sol";
import {IERC20} from "../../dependencies/openzeppelin/IERC20.sol";
import {BitmorLendingPoolLogic} from "./BitmorLendingPoolLogic.sol";
import {SwapLogic} from "./SwapLogic.sol";
import {Errors} from "../helpers/Errors.sol";
import {SafeERC20} from "../../dependencies/openzeppelin/SafeERC20.sol";

/**
 * @title FlashLoanLogic
 * @author Bitmor Protocol
 * @notice Library for handling Aave V3 flash loan callbacks
 * @dev Processes flash loan operations for both loan initialization and loan closure.
 *
 * ## Flash Loan Operations
 *
 * ### Loan Initialization
 * 1. Receive flash loaned USDC
 * 2. Combine with user deposit
 * 3. Swap total USDC to cbBTC via swap adapter
 * 4. Deposit cbBTC to Bitmor Lending Pool (LSA receives aTokens)
 * 5. Borrow from Bitmor Pool to repay flash loan + premium
 *
 * ### Loan Closure
 * 1. Receive flash loaned USDC to repay debt
 * 2. Repay debt on Bitmor Lending Pool
 * 3. Withdraw collateral from Bitmor Pool
 * 4. Send pre-closure fee to collector
 * 5. Swap collateral to USDC to repay flash loan
 *
 * @custom:security Validates flash loan callback caller and initiator
 */
library FlashLoanLogic {
    using SafeERC20 for IERC20;

    /**
     * @notice Local variables for close loan flash loan operations
     * @dev Used internally to organize intermediate values and avoid stack too deep
     */
    struct LocalVarsCloseLoan {
        address lsa; /**
                      * @dev Loan Specific Address being closed
                      */
        bool withdrawInCollateralAsset; /**
                                         * @dev If true, user receives cbBTC; if false, receives USDC
                                         */
        uint256 preClosureFee; /**
                                * @dev Fee charged for early loan closure
                                */
        uint256 finalAmountRepaid; /**
                                    * @dev Actual amount repaid to Bitmor Pool
                                    */
        uint256 collateralAmountWithdrawn; /**
                                            * @dev Amount of collateral withdrawn from Bitmor Pool
                                            */
        uint256 totalDebtRemaining; /**
                                     * @dev Remaining debt after repayment
                                     */
        uint256 collateralAmountToSwap; /**
                                         * @dev Amount of collateral to swap for flash loan repayment
                                         */
        uint256 minimumAcceptable; /**
                                    * @dev Minimum output from swap (slippage protection)
                                    */
        uint256 debtAssetAmtReceived; /**
                                       * @dev Amount of debt asset received from swap
                                       */
        uint256 totalFlashLoanBorrowedAmt; /**
                                            * @dev Total flash loan amount including premium
                                            */
    }

    /**
     * @notice Executes flash loan callback for loan initialization
     * @dev Called by Aave V3 pool during loan creation. Swaps USDC to cbBTC,
     * deposits collateral, and borrows to repay flash loan.
     *
     * ## Security Checks
     * - Caller must be Aave V3 pool
     * - Initiator must be the Loan contract (this)
     *
     * @param ctx Execution context with protocol addresses
     * @param params Flash loan parameters (asset, amount, premium, etc.)
     * @param loansByLSA Storage mapping of loans by LSA
     */
    function executeFLOperationInitiailizingLoan(
        DataTypes.ExecuteFLOperationContext memory ctx,
        DataTypes.ExecuteFLOperationParams memory params,
        mapping(address => DataTypes.LoanData) storage loansByLSA
    ) internal {
        if (msg.sender != ctx.aavePool) {
            revert Errors.CallerIsNotAAVEPool();
        }
        if (params.initiator != address(this)) revert Errors.WrongFLInitiator();

        // Flash loan execution logic will be implemented here
        // Flow: Swap USDC → cbBTC → Deposit to Aave V2 → Borrow from Aave V2 → Repay flash loan

        (address lsa,) = abi.decode(params.params, (address, uint256));

        // Retrieve loan data from storage
        DataTypes.LoanData storage loan = loansByLSA[lsa];

        uint256 totalSwapAmount = loan.depositAmount + params.amount;

        uint256 minimumAcceptable = SwapLogic.calculateMinBTCAmt(
            ctx.zQuoter,
            ctx.debtAsset, // tokenIn
            ctx.collateralAsset, // tokenOut
            ctx.oracle,
            totalSwapAmount, // amountIn
            ctx.maxSlippage
        );

        // Approve SwapAdaptor to spend tokens
        IERC20(ctx.debtAsset).forceApprove(ctx.swapAdapter, totalSwapAmount);

        uint256 amountReceived = SwapLogic.executeSwap(
            ctx.swapAdapter, ctx.debtAsset, ctx.collateralAsset, totalSwapAmount, minimumAcceptable
        );

        if (amountReceived < minimumAcceptable) revert Errors.LessThanMinimumAmtReceived();

        uint256 borrowAmount = params.amount + params.premium;

        LSALogic.approveCreditDelegation(
            lsa,
            ctx.bitmorPool,
            ctx.debtAsset,
            borrowAmount,
            address(this) // Protocol is the delegatee
        );

        // Approve Aave V2 pool to spend asset
        IERC20(ctx.collateralAsset).forceApprove(ctx.bitmorPool, amountReceived);

        BitmorLendingPoolLogic.depositCollateral(ctx.bitmorPool, ctx.collateralAsset, amountReceived, lsa);

        BitmorLendingPoolLogic.borrowDebt(ctx.bitmorPool, ctx.debtAsset, borrowAmount, lsa);

        // To allow aavePool to withdraw borrow amount
        IERC20(ctx.debtAsset).forceApprove(ctx.aavePool, borrowAmount);
    }

    /**
     * @notice Executes flash loan callback for loan closure
     * @dev Called by Aave V3 pool during loan closure. Repays debt, withdraws collateral,
     * charges pre-closure fee, and swaps collateral to repay flash loan.
     *
     * ## Execution Flow
     * 1. Validate caller (Aave pool) and initiator (this contract)
     * 2. Repay full debt amount to Bitmor Lending Pool
     * 3. Withdraw all collateral from Bitmor Pool if debt fully repaid
     * 4. Transfer pre-closure fee to fee collector
     * 5. Swap required collateral amount to debt asset
     * 6. Approve Aave pool to pull flash loan repayment
     *
     * @param ctx Execution context with protocol addresses
     * @param params Flash loan parameters (asset, amount, premium, etc.)
     * @param loansByLSA Storage mapping of loans by LSA
     */
    function executeFLOperationCloseLoan(
        DataTypes.ExecuteFLOperationContext memory ctx,
        DataTypes.ExecuteFLOperationParams memory params,
        mapping(address => DataTypes.LoanData) storage loansByLSA
    ) internal {
        if (msg.sender != ctx.aavePool) {
            revert Errors.CallerIsNotAAVEPool();
        }
        if (params.initiator != address(this)) revert Errors.WrongFLInitiator();

        // Flash loan execution logic will be implemented here
        // Flow: Swap USDC → cbBTC → Deposit to Aave V2 → Borrow from Aave V2 → Repay flash loan
        LocalVarsCloseLoan memory vars;

        (vars.lsa, vars.withdrawInCollateralAsset, vars.collateralAmountToSwap, vars.preClosureFee) =
            abi.decode(params.params, (address, bool, uint256, uint256));

        // Retrieve loan data from storage
        DataTypes.LoanData storage loan = loansByLSA[vars.lsa];

        // =========== Close Loan ==========
        IERC20(ctx.debtAsset).forceApprove(ctx.bitmorPool, params.amount);

        vars.finalAmountRepaid =
            BitmorLendingPoolLogic.executeLoanRepayment(ctx.bitmorPool, ctx.debtAsset, vars.lsa, params.amount);
        // ===============================================================

        // =========== Withdraw collateral asset ==========

        vars.totalDebtRemaining = BitmorLendingPoolLogic.getVDTTokenAmount(ctx.bitmorPool, ctx.debtAsset, vars.lsa);
        if (vars.totalDebtRemaining == 0) {
            loan.status = DataTypes.LoanStatus.Completed;
            loan.duration = 0;

            vars.collateralAmountWithdrawn =
                LSALogic.withdrawCollateral(ctx.bitmorPool, vars.lsa, ctx.collateralAsset, address(this));

            if (vars.collateralAmountWithdrawn == 0) revert Errors.CollateralWithdrawFailed();
        }
        // ===============================================================

        // Sends the pre-closure fee to the fee collector
        IERC20(ctx.collateralAsset).safeTransfer(ctx.feeCollector, vars.preClosureFee);

        // =========== Swap the required amount to debt asset ==========

        if (!vars.withdrawInCollateralAsset) {
            // When not withdrawing in collateral asset, swap all remaining after fee
            vars.collateralAmountToSwap = vars.collateralAmountWithdrawn - vars.preClosureFee;
        }
        // When withdrawInCollateralAsset=true, use the amount calculated in CloseLoanLogic

        vars.minimumAcceptable = SwapLogic.calculateMinBTCAmt(
            ctx.zQuoter,
            ctx.collateralAsset, // tokenIn
            ctx.debtAsset, // tokenOut
            ctx.oracle,
            vars.collateralAmountToSwap, // amountIn
            ctx.maxSlippage
        );

        // Approve SwapAdaptor to spend tokens
        IERC20(ctx.collateralAsset).forceApprove(ctx.swapAdapter, vars.collateralAmountToSwap);

        vars.debtAssetAmtReceived = SwapLogic.executeSwap(
            ctx.swapAdapter,
            ctx.collateralAsset, //tokenIn
            ctx.debtAsset, // tokenOut
            vars.collateralAmountToSwap, // amountIn
            vars.minimumAcceptable
        );
        // ===============================================================

        // To allow aavePool to withdraw borrow amount
        vars.totalFlashLoanBorrowedAmt = params.amount + params.premium;
        IERC20(ctx.debtAsset).forceApprove(ctx.aavePool, vars.totalFlashLoanBorrowedAmt);
    }
}
