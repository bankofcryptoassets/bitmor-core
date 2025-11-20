// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {DataTypes} from '../libraries/types/DataTypes.sol';

/**
 * @title ILoan
 * @notice Interface for the main Bitmor Protocol loan contract
 * @dev Defines all external functions for loan creation, management, and queries
 */
interface ILoan {
  // ============ Events ============

  event Loan__LoanCreated(
    address indexed borrower,
    address indexed lsa,
    uint256 loanAmount,
    uint256 collateralAmount
  );

  event Loan__LoanStatusUpdated(
    address indexed lsa,
    DataTypes.LoanStatus indexed oldStatus,
    DataTypes.LoanStatus indexed newStatus
  );

  event Loan__MaxLoanAmountUpdated(uint256 indexed newAmount);

  event Loan__ClosedLoan(address indexed lsa);

  event Loan__LoanVaultFactoryUpdated(address indexed newFactory);

  event Loan__EscrowUpdated(address indexed newEscrow);

  event Loan__SwapAdapterUpdated(address indexed newSwapAdapter);

  event Loan__ZQuoterUpdated(address indexed newZQuoter);

  event Loan__LoanRepaid(address indexed lsa, uint256 indexed amountRepaid);

  event Loan__LoanDataUpdated(address indexed lsa, bytes data);

  event Loan__PremiumCollectorUpdated(address indexed newPremiumCollector);

  event Loan__GracePeriodUpdated(uint256 indexed newGracePeriod);

  event Loan__PreClosureFeeUpdated(uint256 indexed newPreClosureFee);

  // ============ Main Functions ============

  /**
   * @notice Initializes a new loan with `depositAmount` USDC deposit
   * @dev Creates LSA, calculates loan terms, stores loan data on-chain, and executes flash loan flow
   * @param depositAmount USDC deposit amount (6 decimals)
   * @param premiumAmount USDC premium amount (6 decimals)
   * @param collateralAmount Target cbBTC amount user wants to achieve (8 decimals)
   * @param duration Loan duration in months
   * @param insuranceID Insurance/Order ID for tracking this loan
   * @param onBehalfOf User address on whose behalf of this loan will be created.
   * @return lsa Address of the created Loan Specific Address
   */
  function initializeLoan(
    uint256 depositAmount,
    uint256 premiumAmount,
    uint256 collateralAmount,
    uint256 duration,
    uint256 insuranceID,
    address onBehalfOf
  ) external returns (address lsa);

  // ============ View Functions ============

  /**
   * @notice Retrieves loan data for a specific LSA
   * @param lsa The LSA address
   * @return Loan data struct containing all loan information
   */
  function getLoanByLSA(address lsa) external view returns (DataTypes.LoanData memory);

  /**
   * @notice Gets total number of loans created by `user`
   * @param user The user address
   * @return Total loan count
   */
  function getUserLoanCount(address user) external view returns (uint256);

  /**
   * @notice Gets LSA address for user's Nth loan
   * @param user The user address
   * @param index Loan index (0-based)
   * @return LSA address
   */
  function getUserLoanAtIndex(address user, uint256 index) external view returns (address);

  /**
   * @notice Retrieves all loans for a specific `user`
   * @param user The user address
   * @return Array of loan data structs
   */
  function getUserAllLoans(address user) external view returns (DataTypes.LoanData[] memory);

  /**
   * @notice Gets the collateral asset address
   * @return cbBTC address
   */
  function getCollateralAsset() external view returns (address);

  /**
   * @notice Gets the debt asset address
   * @return USDC address
   */
  function getDebtAsset() external view returns (address);

  /**
   * @notice Calculates strike price for options based on `loanAmount` and `deposit`
   * @dev Formula: strike_price = btc_in_usd * loanAmount/(loanAmount + deposit) * 1.1
   * @param loanAmount The loan amount in USDC (6 decimals)
   * @param deposit The deposit amount in USDC (6 decimals)
   * @return strikePrice Strike price in USD (8 decimals)
   */
  function calculateStrikePrice(
    uint256 loanAmount,
    uint256 deposit
  ) external view returns (uint256 strikePrice);

  // ============ User Actions ============

  /**
   * @notice Allows borrower to repay their loan with `amount` USDC
   * @dev Repays debt on Aave V2 and updates loan state (loanAmount, lastPaymentTimestamp, nextDueTimestamp)
   * @param lsa The Loan Specific Address
   * @param amount Amount of USDC to repay (6 decimals)
   * @return finalAmountRepaid The actual amount repaid
   */
  function repay(address lsa, uint256 amount) external returns (uint256 finalAmountRepaid);

  /**
   * @notice Close the debt position of the `lsa` using flash loan and send the collateral asset or debt asset (as requested)
   * @dev Withdraws from escrow where excess collateral is locked
   * @param lsa The Loan Specific Address
   * @param withdrawInCollateralAsset If true, the collateral asset will be transfered to the `loan.borrower` else collateral value worth of debt asset will be transferred.
   */
  function closeLoan(address lsa, bool withdrawInCollateralAsset) external;

  // ============ Admin Functions ============

  /**
   * @notice Updates the loan vault factory address
   * @param newFactory New factory address
   */
  function setLoanVaultFactory(address newFactory) external;

  /**
   * @notice Updates the swap adapter contract address
   * @param newSwapAdapter New swap adapter address
   */
  function setSwapAdapter(address newSwapAdapter) external;

  /**
   * @notice Updates the zQuoter contract address
   * @param newZQuoter New zQuoter address
   */
  function setZQuoter(address newZQuoter) external;

  /**
   * @notice Updates loan status for a specific `lsa`
   * @dev Used by repayment and liquidation flows
   * @param lsa The LSA address
   * @param newStatus The new loan status
   */
  function updateLoanStatus(address lsa, DataTypes.LoanStatus newStatus) external;

  /**
   * @notice Updates the LoanData for a specific `lsa`
   * @param _data Encoded LoanData struct
   * @param _lsa The Loan Specific Address
   */
  function updateLoanData(bytes calldata _data, address _lsa) external;

  /**
   * @notice Updates the premium collector address
   * @param newPremiumCollector New premium collector address
   */
  function setPremiumCollector(address newPremiumCollector) external;

  /**
   * @notice Get the premium collector address
   */
  function getPremiumCollector() external view returns (address premiumCollector);

  /**
   * @notice Updates the grace period for microLiquidation.
   * @param gracePeriod New grace period in `days`
   */
  function setGracePeriod(uint256 gracePeriod) external;

  /**
   * @notice Returns the `s_gracePeriod`.
   */
  function getGracePeriod() external view returns (uint256 gracePeriod);

  /**
   * @notice Returns `LOAN_REPAYMENT_INTERVAL` constant value.
   */
  function getRepaymentInterval() external view returns (uint256);

  /**
   * @notice Returns the loan pre-closure fee (in bps)
   */
  function getPreClosureFee() external view returns (uint256);

  /**
   * @notice Updates the pre-closure fee (in bps)
   */
  function setPreClosureFee(uint256 newFee) external;

  /**
   * @notice Getter function to calculate the loan details based on the `collateralAmount` and `duration` of the Loan.
   * @param collateralAmount Collateral asset amount
   * @param duration Duration of the loan
   * @return loanAmount Debt asset amount
   * @return monthlyPayment estimated monthly payment amount in debt asset
   * @return minDepositRequired Minimum deposit required in debt asset to initialize loan
   */
  function getLoanDetails(
    uint256 collateralAmount,
    uint256 duration
  ) external view returns (uint256 loanAmount, uint256 monthlyPayment, uint256 minDepositRequired);
}
