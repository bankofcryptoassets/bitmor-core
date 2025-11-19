// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {BitmorLendingPoolLogic} from './BitmorLendingPoolLogic.sol';
import {ILoan} from '../../interfaces/ILoan.sol';
import {DataTypes} from '../types/DataTypes.sol';
import {Errors} from '../helpers/Errors.sol';
import {LoanMath} from '../helpers/LoanMath.sol';
import {IERC20} from '../../dependencies/openzeppelin/IERC20.sol';
import {SafeERC20} from '../../dependencies/openzeppelin/SafeERC20.sol';
import {LSALogic} from './LSALogic.sol';

library RepayLogic {
  using SafeERC20 for IERC20;

  /**
   * Execute Repay checks the `params.lsa` debt position and calculates and repay the `maxRepayableAmt` to the Bitmor Lending Pool. With `finalAmountRepaid` the duration of the Loan is changed accordingly, i.e, if there's no remainig debt then the `loan` status updated to `Completed` and `duration` sets to zero, else the duration is deducted based on the no of `periods` `maxRepayableAmt` has covered.
   * @param bitmorPool Bitmor Lending Pool address
   * @param debtAsset Debt asset address
   * @param params Params the function is being called with.
   * @param loansByLSA Mapping of all the loans.
   */
  function executeRepay(
    address bitmorPool,
    address debtAsset,
    address collateralAsset,
    DataTypes.ExecuteRepayParams memory params,
    mapping(address => DataTypes.LoanData) storage loansByLSA
  ) internal returns (uint256 finalAmountRepaid) {
    if (params.lsa == address(0)) revert Errors.ZeroAddress();
    if (params.amount == 0) revert Errors.ZeroAmount();

    DataTypes.LoanData storage loan = loansByLSA[params.lsa];

    if (loan.borrower == address(0)) revert Errors.LoanDoesNotExists();
    if (loan.status != DataTypes.LoanStatus.Active) revert Errors.LoanIsNotActive();

    // Cap the requested amount to outstanding principal so we never custody more than needed
    (, uint256 totalDebt) = BitmorLendingPoolLogic.getUserPositions(bitmorPool, params.lsa);
    uint256 maxRepayableAmt = LoanMath.min(params.amount, totalDebt);

    // Pull only what might be needed from the borrower
    IERC20(debtAsset).safeTransferFrom(msg.sender, address(this), maxRepayableAmt);

    // Approve Aave V2 pool (the spender) to pull from THIS contract
    IERC20(debtAsset).forceApprove(bitmorPool, maxRepayableAmt);

    // Execute repayment on Aave V2; pool will pull up to `maxRepayableAmt`
    finalAmountRepaid = BitmorLendingPoolLogic.executeLoanRepayment(
      bitmorPool,
      debtAsset,
      params.lsa,
      maxRepayableAmt
    );

    // Update accounting
    (, uint256 totalDebtRemaining) = BitmorLendingPoolLogic.getUserPositions(
      bitmorPool,
      params.lsa
    );

    // Advance schedule only if loan remains active
    if (totalDebtRemaining == 0) {
      // Fully repaid

      loan.status = DataTypes.LoanStatus.Completed;
      loan.duration = 0;

      uint256 amountWithdrawn = LSALogic.withdrawCollateral(
        bitmorPool,
        params.lsa,
        collateralAsset,
        loan.borrower
      );

      if (amountWithdrawn == 0) revert Errors.CollateralWithdrawFailed();
    } else {
      uint256 emp = loan.estimatedMonthlyPayment;
      uint256 periods = 1;
      if (emp > 0) {
        // ceilDiv: (a + b - 1) / b
        periods = (finalAmountRepaid + emp - 1) / (emp);
        if (periods == 0) {
          periods = 1;
        }
      }
      loan.duration -= periods;
    }

    // Refund any unspent amount to the payer
    if (finalAmountRepaid < maxRepayableAmt) {
      IERC20(debtAsset).safeTransfer(msg.sender, maxRepayableAmt - finalAmountRepaid);
    }

    emit ILoan.Loan__LoanRepaid(params.lsa, finalAmountRepaid);
  }
}
