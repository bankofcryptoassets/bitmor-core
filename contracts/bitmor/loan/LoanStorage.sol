// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {DataTypes} from '../libraries/types/DataTypes.sol';

/**
 * @title LoanStorage
 * @notice Storage layout for Bitmor Protocol loan management
 * @dev Contains all state variables for tracking loans and protocol configuration
 */
contract LoanStorage {
  // ============ Immutable Protocol Addresses ============

  /// @notice Aave V3 pool address for flash loan operations
  address public immutable AAVE_V3_POOL;

  /// @notice Aave V2 lending pool address for collateral deposits and debt borrowing
  address public immutable AAVE_V2_POOL;

  /// @notice Aave V2 addresses provider for accessing protocol contracts (oracle, etc.)
  address public immutable AAVE_ADDRESSES_PROVIDER;

  // ============ Protocol Contract Addresses ============

  /// @notice Factory contract for deploying Loan Specific Address (LSAs)
  address public loanVaultFactory;

  /// @notice Escrow contract for holding locked collateral
  address public escrow;

  /// @notice Swap adapter contract for executing token swaps
  address public swapAdapter;

  /// @notice zQuoter contract for price quotation (Aerodrome DEX)
  address public zQuoter; //0x772E2810A471dB2CC7ADA0d37D6395476535889a on Base

  // ============ Asset Configuration ============

  /// @notice Collateral asset address (cbBTC)
  address internal _collateralAsset;

  /// @notice Debt asset address (USDC)
  address internal _debtAsset;

  // ============ Storage Mappings ============

  /// @notice Maps LSA addresses to their loan data
  /// @dev Primary storage for all loan information
  mapping(address => DataTypes.LoanData) internal _loansByLSA;

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

  // ============ Constants ============

  /// @notice Basis points denominator for percentage calculations (10000 = 100%)
  uint256 internal constant BASIS_POINTS = 10000;

  /// @notice Maximum slippage tolerance in basis points (5 = 0.05%)
  uint256 public constant MAX_SLIPPAGE_BPS = 5;

  // ============ Constructor ============

  /**
   * @notice Initializes the storage contract with immutable protocol addresses
   * @param _aaveV3Pool Aave V3 pool address (for flash loans)
   * @param _aaveV2Pool Aave V2 lending pool address (for BTC/USDC reserves)
   * @param _aaveAddressesProvider Aave V2 addresses provider address
   */
  constructor(address _aaveV3Pool, address _aaveV2Pool, address _aaveAddressesProvider) public {
    require(_aaveV3Pool != address(0), 'Invalid Aave V3 pool');
    require(_aaveV2Pool != address(0), 'Invalid Aave V2 pool');
    require(_aaveAddressesProvider != address(0), 'Invalid addresses provider');

    AAVE_V3_POOL = _aaveV3Pool;
    AAVE_V2_POOL = _aaveV2Pool;
    AAVE_ADDRESSES_PROVIDER = _aaveAddressesProvider;
  }
}
