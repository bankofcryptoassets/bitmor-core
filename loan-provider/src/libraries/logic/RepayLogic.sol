// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IERC20 } from "@openzeppelin/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

import { DataTypes } from "../types/DataTypes.sol";
import { ILoan } from "../../interfaces/ILoan.sol";

import { Errors } from "../helpers/Errors.sol";
import { LoanMath } from "../helpers/LoanMath.sol";

import { LSALogic } from "./LSALogic.sol";
import { BitmorLendingPoolLogic } from "./BitmorLendingPoolLogic.sol";

/**
 * @title RepayLogic
 * @author Bitmor Protocol
 * @notice Library for loan repayment execution logic
 * @dev Handles the full repayment flow including validation, execution, and state updates.
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
     * @param bitmorPool Bitmor Lending Pool address
     * @param debtAsset Debt asset address (USDC)
     * @param collateralAsset Collateral asset address (cbBTC)
     * @param params Repayment parameters containing LSA and amount
     * @param loansByLSA Storage mapping of all loans by LSA
     * @return finalAmountRepaid The actual amount repaid to the pool
     */
    function executeRepay(
        address bitmorPool,
        address debtAsset,
        address collateralAsset,
        DataTypes.ExecuteRepayParams memory params,
        mapping(address => DataTypes.LoanData) storage loansByLSA
    ) internal returns (uint256 finalAmountRepaid) {
        if (params.lsa == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (params.amount == 0) revert Errors.ZeroAmount();

        DataTypes.LoanData storage loan = loansByLSA[params.lsa];

        if (loan.borrower == address(0)) revert Errors.LoanDoesNotExists();
        if (loan.status != DataTypes.LoanStatus.Active) revert Errors.LoanIsNotActive();

        // Cap the requested amount to outstanding principal so we never custody more than needed
        uint256 totalDebt = bitmorPool.getVDTTokenAmount(debtAsset, params.lsa);
        uint256 maxRepayableAmt = LoanMath.min(params.amount, totalDebt);

        // Pull only what might be needed from the borrower
        IERC20(debtAsset).safeTransferFrom(msg.sender, address(this), maxRepayableAmt);

        // Approve Aave V2 pool (the spender) to pull from THIS contract
        IERC20(debtAsset).forceApprove(bitmorPool, maxRepayableAmt);

        // Execute repayment on Aave V2; pool will pull up to `maxRepayableAmt`
        finalAmountRepaid = bitmorPool.executeLoanRepayment(debtAsset, params.lsa, maxRepayableAmt);

        // Update accounting
        uint256 totalDebtRemaining = bitmorPool.getVDTTokenAmount(debtAsset, params.lsa);

        // Advance schedule only if loan remains active
        if (totalDebtRemaining == 0) {
            // Fully repaid

            loan.status = DataTypes.LoanStatus.Completed;
            loan.duration = 0;

            /// @dev Withdraw Collateral `bvBTC` shares to `lsa`
            uint256 amountWithdrawn = params.lsa.withdrawCollateral(
                bitmorPool,
                collateralAsset,
                params.lsa
            );

            if (amountWithdrawn == 0) revert Errors.CollateralWithdrawFailed();

            /// @dev Redeem `btc` for `bvBTC` shares from BTC vault to the `borrower` address
            params.lsa.redeemBTC(
                collateralAsset,
                amountWithdrawn,
                loan.borrower,
                params.slippage_sharesToAsset
            );

            emit ILoan.Loan__Completed(params.lsa);
        } else {
            loan.amountRepaidInCurrentPeriod += finalAmountRepaid;
            uint256 periods = loan.amountRepaidInCurrentPeriod / loan.estimatedMonthlyPayment;
            if (periods > 0) {
                loan.duration = loan.duration.zeroFloorSub(periods);
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
