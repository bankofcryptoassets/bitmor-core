// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {BitmorLendingPoolLogic} from "./BitmorLendingPoolLogic.sol";
import {ILoan} from "../../interfaces/ILoan.sol";
import {DataTypes} from "../types/DataTypes.sol";
import {Errors} from "../helpers/Errors.sol";
import {LoanMath} from "../helpers/LoanMath.sol";
import {IERC20} from "../../dependencies/openzeppelin/IERC20.sol";
import {SafeERC20} from "../../dependencies/openzeppelin/SafeERC20.sol";
import {LSALogic} from "./LSALogic.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

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
 * 5. Updates loan state (duration, status)
 * 6. Withdraws collateral if fully repaid
 * 7. Refunds excess payment if any
 */
library RepayLogic {
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;

    /**
     * @notice Executes a loan repayment for a specific LSA
     * @dev Checks the LSA debt position, calculates the repayable amount, and executes
     * repayment to the Bitmor Lending Pool. Updates loan duration based on amount repaid.
     *
     * ## State Changes
     * - If fully repaid: status = `Completed`, duration = 0, collateral withdrawn to borrower
     * - If partial: duration reduced by number of periods covered
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
        uint256 totalDebt = BitmorLendingPoolLogic.getVDTTokenAmount(bitmorPool, debtAsset, params.lsa);
        uint256 maxRepayableAmt = LoanMath.min(params.amount, totalDebt);

        // Pull only what might be needed from the borrower
        IERC20(debtAsset).safeTransferFrom(msg.sender, address(this), maxRepayableAmt);

        // Approve Aave V2 pool (the spender) to pull from THIS contract
        IERC20(debtAsset).forceApprove(bitmorPool, maxRepayableAmt);

        // Execute repayment on Aave V2; pool will pull up to `maxRepayableAmt`
        finalAmountRepaid =
            BitmorLendingPoolLogic.executeLoanRepayment(bitmorPool, debtAsset, params.lsa, maxRepayableAmt);

        // Update accounting
        uint256 totalDebtRemaining = BitmorLendingPoolLogic.getVDTTokenAmount(bitmorPool, debtAsset, params.lsa);

        // Advance schedule only if loan remains active
        if (totalDebtRemaining == 0) {
            // Fully repaid

            loan.status = DataTypes.LoanStatus.Completed;
            loan.duration = 0;

            uint256 amountWithdrawn =
                LSALogic.withdrawCollateral(bitmorPool, params.lsa, collateralAsset, loan.borrower);

            if (amountWithdrawn == 0) revert Errors.CollateralWithdrawFailed();
        } else {
            uint256 periods = finalAmountRepaid.mulDiv(1, loan.estimatedMonthlyPayment);
            loan.duration -= periods;
        }

        // Refund any unspent amount to the payer
        if (finalAmountRepaid < maxRepayableAmt) {
            IERC20(debtAsset).safeTransfer(msg.sender, maxRepayableAmt - finalAmountRepaid);
        }

        emit ILoan.Loan__LoanRepaid(params.lsa, finalAmountRepaid);
    }
}
