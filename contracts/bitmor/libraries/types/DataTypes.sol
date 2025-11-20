// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

library DataTypes {
  // refer to the whitepaper, section 1.1 basic concepts for a formal description of these properties.
  struct ReserveData {
    //stores the reserve configuration
    ReserveConfigurationMap configuration;
    //the liquidity index. Expressed in ray
    uint128 liquidityIndex;
    //variable borrow index. Expressed in ray
    uint128 variableBorrowIndex;
    //the current supply rate. Expressed in ray
    uint128 currentLiquidityRate;
    //the current variable borrow rate. Expressed in ray
    uint128 currentVariableBorrowRate;
    //the current stable borrow rate. Expressed in ray
    uint128 currentStableBorrowRate;
    uint40 lastUpdateTimestamp;
    //tokens addresses
    address aTokenAddress;
    address stableDebtTokenAddress;
    address variableDebtTokenAddress;
    //address of the interest rate strategy
    address interestRateStrategyAddress;
    //the id of the reserve. Represents the position in the list of the active reserves
    uint8 id;
  }

  struct ReserveConfigurationMap {
    //bit 0-15: LTV
    //bit 16-31: Liq. threshold
    //bit 32-47: Liq. bonus
    //bit 48-55: Decimals
    //bit 56: Reserve is active
    //bit 57: reserve is frozen
    //bit 58: borrowing is enabled
    //bit 59: stable rate borrowing enabled
    //bit 60-63: reserved
    //bit 64-79: reserve factor
    uint256 data;
  }

  struct UserConfigurationMap {
    uint256 data;
  }

  enum InterestRateMode {
    NONE,
    STABLE,
    VARIABLE
  }

  struct ExecuteInitializeLoanParams {
    address user;
    uint256 depositAmount;
    uint256 premiumAmount;
    uint256 collateralAmount;
    uint256 duration;
    uint256 insuranceID;
  }

  struct InitializeLoanContext {
    address bitmorPool;
    address oracle;
    address collateralAsset;
    address debtAsset;
    address aavePool;
    address loanVaultFactory;
    address premiumCollector;
    uint256 maxCollateralAmt;
    uint256 loanRepaymentInterval;
  }

  struct ExecuteFLOperationParams {
    address asset;
    uint256 amount;
    uint256 premium;
    address initiator;
    bytes params;
  }

  struct ExecuteFLOperationContext {
    address aavePool;
    address bitmorPool;
    address zQuoter;
    address debtAsset;
    address collateralAsset;
    address swapAdapter;
    address feeCollector;
    uint256 maxSlippage;
  }

  struct ExecuteRepayParams {
    address lsa;
    uint256 amount;
  }

  struct ExecuteCloseLoanContext {
    address bitmorPool;
    address aavePool;
    address oracle;
    address debtAsset;
    address collateralAsset;
    uint256 preClosureFeeBps;
    uint256 maxSlippage;
  }

  struct ExecuteCloseLoanParams {
    address lsa;
    bool withdrawInCollateralAsset;
  }

  struct CalculateLoanAmountAndMonthlyPayment {
    address bitmorPool;
    address oracle;
    address collateralAsset;
    address debtAsset;
    uint256 depositAmount;
    uint256 debtAssetDecimals;
    uint256 collateralAmount;
    uint256 collateralAssetDecimals;
    uint256 duration;
  }

  struct CalculateLoanAmt {
    uint256 depositAmount;
    uint256 debtAssetDecimals;
    uint256 collateralAmount;
    uint256 collateralAssetDecimals;
    uint256 collateralPriceUSD;
    uint256 debtPriceUSD;
    uint256 interestRate;
    uint256 duration;
  }

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
   * @param lastPaymentTimestamp Timestamp at which last payment was made.
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
    uint256 lastPaymentTimestamp;
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
