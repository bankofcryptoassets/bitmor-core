// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

/**
 * @title ILoanVaultFactory
 * @notice Interface for LoanVaultFactory contract
 * @dev Used by Loan contract to create new LSAs (Loan Specific Addresses)
 */
interface ILoanVaultFactory {
  // ============ Events ============

  event LoanVaultFactory__VaultCreated(
    address indexed vault,
    address indexed borrower,
    bytes32 salt
  );

  event LoanVaultFactory__LoanContractUpdated(
    address indexed oldContract,
    address indexed newContract
  );

  /**
   * @notice Creates a new LoanVault using CREATE2
   * @dev Can only be called by the authorized Loan contract
   * @param borrower The user creating the loan
   * @param timestamp The creation timestamp (for salt generation)
   * @return vault The address of the newly created vault
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
