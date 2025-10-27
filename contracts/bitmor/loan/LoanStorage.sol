// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

/**
 * @title LoanStorage
 * @notice Storage layout for Bitmor Protocol loan management
 * @dev Contains all state variables for tracking loans and protocol configuration
 */
contract LoanStorage {
  // ============ Immutable Protocol Addresses ============

  /// @notice Aave V3 pool address for flash loan operations
  address public immutable AAVE_V3_POOL;

  /// @notice Bonzo lending pool address for collateral deposits and debt borrowing
  address public immutable AAVE_RESERVE;

  /// @notice Bonzo addresses provider for accessing protocol contracts (oracle, etc.)
  address public immutable BONZO_ADDRESSES_PROVIDER;

  // ============ Protocol Contract Addresses ============

  /// @notice Factory contract for deploying Loan Specific Address (LSAs)
  address public loanVaultFactory;

  /// @notice Escrow contract for holding locked collateral
  address public escrow;

  /// @notice Swap adapter contract for executing token swaps
  address public swapAdapter;

  // ============ Asset Configuration ============

  /// @notice Collateral asset address (WBTC)
  address internal _collateralAsset;

  /// @notice Debt asset address (USDC)
  address internal _debtAsset;

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

  // ============ Loan Data Structure ============

  /**
   * @notice Complete loan information stored per LSA
   * @param borrower The address that created and owns this loan
   * @param depositAmount Initial USDC deposit amount (6 decimals)
   * @param loanAmount Total amount borrowed via flash loan (6 decimals)
   * @param collateralAmount WBTC amount user wants to achieve (8 decimals)
   * @param estimatedMonthlyPayment Estimated monthly payment calculated at creation (6 decimals)
   * @param interestRateAtCreation Bonzo's variable borrow rate snapshot at loan creation (27 decimals - ray)
   * @param duration Loan term length in months
   * @param createdAt Unix timestamp when loan was created
   * @param insuranceID Insurance/Order ID for tracking this loan
   * @param nextDueTimestamp Unix timestamp of the next payment due date (updated during repayments)
   * @param lastDueTimestamp Unix timestamp of the last payment due date (updated during repayments)
   * @param status Current lifecycle status of the loan
   */
  struct LoanData {
    address borrower;
    uint256 depositAmount;
    uint256 loanAmount;
    uint256 collateralAmount;
    uint256 estimatedMonthlyPayment;
    uint256 interestRateAtCreation;
    uint256 duration;
    uint256 createdAt;
    uint256 insuranceID;
    uint256 nextDueTimestamp;
    uint256 lastDueTimestamp;
    LoanStatus status;
  }

  // ============ Storage Mappings ============

  /// @notice Maps LSA addresses to their loan data
  /// @dev Primary storage for all loan information
  mapping(address => LoanData) internal _loansByLSA;

  /// @notice Tracks the total number of loans created by each user
  /// @dev Used to index and iterate through user's loans
  mapping(address => uint256) public userLoanCount;

  /// @notice Maps user address and index to their LSA addresses
  /// @dev Enables retrieval of user's Nth loan: userLoanAtIndex[user][0] returns first loan's LSA
  mapping(address => mapping(uint256 => address)) public userLoanAtIndex;

  // ============ Protocol Parameters ============

  /// @notice Maximum loan amount allowed per loan (6 decimals for USDC)
  /// @dev Can be updated by admin to manage protocol risk
  uint256 public maxLoanAmount;

  // ============ Events ============

  event LoanCreated(
    address indexed borrower,
    address indexed lsa,
    uint256 loanAmount,
    uint256 collateralAmount,
    uint256 createdAt
  );

  event LoanStatusUpdated(address indexed lsa, LoanStatus oldStatus, LoanStatus newStatus);

  event MaxLoanAmountUpdated(uint256 oldAmount, uint256 newAmount);

  // ============ Constants ============

  /// @notice Basis points denominator for percentage calculations (10000 = 100%)
  uint256 internal constant BASIS_POINTS = 10000;

  // ============ Constructor ============

  /**
   * @notice Initializes the storage contract with immutable protocol addresses
   * @param _aavePool Aave V3 pool address
   * @param _bonzoPool Bonzo lending pool address
   * @param _bonzoAddressesProvider Bonzo addresses provider address
   */
  constructor(address _aavePool, address _bonzoPool, address _bonzoAddressesProvider) public {
    require(_aavePool != address(0), 'Invalid Aave pool');
    require(_bonzoPool != address(0), 'Invalid Bonzo pool');
    require(_bonzoAddressesProvider != address(0), 'Invalid addresses provider');

    AAVE_V3_POOL = _aavePool;
    AAVE_RESERVE = _bonzoPool;
    BONZO_ADDRESSES_PROVIDER = _bonzoAddressesProvider;
  }
}
