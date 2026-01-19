// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

import {Errors} from "../helpers/Errors.sol";
import {DataTypes} from "../types/DataTypes.sol";

import {LSALogic} from "./LSALogic.sol";
import {SwapLogic} from "./SwapLogic.sol";
import {BTCVaultLogic} from "./BTCVaultLogic.sol";
import {BitmorLendingPoolLogic} from "./BitmorLendingPoolLogic.sol";

import {IPriceOracleGetter} from "../../interfaces/IPriceOracleGetter.sol";

/**
 * @title FlashLoanLogic
 * @author Bitmor Protocol
 * @notice Library for handling Aave V3 flash loan callbacks
 * @dev Processes flash loan operations for both loan initialization and loan closure.
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
    using LSALogic for address;
    using BTCVaultLogic for address;
    using BitmorLendingPoolLogic for address;
    using FixedPointMathLib for uint256;

    /**
     * @notice Local variables for close loan flash loan operations
     * @dev Used internally to organize intermediate values and avoid stack too deep
     */
    struct LocalVarsCloseLoan {
        /// @dev Loan Specific Address being closed
        address lsa;
        /// @dev If true, user receives cbBTC; if false, receives USDC
        bool withdrawInCollateralAsset;
        /// @dev Fee charged for early loan closure
        uint256 preClosureFeeBps;
        uint256 preClosureFeeAmt;
        /// @dev Actual amount repaid to Bitmor Pool
        uint256 finalAmountRepaid;
        /// @dev Amount of collateral withdrawn from Bitmor Pool
        uint256 collateralAmountWithdrawn;
        /// @dev Remaining debt after repayment
        uint256 totalDebtRemaining;
        /// @dev Amount of collateral to swap for flash loan repayment
        uint256 btcAmtToSwap;
        /// @dev Minimum output from swap (slippage protection)
        uint256 minimumAcceptable;
        /// @dev Amount of debt asset received from swap
        uint256 debtAssetAmtReceived;
        /// @dev Total flash loan amount including premium
        uint256 totalFlashLoanBorrowedAmt;
        uint256 btcAmtReceived;
    }
    uint256 constant BASIS_POINT_SCALE = 100_00;

    /**
     * @notice Executes flash loan callback for loan initialization
     * @dev Called by Aave V3 pool during loan creation.
     *
     * Flow:
     * 1. Swap `debtAsset` to `btc`
     * 2. Deposit `btc` to `collateralAsset` which is BTC vault and receives `bvBTC` shares.
     * 3. Deposit `bvBTC` in `bitmorPool`
     * 4. Borrow `debtAsset` from `bitmorPool`
     * 5. Repay the Flash Loan `amount` and `premium`
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

        (address lsa,) = abi.decode(params.params, (address, uint256));

        // Retrieve loan data from storage
        DataTypes.LoanData storage loan = loansByLSA[lsa];

        uint256 totalSwapAmount = loan.depositAmount + params.amount;

        uint256 minimumAcceptable = SwapLogic.calculateMinBTCAmt(
            ctx.zQuoter,
            ctx.debtAsset, // tokenIn
            ctx.btc, // tokenOut
            ctx.oracle,
            totalSwapAmount, // amountIn
            ctx.maxSlippage
        );

        /// @dev Approve SwapAdaptor to spend tokens
        IERC20(ctx.debtAsset).forceApprove(ctx.swapAdapter, totalSwapAmount);

        /// @dev Swap USDC to BTC
        uint256 amountReceived = SwapLogic.executeSwap(
            ctx.swapAdapter, ctx.debtAsset, ctx.collateralAsset, totalSwapAmount, minimumAcceptable
        );

        if (amountReceived < minimumAcceptable) revert Errors.LessThanMinimumAmtReceived();

        /// @dev Approve BTC Vault, `collateralAsset` to spend `btc`.
        IERC20(ctx.collateralAsset).forceApprove(ctx.btc, amountReceived);

        /// @dev Depositing BTC into BTC Vault and receiving its shares `bvBTC`.
        uint256 bvBTCSharesReceived = ctx.collateralAsset.deposit(amountReceived, address(this));

        /// @dev Approve Aave V2 pool to spend `bvBTC`
        IERC20(ctx.collateralAsset).forceApprove(ctx.bitmorPool, bvBTCSharesReceived);

        /// @dev Depositing `bvBTC` shares onbehalf of `lsa`
        ctx.bitmorPool.depositCollateral(ctx.collateralAsset, bvBTCSharesReceived, lsa);

        /// @dev this borrow amount includes amount to borrow and flash loan premium.
        uint256 borrowAmount = params.amount + params.premium;

        /// @dev Approving Loan, address(this), to borrow.
        lsa.approveCreditDelegation(
            ctx.bitmorPool,
            ctx.debtAsset,
            borrowAmount,
            address(this) // Protocol is the delegatee
        );

        /// @dev Borrowing DebtAsset worth of `borrowAmount` onbehalf of `lsa`.
        ctx.bitmorPool.borrowDebt(ctx.debtAsset, borrowAmount, lsa);

        /// @dev To allow aavePool to withdraw borrow amount for Flash Loan repayment.
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

        (vars.lsa, vars.withdrawInCollateralAsset, vars.preClosureFeeBps) =
            abi.decode(params.params, (address, bool, uint256));

        // Retrieve loan data from storage
        DataTypes.LoanData storage loan = loansByLSA[vars.lsa];

        // To allow aavePool to withdraw borrow amount
        vars.totalFlashLoanBorrowedAmt = params.amount + params.premium;

        // =========== Close Loan ==========
        IERC20(ctx.debtAsset).forceApprove(ctx.bitmorPool, params.amount);

        vars.finalAmountRepaid = ctx.bitmorPool.executeLoanRepayment(ctx.debtAsset, vars.lsa, params.amount);
        // ===============================================================

        // =========== Withdraw collateral asset ==========

        vars.totalDebtRemaining = ctx.bitmorPool.getVDTTokenAmount(ctx.debtAsset, vars.lsa);
        if (vars.totalDebtRemaining == 0) {
            loan.status = DataTypes.LoanStatus.Completed;
            loan.duration = 0;

            vars.collateralAmountWithdrawn =
                vars.lsa.withdrawCollateral(ctx.bitmorPool, ctx.collateralAsset, address(this));

            if (vars.collateralAmountWithdrawn == 0) revert Errors.CollateralWithdrawFailed();

            /// @dev Redeem `btc` for `bvBTC` shares from BTC vault to the `borrower` address
            vars.btcAmtReceived = vars.lsa
                .redeemBTC(
                    ctx.collateralAsset, vars.collateralAmountWithdrawn, loan.borrower, params.slippage_sharesToAsset
                );
        }
        // ===============================================================

        vars.preClosureFeeAmt = vars.btcAmtReceived.mulDivUp(vars.preClosureFeeBps, BASIS_POINT_SCALE);

        // Sends the pre-closure fee to the fee collector
        IERC20(ctx.collateralAsset).safeTransfer(ctx.feeCollector, vars.preClosureFeeAmt);

        // =========== Swap the required amount to debt asset ==========

        if (vars.withdrawInCollateralAsset) {
            uint256 debtAssetPrice = IPriceOracleGetter(ctx.oracle).getAssetPrice(ctx.debtAsset);
            uint256 debtAssetToRepayUSD = vars.totalFlashLoanBorrowedAmt * debtAssetPrice;

            uint256 btcPrice = IPriceOracleGetter(ctx.oracle).getAssetPrice(ctx.btc);
            vars.btcAmtToSwap = debtAssetToRepayUSD.mulDiv(8, btcPrice);
        } else {
            // When not withdrawing in collateral asset, swap all remaining after fee
            vars.btcAmtToSwap = vars.btcAmtReceived - vars.preClosureFeeAmt;
        }
        // When withdrawInCollateralAsset=true, use the amount calculated in CloseLoanLogic

        vars.minimumAcceptable = SwapLogic.calculateMinBTCAmt(
            ctx.zQuoter,
            ctx.btc, // tokenIn
            ctx.debtAsset, // tokenOut
            ctx.oracle,
            vars.btcAmtToSwap, // amountIn
            ctx.maxSlippage
        );

        // Approve SwapAdaptor to spend tokens
        IERC20(ctx.collateralAsset).forceApprove(ctx.swapAdapter, vars.btcAmtToSwap);

        vars.debtAssetAmtReceived = SwapLogic.executeSwap(
            ctx.swapAdapter,
            ctx.collateralAsset, //tokenIn
            ctx.debtAsset, // tokenOut
            vars.btcAmtToSwap, // amountIn
            vars.minimumAcceptable
        );
        // ===============================================================

        IERC20(ctx.debtAsset).forceApprove(ctx.aavePool, vars.totalFlashLoanBorrowedAmt);
    }
}
