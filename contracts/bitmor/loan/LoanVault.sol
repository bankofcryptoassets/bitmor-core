// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {IERC20} from '../../dependencies/openzeppelin/contracts/IERC20.sol';
import {SafeERC20} from '../../dependencies/openzeppelin/contracts/SafeERC20.sol';
import {ILoanVault} from '../interfaces/ILoanVault.sol';

/**
 * @title LoanVault
 * @notice Loan Specific Address (LSA) that holds the Aave V2 position
 * @dev Minimal proxy pattern - deployed via CREATE2 for deterministic addresses
 * Each loan gets its own LSA which holds acbBTC collateral and vdtUSDC debt
 */
contract LoanVault is ILoanVault {
  using SafeERC20 for IERC20;

  // ============ State Variables ============

  /// @notice The Loan contract that controls this vault
  address private s_owner; // This will be our Loan.sol contract address

  /// @notice The user who created this loan
  address private s_borrower;

  /// @notice Prevents re-initialization
  bool private s_initialized;

  // ============ Modifiers ============

  modifier onlyOwner() {
    require(msg.sender == s_owner, 'LoanVault: caller is not owner');
    _;
  }

  modifier notInitialized() {
    require(!s_initialized, 'LoanVault: already initialized');
    _;
  }

  // ============ Initialization ============

  /**
   * @notice Initializes the vault after deployment
   * @dev Called by factory immediately after CREATE2 deployment
   * @param _owner The Loan contract address that will control this vault
   * @param _borrower The user who created this loan
   */
  function initialize(address _owner, address _borrower) external override notInitialized {
    require(_owner != address(0), 'LoanVault: invalid owner');
    require(_borrower != address(0), 'LoanVault: invalid borrower');

    s_owner = _owner;
    s_borrower = _borrower;
    s_initialized = true;

    emit LoanVault__VaultInitialized(_owner, _borrower);
  }

  // ============ Token Operations ============

  /**
   * @notice Approves a spender to use tokens held by this vault
   * @dev Used to approve escrow for transferring acbBTC for operations
   * @param token The token to approve
   * @param spender The address to approve
   * @param amount The amount to approve
   */
  function approveToken(
    address token,
    address spender,
    uint256 amount
  ) external override onlyOwner {
    require(token != address(0), 'LoanVault: invalid token');
    require(spender != address(0), 'LoanVault: invalid spender');

    IERC20(token).safeApprove(spender, 0); // Reset first for tokens like USDT
    IERC20(token).safeApprove(spender, amount);

    emit LoanVault__TokenApproved(token, spender, amount);
  }

  /**
   * @notice Transfer token
   * @dev Used to transfer aToken from LoanVault to `to`
   * @param token The token to transfer
   * @param to The receiver address
   * @param amount The amount to transfer
   */
  function transferToken(address token, address to, uint256 amount) external override onlyOwner {
    require(token != address(0), 'LoanVault: invalid token');
    require(to != address(0), 'LoanVault: invalid to address');

    IERC20(token).safeTransfer(to, amount);
    emit LoanVault__TokenTransferred(token, to, amount);
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
  ) external override onlyOwner returns (bytes memory result) {
    require(target != address(0), 'LoanVault: invalid target');

    (bool success, bytes memory returnData) = target.call(data);
    require(success, 'LoanVault: execution failed');

    emit LoanVault__Executed(target, data, returnData);

    return returnData;
  }

  // ============ View Functions ============

  /**
   * @notice Gets the owner of this vault (Loan contract)
   * @return The owner address
   */
  function owner() external view override returns (address) {
    return s_owner;
  }

  /**
   * @notice Gets the borrower who created this loan
   * @return The borrower address
   */
  function borrower() external view override returns (address) {
    return s_borrower;
  }

  /**
   * @notice Checks if the vault has been initialized
   * @return True if initialized, false otherwise
   */
  function isInitialized() external view override returns (bool) {
    return s_initialized;
  }

  /**
   * @notice Gets the balance of a token held by this vault
   * @param token The token address to check
   * @return The balance of the token
   */
  function getTokenBalance(address token) external view override returns (uint256) {
    return IERC20(token).balanceOf(address(this));
  }

  receive() external payable {}
}
