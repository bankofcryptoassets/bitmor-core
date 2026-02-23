// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {ILoanVault} from "../interfaces/ILoanVault.sol";
import {Errors} from "../libraries/helpers/Errors.sol";

/**
 * @title LoanVault
 * @author Bitmor Protocol
 * @notice Loan Specific Address (LSA) that holds the Aave V2 position
 * @dev Minimal proxy pattern - deployed via CREATE2 for deterministic addresses.
 * Each loan gets its own LSA which holds abvBTC collateral and vdtUSDC debt.
 *
 * ## Design
 * - Each loan creates a new LoanVault instance via minimal proxy (clone)
 * - The vault holds aTokens (abvBTC) representing collateral
 * - The vault holds variable debt tokens (vdtUSDC) representing the borrowed amount
 * - Only the Loan contract (owner) can execute operations on this vault
 *
 * ## Security Model
 * - Single owner (Loan contract) controls all operations
 * - Initialization can only happen once
 * - Arbitrary execution allows flexibility while maintaining access control
 *
 * @custom:security Only owner can approve, transfer, or execute operations
 */
contract LoanVault is ILoanVault {
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    /**
     * @notice The Loan contract that controls this vault
     */
    address private s_owner; // This will be our Loan.sol contract address

    /**
     * @notice The user who created this loan
     */
    address private s_borrower;

    /**
     * @notice Prevents re-initialization
     */
    bool private s_initialized;

    // ============ Modifiers ============

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    modifier notInitialized() {
        _notInitialized();
        _;
    }

    // ============ Initialization ============

    /**
     * @notice Initializes the vault after deployment
     * @dev Called by factory immediately after CREATE2 deployment.
     *
     * Initialization invariants:
     * - MUST revert if already initialized; each LoanVault supports exactly one loan
     * - MUST NOT allow re-initialization once `s_initialized` is true
     * - MUST revert if `_owner` or `_borrower` is the zero address
     *
     * @param _owner The Loan contract address that will control this vault
     * @param _borrower The user who created this loan
     */
    function initialize(address _owner, address _borrower) external override notInitialized {
        if (_owner == address(0)) revert Errors.LoanVault__InvalidOwner();
        if (_borrower == address(0)) revert Errors.LoanVault__InvalidBorrower();

        s_owner = _owner;
        s_borrower = _borrower;
        s_initialized = true;

        emit LoanVault__VaultInitialized(_owner, _borrower);
    }

    // ============ Token Operations ============

    /**
     * @notice Approves a `spender` to use `amount` of `token` held by this vault
     * @dev Resets approval to zero first for safety (handles tokens like USDT)
     * @param token The token to approve
     * @param spender The address to approve
     * @param amount The amount to approve
     * @custom:access Restricted to owner (Loan contract)
     */
    function approveToken(address token, address spender, uint256 amount) external override onlyOwner {
        if (token == address(0)) revert Errors.LoanVault__InvalidToken();
        if (spender == address(0)) revert Errors.LoanVault__InvalidSpender();

        IERC20(token).forceApprove(spender, 0); // Reset first for tokens like USDT
        IERC20(token).forceApprove(spender, amount);

        emit LoanVault__TokenApproved(token, spender, amount);
    }

    /**
     * @notice Transfers `amount` of `token` from this vault to `to`
     * @param token The token to transfer
     * @param to The receiver address
     * @param amount The amount to transfer
     * @custom:access Restricted to owner (Loan contract)
     */
    function transferToken(address token, address to, uint256 amount) external override onlyOwner {
        if (token == address(0)) revert Errors.LoanVault__InvalidToken();
        if (to == address(0)) revert Errors.LoanVault__InvalidToAddress();

        IERC20(token).safeTransfer(to, amount);
        emit LoanVault__TokenTransferred(token, to, amount);
    }

    // ============ Arbitrary Execution ============

    /**
     * @notice Executes an arbitrary call from this vault to `target` with `data`
     * @dev Provides flexibility for complex operations (supply, borrow, repay, etc.)
     * @param target The contract to call
     * @param data The calldata to send
     * @return result The return data from the call
     * @custom:access Restricted to owner (Loan contract)
     */
    function execute(address target, bytes calldata data) external override onlyOwner returns (bytes memory result) {
        if (target == address(0)) revert Errors.LoanVault__InvalidTarget();

        (bool success, bytes memory returnData) = target.call(data);
        if (!success) revert Errors.LoanVault__ExecutionFailed();

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

    /**
     * @notice Internal validation to ensure vault is not already initialized
     * @dev Reverts if `s_initialized` is true.
     * Enforces invariant: MUST NOT allow re-initialization of same LoanVault.
     */
    function _notInitialized() internal view {
        if (s_initialized) revert Errors.LoanVault__AlreadyInitialized();
    }

    /**
     * @notice Internal validation to ensure caller is the owner
     * @dev Reverts if `msg.sender` is not `s_owner`
     */
    function _onlyOwner() internal view {
        if (msg.sender != s_owner) revert Errors.LoanVault__CallerIsNotOwner();
    }

    /**
     * @notice Allows the vault to receive native tokens (ETH)
     * @dev Required for potential gas refunds or protocol operations
     */
    receive() external payable {}
}
