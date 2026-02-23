// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title ILoanVaultFactory
 * @author Bitmor Protocol
 * @notice Interface for LoanVaultFactory contract
 * @dev Used by Loan contract to create new LSAs (Loan Specific Addresses)
 */
interface ILoanVaultFactory {
    // ============ Events ============

    /**
     * @notice Emitted when a new LoanVault clone is created via CREATE2
     * @param vault Address of the newly created vault
     * @param borrower Address of the borrower who owns the vault
     * @param salt Deterministic salt used for CREATE2 deployment
     */
    event LoanVaultFactory__VaultCreated(address indexed vault, address indexed borrower, bytes32 salt);

    /**
     * @notice Emitted when the authorized Loan contract address is updated
     * @param oldContract Address of the previous Loan contract
     * @param newContract Address of the new Loan contract
     */
    event LoanVaultFactory__LoanContractUpdated(address indexed oldContract, address indexed newContract);

    /**
     * @notice Creates a new LoanVault using CREATE2
     * @param borrower The user creating the loan
     * @param timestamp The creation timestamp (for salt generation)
     * @return vault The address of the newly created vault
     * @custom:access Restricted to the authorized Loan contract
     */
    function createLoanVault(address borrower, uint256 timestamp) external returns (address vault);

    /**
     * @notice Computes the deterministic address for a vault before deployment
     * @dev Uses CREATE2 formula: keccak256(0xff ++ factory ++ salt ++ keccak256(initCode))
     * @param borrower The borrower's address
     * @param timestamp The creation timestamp
     * @return The predicted vault address
     */
    function computeAddress(address borrower, uint256 timestamp) external view returns (address);
}
