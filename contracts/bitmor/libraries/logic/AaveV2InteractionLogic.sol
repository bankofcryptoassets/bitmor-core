// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {SafeERC20} from '../../dependencies/openzeppelin/SafeERC20.sol';
import {IERC20} from '../../dependencies/openzeppelin/IERC20.sol';
import {ILendingPool} from '../../interfaces/ILendingPool.sol';
import {DataTypes} from '../types/DataTypes.sol';
import {ILoanVault} from '../../interfaces/ILoanVault.sol';
import {DataTypes as BitmorDataTypes} from '../types/DataTypes.sol';

/**
 * @title AaveV2InteractionLogic
 * @notice Handles deposits and borrows on Aave V2 lending pool
 */

library AaveV2InteractionLogic {
  using SafeERC20 for IERC20;

  uint256 constant MAX_U256 = type(uint256).max;
  uint256 constant RATE_MODE = 2;

  /**
   * @notice Deposits collateral to Aave V2 on behalf of LSA
   * @dev LSA receives aTokens (acbBTC), Protocol holds cbBTC before deposit
   * @param aaveV2Pool Aave V2 lending pool address
   * @param asset Collateral asset (cbBTC)
   * @param amount Amount to deposit (8 decimals)
   * @param onBehalfOf LSA address that receives aTokens
   */
  function depositCollateral(
    address aaveV2Pool,
    address asset,
    uint256 amount,
    address onBehalfOf
  ) internal {
    require(amount > 0, 'AaveV2InteractionLogic: invalid deposit amount');
    require(onBehalfOf != address(0), 'AaveV2InteractionLogic: invalid onBehalfOf');

    // Approve Aave V2 pool to spend asset
    IERC20(asset).forceApprove(aaveV2Pool, amount);

    ILendingPool(aaveV2Pool).deposit(asset, amount, onBehalfOf, 0);
  }

  /**
   * @notice Borrows debt from Aave V2 on behalf of LSA
   * @dev Protocol receives USDC, LSA receives variable debt tokens
   * @param aaveV2Pool Aave V2 lending pool address
   * @param asset Debt asset (USDC)
   * @param amount Amount to borrow (6 decimals)
   * @param onBehalfOf LSA address that receives debt tokens
   */
  function borrowDebt(
    address aaveV2Pool,
    address asset,
    uint256 amount,
    address onBehalfOf
  ) internal {
    require(amount > 0, 'AaveV2InteractionLogic: invalid borrow amount');
    require(onBehalfOf != address(0), 'AaveV2InteractionLogic: invalid onBehalfOf');

    // Borrow from Aave V2 - onBehalfOf receives debt, caller receives USDC
    ILendingPool(aaveV2Pool).borrow(asset, amount, 2, 0, onBehalfOf);
  }

  /**
   * @notice Retrieves aToken address for given asset
   * @dev Used to get acbBTC address for collateral locking
   * @param aaveV2Pool Aave V2 lending pool address
   * @param asset Underlying asset (cbBTC)
   * @return aToken address (acbBTC)
   */
  function getATokenAddress(address aaveV2Pool, address asset) internal view returns (address) {
    DataTypes.ReserveData memory reserveData = ILendingPool(aaveV2Pool).getReserveData(asset);
    address aToken = reserveData.aTokenAddress;

    require(aToken != address(0), 'AaveV2InteractionLogic: invalid aToken');
    return aToken;
  }

  function getUserCurrentDebt(
    address aaveV2Pool,
    address lsa
  ) internal view returns (uint256 totalDebt) {
    (, totalDebt, , , , ) = ILendingPool(aaveV2Pool).getUserAccountData(lsa);
  }

  function closeLoan(
    address aaveV2Pool,
    address lsa,
    address debtAsset,
    address cbBTC,
    address recipient,
    uint256 repaymentAmount
  ) internal returns (uint256 finalAmountRepaid, uint256 amountWithdrawn) {
    finalAmountRepaid = ILendingPool(aaveV2Pool).repay(debtAsset, MAX_U256, RATE_MODE, lsa);

    // LSA calls aaveV2Pool.withdraw(cbBTC, amount, recipient)
    // This will:
    //   - Burn acbBTC from LSA
    //   - Send cbBTC to recipient
    //   - Validate health factor > 1.0 (Aave's built-in check) @Note @TODO: This is something which we may have to remove as we have insurance in place.
    bytes memory withdrawData = abi.encodeWithSignature(
      'withdraw(address,uint256,address)',
      cbBTC,
      MAX_U256,
      recipient
    );

    bytes memory result = ILoanVault(lsa).execute(aaveV2Pool, withdrawData);

    // Decode the actual amount withdrawn
    amountWithdrawn = abi.decode(result, (uint256));

    require(amountWithdrawn > 0, 'WithdrawalLogic: withdrawal failed');

    return (finalAmountRepaid, amountWithdrawn);
  }

  /**
   * @notice Executes loan repayment on Aave V2 and updates loan state
   * @dev Updates loanAmount, lastDueTimestamp, nextDueTimestamp, and status. Marks loan as Completed if fully repaid.
   * @param loanData Storage reference to the loan being repaid
   * @param aaveV2Pool Aave V2 lending pool address
   * @param debtAsset USDC token address (debt asset)
   * @param lsa Loan Specific Address (the borrower address on Aave)
   * @param amount Maximum amount to repay (actual repaid may be less if debt is smaller)
   * @return finalAmountRepaid Actual amount repaid to Aave
   * @return nextDueTimestamp Updated next payment due timestamp (or current if fully repaid)
   */
  function executeLoanRepayment(
    BitmorDataTypes.LoanData storage loanData,
    address aaveV2Pool,
    address debtAsset,
    address lsa,
    uint256 amount
  ) internal returns (uint256 finalAmountRepaid, uint256 nextDueTimestamp) {
    // NOTE: Allowance must be set by the caller (Loan.sol) that holds the funds.
    // Aave V2 will pull up to `amount` from the caller (Loan.sol) during `repay`.

    uint256 beforeDebt = loanData.loanAmount;

    finalAmountRepaid = ILendingPool(aaveV2Pool).repay(debtAsset, amount, RATE_MODE, lsa);

    // Update accounting
    uint256 afterDebt = beforeDebt - finalAmountRepaid;
    loanData.loanAmount = afterDebt;
    loanData.lastDueTimestamp = block.timestamp;

    // Advance schedule only if loan remains active
    if (afterDebt == 0) {
      // Fully repaid
      nextDueTimestamp = loanData.nextDueTimestamp;
      loanData.status = BitmorDataTypes.LoanStatus.Completed;
    } else {
      uint256 emp = loanData.estimatedMonthlyPayment;
      uint256 periods = 1;
      if (emp > 0) {
        // ceilDiv: (a + b - 1) / b
        periods = (finalAmountRepaid + emp - 1) / (emp);
        if (periods == 0) {
          periods = 1;
        }
      }
      nextDueTimestamp = loanData.nextDueTimestamp + (periods * (30 days));
      loanData.nextDueTimestamp = nextDueTimestamp;
    }

    return (finalAmountRepaid, nextDueTimestamp);
  }
}
