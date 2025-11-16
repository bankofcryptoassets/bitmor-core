// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {AaveV2InteractionLogic} from './AaveV2InteractionLogic.sol';
import {ILoan} from '../../interfaces/ILoan.sol';
import {DataTypes} from '../types/DataTypes.sol';
import {Errors} from '../helpers/Errors.sol';
import {LoanMath} from '../helpers/LoanMath.sol';
import {IERC20} from '../../dependencies/openzeppelin/IERC20.sol';
import {SafeERC20} from '../../dependencies/openzeppelin/SafeERC20.sol';

library RepayLogic {
  using SafeERC20 for IERC20;

  function executeRepay(
    address bitmorPool,
    address debtAsset,
    DataTypes.ExecuteRepayParams memory params,
    mapping(address => DataTypes.LoanData) storage loansByLSA
  ) internal returns (uint256 finalAmountRepaid, uint256 nextDueTimestamp) {
    if (params.lsa == address(0)) revert Errors.ZeroAddress();
    if (params.amount == 0) revert Errors.ZeroAmount();

    DataTypes.LoanData storage loan = loansByLSA[params.lsa];

    if (loan.borrower == address(0)) revert Errors.LoanDoesNotExists();
    if (loan.status != DataTypes.LoanStatus.Active) revert Errors.LoanIsNotActive();

    // Cap the requested amount to outstanding principal so we never custody more than needed
    uint256 maxRepayableAmt = LoanMath.min(params.amount, loan.loanAmount);

    // Pull only what might be needed from the borrower
    IERC20(debtAsset).safeTransferFrom(msg.sender, address(this), maxRepayableAmt);

    // Approve Aave V2 pool (the spender) to pull from THIS contract
    IERC20(debtAsset).forceApprove(bitmorPool, maxRepayableAmt);

    // Execute repayment on Aave V2; pool will pull up to `maxRepayableAmt`
    (finalAmountRepaid, nextDueTimestamp) = AaveV2InteractionLogic.executeLoanRepayment(
      loan,
      bitmorPool,
      debtAsset,
      params.lsa,
      maxRepayableAmt
    );

    // Refund any unspent amount to the payer
    if (finalAmountRepaid < maxRepayableAmt) {
      IERC20(debtAsset).safeTransfer(msg.sender, maxRepayableAmt - finalAmountRepaid);
    }

    emit ILoan.Loan__LoanRepaid(params.lsa, finalAmountRepaid, nextDueTimestamp);
  }
}
