// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

import {Errors} from "../helpers/Errors.sol";
import {Constants} from "../helpers/Constants.sol";
import {DataTypes} from "../types/DataTypes.sol";

import {LSALogic} from "./LSALogic.sol";
import {SwapLogic} from "./SwapLogic.sol";
import {BTCVaultLogic} from "./BTCVaultLogic.sol";
import {BitmorLendingPoolLogic} from "./BitmorLendingPoolLogic.sol";

import {ILoan} from "../../interfaces/ILoan.sol";

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
    using SwapLogic for address;

    /**
     * @notice Local variables for close loan flash loan operations
     * @dev Used internally to organize intermediate values and avoid stack too deep
     */
    struct LocalVarsCloseLoan {
        /// @dev Loan Specific Address being closed
        address lsa;
        /// @dev If true, user receives cbBTC; if false, receives USDC
        bool withdrawInBTC;
        /// @dev Fee charged for early loan closure in basis points
        uint256 preClosureFeeBps;
        /// @dev Pre-closure fee amount in debt asset
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
        /// @dev Amount of cbBTC received after redeeming bvBTC shares
        uint256 btcAmtReceived;
        /// @dev Total cbBTC amount to swap, calculated in `CloseLoanLogic`
        uint256 totalBTCAmtToSwap;
        /// @dev Pre-closure fee amount denominated in cbBTC
        uint256 preClosureFeeAmtInBTC;
    }

    /**
     * @dev Basis points denominator for percentage calculations (100% = 10000)
     */
    uint256 constant BASIS_POINT_SCALE = 100_00;

    /**
     * @notice Executes flash loan callback for loan initialization
     * @dev Called by Aave V3 pool during loan creation.
     *
     * Flow:
     * 1. Swap `debtAsset` to `btc`
     * 2. Deposit `btc` to `collateralAsset` which is BTC vault and receives `bvBTC` shares
     * 3. Deposit `bvBTC` in `bitmorPool`
     * 4. Borrow `debtAsset` from `bitmorPool`
     * 5. Repay the Flash Loan `amount` and `premium`
     *
     * @param ctx Execution context with protocol addresses
     * @param params Flash loan parameters (asset, amount, premium, etc.)
     * @param loansByLSA Storage mapping of loans by LSA
     * @custom:security Validates `msg.sender` is the Aave V3 pool and `params.initiator` is this contract
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

        (address lsa, uint256 btcAmount) = abi.decode(params.params, (address, uint256));

        // Retrieve loan data from storage
        DataTypes.LoanData storage loan = loansByLSA[lsa];

        uint256 totalSwapAmount = loan.depositAmount + params.amount;

        uint256 maxAmountIn = ctx.swapper.calculateMaxAmountIn(
            ctx.debtAsset, // tokenIn
            ctx.btc, // tokenOut
            btcAmount,
            ctx.maxSlippage
        );

        if (maxAmountIn > totalSwapAmount) revert Errors.LessAmountForExactOutSwap();

        /// @dev Approve SwapAdaptor to spend tokens
        IERC20(ctx.debtAsset).forceApprove(ctx.swapper, totalSwapAmount);

        /// @dev Swap USDC to BTC
        ctx.swapper.executeExactOutSwap(ctx.debtAsset, ctx.btc, btcAmount, maxAmountIn, address(this));

        /// @dev Approve BTC Vault (`collateralAsset`) to spend `btc`.
        IERC20(ctx.btc).forceApprove(ctx.collateralAsset, btcAmount);

        /// @dev Depositing BTC into BTC Vault and receiving its shares `bvBTC`.
        uint256 bvBTCSharesReceived = ctx.collateralAsset.deposit(btcAmount, address(this));

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
     * @custom:security Validates `msg.sender` is the Aave V3 pool and `params.initiator` is this contract
     * TODO: to check whether we need to pass uint256 max or this will work through integration testing.
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

        (vars.lsa, vars.withdrawInBTC, vars.totalBTCAmtToSwap, vars.preClosureFeeAmtInBTC) =
            abi.decode(params.params, (address, bool, uint256, uint256));

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
        if (vars.totalDebtRemaining <= Constants.DEBT_DUST_THRESHOLD) {
            loan.status = DataTypes.LoanStatus.Completed;
            loan.duration = 0;

            // Repay dust debt so lending pool allows full collateral withdrawal
            if (vars.totalDebtRemaining > 0) {
                ctx.bitmorPool.repayDustDebt(ctx.debtAsset, vars.lsa, vars.totalDebtRemaining);
                emit ILoan.Loan__DustDebtAbsorbed(vars.lsa, vars.totalDebtRemaining);
            }

            vars.collateralAmountWithdrawn = vars.lsa.withdrawCollateral(ctx.bitmorPool, ctx.collateralAsset, vars.lsa);

            if (vars.collateralAmountWithdrawn == 0) revert Errors.CollateralWithdrawFailed();

            /// @dev Redeem `btc` for `bvBTC` shares from BTC vault to Loan contract
            /// The Loan contract needs the BTC to deduct fee and swap for flash loan repayment.
            /// CloseLoanLogic transfers remaining BTC/USDC to borrower after flash loan completes.
            vars.btcAmtReceived = vars.lsa.redeemBTC(
                ctx.collateralAsset, vars.collateralAmountWithdrawn, address(this), params.slippage_sharesToAsset
            );
        }
        // ===============================================================

        // Sends the pre-closure fee to the fee collector
        IERC20(ctx.btc).safeTransfer(ctx.feeCollector, vars.preClosureFeeAmtInBTC);

        // =========== Swap the required amount to debt asset ==========

        vars.btcAmtToSwap = vars.totalBTCAmtToSwap.min((vars.btcAmtReceived - vars.preClosureFeeAmtInBTC));

        vars.minimumAcceptable =
            ctx.swapper.calculateMinAmountOut(ctx.btc, ctx.debtAsset, vars.btcAmtToSwap, ctx.maxSlippage);

        // Approve SwapAdaptor to spend tokens
        IERC20(ctx.btc).forceApprove(ctx.swapper, vars.btcAmtToSwap);

        vars.debtAssetAmtReceived = ctx.swapper.executeExactInSwap(
            ctx.btc, //tokenIn
            ctx.debtAsset, // tokenOut
            vars.btcAmtToSwap, // amountIn
            vars.minimumAcceptable,
            address(this)
        );

        if (vars.debtAssetAmtReceived < vars.totalFlashLoanBorrowedAmt) {
            revert Errors.InsufficientSwapOutput();
        }

        // ===============================================================

        IERC20(ctx.debtAsset).forceApprove(ctx.aavePool, vars.totalFlashLoanBorrowedAmt);
    }
}
