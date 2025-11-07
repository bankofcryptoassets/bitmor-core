// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

library DataTypes {
  // ============ Loan Data Structure ============

  /**
   * @notice Complete loan information stored per LSA
   * @param borrower The address that created and owns this loan
   * @param depositAmount Initial USDC deposit amount (6 decimals)
   * @param loanAmount Total amount borrowed via flash loan (6 decimals)
   * @param collateralAmount cbBTC amount user wants to achieve (8 decimals)
   * @param estimatedMonthlyPayment Estimated monthly payment calculated at creation (6 decimals)
   * @param duration Loan term length in months
   * @param createdAt Unix timestamp when loan was created
   * @param insuranceID Insurance/Order ID for tracking this loan
   * @param nextDueTimestamp Unix timestamp of the next payment due date (updated during repayments)
   * @param lastDueTimestamp Unix timestamp when the last payment was made (0 if no payments yet, updated during repayments)
   * @param status Current lifecycle status of the loan
   */
  struct LoanData {
    address borrower;
    uint256 depositAmount;
    uint256 loanAmount;
    uint256 collateralAmount;
    uint256 estimatedMonthlyPayment;
    uint256 duration;
    uint256 createdAt;
    uint256 insuranceID;
    uint256 nextDueTimestamp;
    uint256 lastDueTimestamp;
    LoanStatus status;
  }

  // ============ Loan Status ============

  /**
   * @notice Represents the current state of a loan
   * @dev Active: Loan is ongoing and being repaid
   * @dev Completed: Loan has been fully repaid
   * @dev Liquidated: Loan was liquidated due to insufficient collateral or other reasons
   */
  enum LoanStatus {
    Active,
    Completed,
    Liquidated
  }
}
