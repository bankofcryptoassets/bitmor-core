// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {IERC20} from '../../dependencies/openzeppelin/contracts/IERC20.sol';
import {SafeERC20} from '../../dependencies/openzeppelin/contracts/SafeERC20.sol';

/**
 * @title LoanVault
 * @notice Loan Specific Address (LSA) that holds the Bonzo position
 * @dev Minimal proxy pattern - deployed via CREATE2 for deterministic addresses
 * Each loan gets its own LSA which holds aBTC collateral and vdtUSDC debt
 */
contract LoanVault {
  using SafeERC20 for IERC20;

  // ============ State Variables ============

  /// @notice The Loan contract that controls this vault
  address public owner; // This will be our Loan.sol contract address

  /// @notice The user who created this loan
  address public borrower;

  /// @notice Prevents re-initialization
  bool private _initialized;

  // ============ Events ============

  event VaultInitialized(address indexed owner, address indexed borrower);
  event TokenApproved(address indexed token, address indexed spender, uint256 amount);
  event Executed(address indexed target, bytes data, bytes result);

  // ============ Modifiers ============

  modifier onlyOwner() {
    require(msg.sender == owner, 'LoanVault: caller is not owner');
    _;
  }

  modifier notInitialized() {
    require(!_initialized, 'LoanVault: already initialized');
    _;
  }

  // ============ Initialization ============

  /**
   * @notice Initializes the vault after deployment
   * @dev Called by factory immediately after CREATE2 deployment
   * @param _owner The Loan contract address that will control this vault
   * @param _borrower The user who created this loan
   */
  function initialize(address _owner, address _borrower) external notInitialized {
    require(_owner != address(0), 'LoanVault: invalid owner');
    require(_borrower != address(0), 'LoanVault: invalid borrower');

    owner = _owner;
    borrower = _borrower;
    _initialized = true;

    emit VaultInitialized(_owner, _borrower);
  }

  // ============ Token Operations ============

  /**
   * @notice Approves a spender to use tokens held by this vault
   * @dev Used to approve escrow for transferring aBTC for operations
   * @param token The token to approve
   * @param spender The address to approve
   * @param amount The amount to approve
   */
  function approveToken(address token, address spender, uint256 amount) external onlyOwner {
    require(token != address(0), 'LoanVault: invalid token');
    require(spender != address(0), 'LoanVault: invalid spender');

    IERC20(token).safeApprove(spender, 0); // Reset first for tokens like USDT
    IERC20(token).safeApprove(spender, amount);

    emit TokenApproved(token, spender, amount);
  }

  // ============ Arbitrary Execution ============

  /**
   * @notice Executes an arbitrary call from this vault
   * @dev Provides flexibility for complex operations (supply, borrow, repay, etc.)
   * @param target The contract to call
   * @param data The calldata to send
   * @return result The return data from the call
   */
  function execute(
    address target,
    bytes calldata data
  ) external onlyOwner returns (bytes memory result) {
    require(target != address(0), 'LoanVault: invalid target');

    (bool success, bytes memory returnData) = target.call(data);
    require(success, 'LoanVault: execution failed');

    emit Executed(target, data, returnData);

    return returnData;
  }

  // ============ View Functions ============

  /**
   * @notice Checks if the vault has been initialized
   * @return True if initialized, false otherwise
   */
  function isInitialized() external view returns (bool) {
    return _initialized;
  }

  /**
   * @notice Gets the balance of a token held by this vault
   * @param token The token address to check
   * @return The balance of the token
   */
  function getTokenBalance(address token) external view returns (uint256) {
    return IERC20(token).balanceOf(address(this));
  }
}
