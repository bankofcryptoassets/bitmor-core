// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

/**
 * @title ILoanVault
 * @notice Interface for LoanVault (LSA - Loan Specific Address)
 * @dev Minimal interface for LoanVaultFactory to interact with LoanVault clones
 */
interface ILoanVault {
    // ============ Events ============

    event LoanVault__VaultInitialized(address indexed owner, address indexed borrower);
    event LoanVault__TokenApproved(address indexed token, address indexed spender, uint256 amount);
    event LoanVault__TokenTransferred(address indexed token, address indexed to, uint256 amount);
    event LoanVault__Executed(address indexed target, bytes data, bytes result);

    /**
     * @notice Initializes the LoanVault clone after deployment
     * @dev Called by LoanVaultFactory immediately after creating a clone
     * @param owner The Loan contract address (owner of this LSA)
     * @param borrower The user who created the loan
     */
    function initialize(address owner, address borrower) external;

    /**
     * @notice Approves a token for spending by another contract
     * @dev Only callable by owner (Loan contract)
     * @param token The token address to approve
     * @param spender The address authorized to spend
     * @param amount The amount to approve
     */
    function approveToken(address token, address spender, uint256 amount) external;

    /**
     * @notice Transfer token
     * @dev Used to transfer aToken from LoanVault to `to`
     * @param token The token to transfer
     * @param to The receiver address
     * @param amount The amount to transfer
     */
    function transferToken(address token, address to, uint256 amount) external;

    /**
     * @notice Executes an arbitrary call to another contract
     * @dev Only callable by owner - provides flexibility for complex operations
     * Use this to call approveDelegation on debt tokens or any other contract interaction
     * @param target The contract address to call
     * @param data The encoded function call data
     * @return returnData The return data from the call
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
