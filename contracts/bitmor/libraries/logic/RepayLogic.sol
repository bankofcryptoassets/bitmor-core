// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {SafeMath} from '../../../dependencies/openzeppelin/contracts/SafeMath.sol';
import {ILendingPool} from '../../../interfaces/ILendingPool.sol';
import {DataTypes} from '../types/DataTypes.sol';

library RepayLogic {
  using SafeMath for uint256;

  function executeLoanRepayment(
    DataTypes.LoanData storage loanData,
    address aaveV2Pool,
    address debtAsset,
    address lsa,
    uint256 amount
  ) internal returns (uint256 finalAmountRepaid, uint256 nextDueTimestamp) {
    // Bitmor uses variable-rate borrowing on Aave V2
    uint256 RATE_MODE = 2;

    // NOTE: Allowance must be set by the caller (Loan.sol) that holds the funds.
    // Aave V2 will pull up to `amount` from the caller (Loan.sol) during `repay`.

    uint256 beforeDebt = loanData.loanAmount;

    finalAmountRepaid = ILendingPool(aaveV2Pool).repay(debtAsset, amount, RATE_MODE, lsa);

    // Update accounting
    uint256 afterDebt = beforeDebt.sub(finalAmountRepaid);
    loanData.loanAmount = afterDebt;
    loanData.lastDueTimestamp = block.timestamp;

    // Advance schedule only if loan remains active
    if (afterDebt == 0) {
      // Fully repaid
      nextDueTimestamp = loanData.nextDueTimestamp; // keep as-is (or could set 0 by design)
      loanData.status = DataTypes.LoanStatus.Completed;
    } else {
      nextDueTimestamp = loanData.nextDueTimestamp.add(30 days);
      loanData.nextDueTimestamp = nextDueTimestamp;
    }

    return (finalAmountRepaid, nextDueTimestamp);
  }
}
