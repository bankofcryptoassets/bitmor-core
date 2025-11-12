// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {DataTypes} from '../libraries/types/DataTypes.sol';

/**
 * @title LoanStorage
 * @notice Storage layout for Bitmor Protocol loan management
 * @dev Contains all state variables for tracking loans and protocol configuration
 */
contract LoanStorage {
  // ============ Immutable Protocol Addresses ============

  /// @notice Aave V3 pool address for flash loan operations
  address public immutable i_AAVE_V3_POOL;

  /// @notice Bitmor Lending Pool address for collateral deposits and debt borrowing
  address public immutable i_AAVE_V2_POOL;

  /// @notice Aave V2 addresses provider for accessing protocol contracts (oracle, etc.)
  address public immutable i_ORACLE;

  /// @notice Collateral asset address (cbBTC)
  address internal immutable i_collateralAsset;

  /// @notice Debt asset address (USDC)
  address internal immutable i_debtAsset;

  // ============ Protocol Contract Addresses ============

  /// @notice Factory contract for deploying Loan Specific Address (LSAs)
  address public s_loanVaultFactory;

  /// @notice Escrow contract for holding locked collateral
  address public s_escrow;

  /// @notice Swap adapter contract for executing token swaps
  address public s_swapAdapter;

  /// @notice zQuoter contract for price quotation (Aerodrome DEX)
  address public s_zQuoter; //0x772E2810A471dB2CC7ADA0d37D6395476535889a on Base

  /// @notice Collects insurance premium amount.
  address public s_premiumCollector;

  // ============ Storage Mappings ============

  /// @notice Maps LSA addresses to their loan data
  /// @dev Primary storage for all loan information
  mapping(address => DataTypes.LoanData) internal s_loansByLSA;

  /// @notice Tracks the total number of loans created by each user
  /// @dev Used to index and iterate through user's loans
  mapping(address => uint256) public s_userLoanCount;

  /// @notice Maps user address and index to their LSA addresses
  /// @dev Enables retrieval of user's Nth loan: s_userLoanAtIndex[user][0] returns first loan's LSA
  mapping(address => mapping(uint256 => address)) public s_userLoanAtIndex;

  // ============ Protocol Parameters ============

  /// @notice Maximum loan amount allowed per loan (6 decimals for USDC)
  /// @dev Can be updated by admin to manage protocol risk
  uint256 public s_maxLoanAmount;

  // ============ Constants ============

  /// @notice Basis points denominator for percentage calculations (10000 = 100%)
  uint256 internal constant BASIS_POINTS = 10000;

  /// @notice Maximum slippage tolerance in basis points (200 = 2%)
  uint256 public constant MAX_SLIPPAGE_BPS = 200;

  /// @notice Loan repayment interval in seconds (30 days)
  uint256 public constant LOAN_REPAYMENT_INTERVAL = 30 days;

  // ============ Constructor ============

  /**
   * @notice Initializes the storage contract with immutable protocol addresses
   * @param _aaveV3Pool Aave V3 pool address (for flash loans)
   * @param _bitmorPool Bitmor Lending Pool
   * @param _oracle Price Oracle
   * @param _collateralAsset Collateral asset address (cbBTC)
   * @param _debtAsset Debt asset address (USDC)
   */
  constructor(
    address _aaveV3Pool,
    address _bitmorPool,
    address _oracle,
    address _collateralAsset,
    address _debtAsset
  ) {
    require(_aaveV3Pool != address(0), 'LoanStorage: Invalid Aave V3 pool');
    require(_bitmorPool != address(0), 'LoanStorage: Invalid Aave V2 pool');
    require(_oracle != address(0), 'LoanStorage: Invalid addresses provider');
    require(_collateralAsset != address(0), 'LoanStorage: Invalid collateral asset');
    require(_debtAsset != address(0), 'LoanStorage: Invalid debt asset');

    i_AAVE_V3_POOL = _aaveV3Pool;
    i_AAVE_V2_POOL = _bitmorPool;
    i_ORACLE = _oracle;
    i_collateralAsset = _collateralAsset;
    i_debtAsset = _debtAsset;
  }
}
