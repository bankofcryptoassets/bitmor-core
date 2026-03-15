// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {DataTypes} from "../types/DataTypes.sol";
import {ILoan} from "../../interfaces/ILoan.sol";

import {Errors} from "../helpers/Errors.sol";
import {Constants} from "../helpers/Constants.sol";
import {LoanMath} from "../helpers/LoanMath.sol";

import {LoanStorage} from "../../protocol/LoanStorage.sol";

import {LSALogic} from "./LSALogic.sol";
import {BitmorLendingPoolLogic} from "./BitmorLendingPoolLogic.sol";

/**
 * @title RepayLogic
 * @author Bitmor Protocol
 * @notice Library for loan repayment execution logic
 * @dev Deployed as a public linked library. Resolves ERC-7201 storage internally
 * via `_resolveStorage(bytes32)`.
 *
 * ## Repayment Flow
 * 1. Validates LSA and amount parameters
 * 2. Caps repayment to outstanding debt (no overpayment)
 * 3. Pulls funds from payer and approves Bitmor Pool
 * 4. Executes repayment on Bitmor Lending Pool
 * 5. Accumulates partial payments; updates loan duration when full period(s) covered
 * 6. Withdraws collateral if fully repaid
 * 7. Refunds excess payment if any
 */
library RepayLogic {
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;
    using BitmorLendingPoolLogic for address;
    using LSALogic for address;

    function _resolveStorage(bytes32 slot) private pure returns (LoanStorage.LoanStorageData storage $) {
        assembly {
            $.slot := slot
        }
    }

    /**
     * @notice Executes a loan repayment for a specific LSA
     * @dev Checks the LSA debt position, calculates the repayable amount, and executes
     * repayment to the Bitmor Lending Pool. Updates loan duration based on amount repaid.
     *
     * ## State Changes
     * - If fully repaid: status = `Completed`, duration = 0, collateral withdrawn to borrower
     * - If partial period: `amountRepaidInCurrentPeriod` accumulates; duration unchanged
     * - If accumulated amount covers full period(s): duration reduced, remainder carried over
     *
     * ## Repayment Invariants
     * - MUST revert if loan status is `Completed` or `Liquidated` (Invariant 2.1.3)
     * - MUST reduce outstanding debt, MUST NOT increase it (Invariant 3.1)
     * - MUST cap: `finalAmountRepaid` = min(`params.amount`, `getVDTTokenAmount(lsa)`) (Invariant 3.2)
     * - Real debt after repayment MUST be strictly less than before (Invariant 3.3)
     * - Pool available liquidity MUST increase by `finalAmountRepaid` (Invariant 3.4)
     * - When accumulated repayment covers full period(s), `lastPaymentTimestamp` MUST advance (Invariant 3.5)
     * - If `params.amount` < `estimatedMonthlyPayment` and accumulated amount does not cover a full
     *   period, due date MUST NOT advance (Invariant 3.8)
     * - On final payment: debt remaining MUST be exactly 0 (or below dust threshold),
     *   MUST NOT be negative (Invariant 3.7)
     *
     * @param storageSlot ERC-7201 storage slot for LoanStorageData
     * @param bitmorPool Bitmor Lending Pool address
     * @param debtAsset Debt asset address (USDC)
     * @param collateralAsset Collateral asset address (bvBTC)
     * @param autoRepayer Address of the AutoRepayment contract
     * @param params Repayment parameters containing LSA and amount
     * @return finalAmountRepaid The actual amount repaid to the pool
     */
    function executeRepay(
        bytes32 storageSlot,
        address bitmorPool,
        address debtAsset,
        address collateralAsset,
        address autoRepayer,
        DataTypes.ExecuteRepayParams memory params
    ) public returns (uint256 finalAmountRepaid) {
        if (params.lsa == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (params.amount == 0) revert Errors.ZeroAmount();

        DataTypes.LoanData storage loan = _resolveStorage(storageSlot).loansByLSA[params.lsa];

        if (loan.borrower == address(0)) revert Errors.LoanDoesNotExists();
        if (loan.borrower != msg.sender && msg.sender != autoRepayer) {
            revert Errors.UnauthorizedCaller();
        }
        if (loan.status != DataTypes.LoanStatus.Active) revert Errors.LoanIsNotActive();

        uint256 totalDebt = bitmorPool.getVDTTokenAmount(debtAsset, params.lsa);
        uint256 maxRepayableAmt = LoanMath.min(params.amount, totalDebt);

        // Pull only what might be needed from the borrower
        IERC20(debtAsset).safeTransferFrom(msg.sender, address(this), maxRepayableAmt);

        // Approve Aave V2 pool (the spender) to pull from THIS contract
        IERC20(debtAsset).forceApprove(bitmorPool, maxRepayableAmt);

        finalAmountRepaid = bitmorPool.executeLoanRepayment(debtAsset, params.lsa, maxRepayableAmt);

        uint256 totalDebtRemaining = bitmorPool.getVDTTokenAmount(debtAsset, params.lsa);

        // Advance schedule only if loan remains active
        if (totalDebtRemaining <= Constants.DEBT_DUST_THRESHOLD) {
            loan.status = DataTypes.LoanStatus.Completed;
            loan.duration = 0;

            // Repay dust debt so lending pool allows full collateral withdrawal
            if (totalDebtRemaining > 0) {
                uint256 dustRepaid = bitmorPool.repayDustDebt(debtAsset, params.lsa, totalDebtRemaining);
                finalAmountRepaid += dustRepaid;
                emit ILoan.Loan__DustDebtAbsorbed(params.lsa, totalDebtRemaining);
            }

            /// @dev Withdraw Collateral `bvBTC` shares to `lsa`
            uint256 amountWithdrawn = params.lsa.withdrawCollateral(bitmorPool, collateralAsset, params.lsa);

            if (amountWithdrawn == 0) revert Errors.CollateralWithdrawFailed();

            /// @dev Redeem `bvBTC` shares for `btc` from BTC vault to the `borrower` address
            params.lsa.redeemBTC(collateralAsset, amountWithdrawn, loan.borrower, params.slippage_sharesToAsset);

            emit ILoan.Loan__Completed(params.lsa);
        } else {
            loan.amountRepaidInCurrentPeriod += finalAmountRepaid;
            uint256 periods = loan.amountRepaidInCurrentPeriod / loan.estimatedMonthlyPayment;
            if (periods > 0) {
                uint256 newDuration = loan.duration.zeroFloorSub(periods);

                /// @dev Duration stays `1` till the complete debt is repaid.
                loan.duration = newDuration == 0 ? 1 : newDuration;
                loan.amountRepaidInCurrentPeriod -= periods * loan.estimatedMonthlyPayment;
                loan.lastPaymentTimestamp = block.timestamp;
            }
        }

        // Refund any unspent amount to the payer
        if (finalAmountRepaid < maxRepayableAmt) {
            IERC20(debtAsset).safeTransfer(msg.sender, maxRepayableAmt - finalAmountRepaid);
        }

        emit ILoan.Loan__LoanRepaid(params.lsa, finalAmountRepaid);
    }
}
