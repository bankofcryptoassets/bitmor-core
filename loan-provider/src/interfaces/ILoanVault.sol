// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

/**
 * @title ILoanVault
 * @author Bitmor Protocol
 * @notice Interface for LoanVault (LSA - Loan Specific Address)
 * @dev Minimal interface for LoanVaultFactory to interact with LoanVault clones
 */
interface ILoanVault {
    // ============ Events ============

    /**
     * @notice Emitted when the vault is initialized after clone deployment
     * @param owner Address of the Loan contract that owns this vault
     * @param borrower Address of the user who created the loan
     */
    event LoanVault__VaultInitialized(address indexed owner, address indexed borrower);

    /**
     * @notice Emitted when a token approval is set on this vault
     * @param token Address of the approved token
     * @param spender Address authorized to spend the token
     * @param amount Approved spending amount
     */
    event LoanVault__TokenApproved(address indexed token, address indexed spender, uint256 amount);

    /**
     * @notice Emitted when tokens are transferred out of this vault
     * @param token Address of the transferred token
     * @param to Recipient address
     * @param amount Amount transferred
     */
    event LoanVault__TokenTransferred(address indexed token, address indexed to, uint256 amount);

    /**
     * @notice Emitted when an arbitrary call is executed from this vault
     * @param target Address of the called contract
     * @param data Encoded calldata sent to the target
     * @param result Return data from the call
     */
    event LoanVault__Executed(address indexed target, bytes data, bytes result);

    /**
     * @notice Initializes the LoanVault clone after deployment
     * @dev Called by LoanVaultFactory immediately after creating a clone
     * @param owner The Loan contract address (owner of this LSA)
     * @param borrower The user who created the loan
     */
    function initialize(address owner, address borrower) external;

    /**
     * @notice Approves a `spender` to use `amount` of `token` held by this vault
     * @param token The token address to approve
     * @param spender The address authorized to spend
     * @param amount The amount to approve
     * @custom:access Restricted to owner (Loan contract)
     */
    function approveToken(address token, address spender, uint256 amount) external;

    /**
     * @notice Transfers `amount` of `token` from this vault to `to`
     * @param token The token to transfer
     * @param to The receiver address
     * @param amount The amount to transfer
     * @custom:access Restricted to owner (Loan contract)
     */
    function transferToken(address token, address to, uint256 amount) external;

    /**
     * @notice Executes an arbitrary call to `target` with `data`
     * @dev Provides flexibility for complex operations such as `approveDelegation` on debt tokens
     * @param target The contract address to call
     * @param data The encoded function call data
     * @return returnData The return data from the call
     * @custom:access Restricted to owner (Loan contract)
     */
    function execute(address target, bytes calldata data) external returns (bytes memory returnData);

    /**
     * @notice Returns the owner of this vault (Loan contract address)
     * @return The owner address
     */
    function owner() external view returns (address);

    /**
     * @notice Returns the borrower who owns this loan
     * @return The borrower address
     */
    function borrower() external view returns (address);

    /**
     * @notice Checks if the vault has been initialized
     * @return True if initialized, false otherwise
     */
    function isInitialized() external view returns (bool);

    /**
     * @notice Gets the balance of a token held by this vault
     * @param token The token address to check
     * @return The balance of the token
     */
    function getTokenBalance(address token) external view returns (uint256);
}
