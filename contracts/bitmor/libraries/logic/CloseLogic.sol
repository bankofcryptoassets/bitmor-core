// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {DataTypes} from '../types/DataTypes.sol';
import {ILoan} from '../../interfaces/ILoan.sol';
import {Errors} from '../helpers/Errors.sol';
import {BitmorLendingPoolLogic} from './BitmorLendingPoolLogic.sol';
import {IERC20} from '../../dependencies/openzeppelin/IERC20.sol';
import {SafeERC20} from '../../dependencies/openzeppelin/SafeERC20.sol';

library CloseLogic {
  using SafeERC20 for IERC20;

  function executeClose(
    DataTypes.CloseContext memory ctx,
    DataTypes.ExecuteCloseParams memory params,
    mapping(address => DataTypes.LoanData) storage loansByLSA
  ) internal returns (uint256 finalAmountRepaid, uint256 amountWithdrawn) {
    DataTypes.LoanData storage loan = loansByLSA[params.lsa];

    if (loan.status != DataTypes.LoanStatus.Active) revert Errors.LoanIsNotActive();

    uint256 totalDebtAmt = BitmorLendingPoolLogic.getUserCurrentDebt(ctx.bitmorPool, params.lsa);

    if (params.amount < totalDebtAmt)
      revert Errors.InsufficientAmountSuppliedForClosure(totalDebtAmt, params.amount);

    IERC20(ctx.debtAsset).safeTransferFrom(msg.sender, address(this), totalDebtAmt);

    IERC20(ctx.debtAsset).forceApprove(ctx.bitmorPool, totalDebtAmt);
    (finalAmountRepaid, amountWithdrawn) = BitmorLendingPoolLogic.closeLoan(
      ctx.bitmorPool,
      params.lsa,
      ctx.debtAsset,
      ctx.collateralAsset,
      msg.sender,
      totalDebtAmt,
      loan
    );

    emit ILoan.Loan__ClosedLoan(params.lsa, finalAmountRepaid, amountWithdrawn);
  }
}
