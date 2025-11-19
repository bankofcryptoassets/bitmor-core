// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {ILendingPool} from '../../interfaces/ILendingPool.sol';

/**
 * @title BitmorLendingPoolLogic
 * @notice Handles deposits and borrows on Bitmor Lending Pool
 */

library BitmorLendingPoolLogic {
  uint256 constant RATE_MODE = 2;
  uint16 constant REFERRAL = 0;

  /**
   * @notice Deposits collateral to Aave V2 on behalf of LSA
   * @dev LSA receives aTokens (acbBTC), Protocol holds cbBTC before deposit
   * @param bitmorPool Bitmor Lending Pool address
   * @param asset Collateral asset (cbBTC)
   * @param amount Amount to deposit (8 decimals)
   * @param onBehalfOf LSA address that receives aTokens
   */
  function depositCollateral(
    address bitmorPool,
    address asset,
    uint256 amount,
    address onBehalfOf
  ) internal {
    ILendingPool(bitmorPool).deposit(asset, amount, onBehalfOf, REFERRAL);
  }

  /**
   * @notice Borrows debt from Aave V2 on behalf of LSA
   * @dev Protocol receives USDC, LSA receives variable debt tokens
   * @param bitmorPool Bitmor Lending Pool address
   * @param asset Debt asset (USDC)
   * @param amount Amount to borrow (6 decimals)
   * @param onBehalfOf LSA address that receives debt tokens
   */
  function borrowDebt(
    address bitmorPool,
    address asset,
    uint256 amount,
    address onBehalfOf
  ) internal {
    // Borrow from Aave V2 - onBehalfOf receives debt, caller receives USDC
    ILendingPool(bitmorPool).borrow(asset, amount, RATE_MODE, REFERRAL, onBehalfOf);
  }

  /**
   * @notice Get the latest position value of the `lsa` in `bitmorPool`.
   * @param lsa Loan Vault Address
   * @return totalCollateral Total collateral asset value in USD hold by LSA
   * @return totalDebt Total debt asset value in USD hold by LSA
   */
  function getUserPositions(
    address bitmorPool,
    address lsa
  ) internal view returns (uint256 totalCollateral, uint256 totalDebt) {
    (totalCollateral, totalDebt, , , , ) = ILendingPool(bitmorPool).getUserAccountData(lsa);
  }

  /**
   * @notice Executes loan repayment on Aave V2 and updates loan state
   * @dev Updates loanAmount, lastPaymentTimestamp, nextDueTimestamp, and status. Marks loan as Completed if fully repaid.
   * @param bitmorPool Bitmor Lending Pool address
   * @param debtAsset USDC token address (debt asset)
   * @param lsa Loan Specific Address (the borrower address on Aave)
   * @param amount Maximum amount to repay (actual repaid may be less if debt is smaller)
   * @return finalAmountRepaid Actual amount repaid to Aave
   */
  function executeLoanRepayment(
    address bitmorPool,
    address debtAsset,
    address lsa,
    uint256 amount
  ) internal returns (uint256 finalAmountRepaid) {
    // NOTE: Allowance must be set by the caller (Loan.sol) that holds the funds.
    // Aave V2 will pull up to `amount` from the caller (Loan.sol) during `repay`.
    finalAmountRepaid = ILendingPool(bitmorPool).repay(debtAsset, amount, RATE_MODE, lsa);
  }
}
