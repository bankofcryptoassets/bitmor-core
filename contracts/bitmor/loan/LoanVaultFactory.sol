// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {Clones} from '../dependencies/openzeppelin/Clones.sol';
import {ILoanVault} from '../interfaces/ILoanVault.sol';

/**
 * @title LoanVaultFactory
 * @notice Factory for deploying LoanVault instances using CREATE2
 * @dev Uses minimal proxy (clone) pattern for gas-efficient deployment
 * Produces deterministic addresses that can be computed before deployment
 */
contract LoanVaultFactory {
  // ============ State Variables ============

  /// @notice The LoanVault implementation contract to clone
  address public immutable i_IMPLEMENTATION;

  /// @notice The Loan contract authorized to create vaults
  address public s_loanContract; // This will be our Loan.sol contract address

  // ============ Events ============

  event LoanVaultFactory__VaultCreated(
    address indexed vault,
    address indexed borrower,
    uint256 timestamp,
    bytes32 salt
  );

  event LoanVaultFactory__LoanContractUpdated(
    address indexed oldContract,
    address indexed newContract
  );

  // ============ Modifiers ============

  modifier onlyLoanContract() {
    require(msg.sender == s_loanContract, 'LoanVaultFactory: caller not authorized');
    _;
  }

  // ============ Constructor ============

  /**
   * @notice Initializes the factory with implementation
   * @param implementation The LoanVault implementation address to clone
   * @param _loanContract The Loan contract address authorized to create vaults
   */
  constructor(address implementation, address _loanContract) public {
    require(implementation != address(0), 'LoanVaultFactory: invalid implementation');
    require(_loanContract != address(0), 'LoanVaultFactory: invalid loan contract');
    i_IMPLEMENTATION = implementation;
    s_loanContract = _loanContract;
  }

  // ============ Public Functions ============

  /**
   * @notice Computes the deterministic address for a vault before deployment
   * @dev Uses CREATE2 formula: keccak256(0xff ++ factory ++ salt ++ keccak256(initCode))
   * @param borrower The borrower's address
   * @param timestamp The creation timestamp
   * @return The predicted vault address
   */
  function computeAddress(address borrower, uint256 timestamp) external view returns (address) {
    bytes32 salt = _generateSalt(borrower, timestamp);
    return Clones.predictDeterministicAddress(i_IMPLEMENTATION, salt, address(this));
  }

  /**
   * @notice Creates a new LoanVault using CREATE2
   * @dev Can only be called by the authorized Loan contract
   * @param borrower The user creating the loan
   * @param timestamp The creation timestamp (for salt generation)
   * @return vault The address of the newly created vault
   */
  function createLoanVault(
    address borrower,
    uint256 timestamp
  ) external onlyLoanContract returns (address vault) {
    require(borrower != address(0), 'LoanVaultFactory: invalid borrower');

    // Generate deterministic salt from borrower and timestamp
    bytes32 salt = _generateSalt(borrower, timestamp);

    // Deploy clone using CREATE2 (deterministic address)
    vault = Clones.cloneDeterministic(i_IMPLEMENTATION, salt);

    // Initialize the vault
    ILoanVault(vault).initialize(s_loanContract, borrower);

    emit LoanVaultFactory__VaultCreated(vault, borrower, timestamp, salt);

    return vault;
  }

  // ============ Internal Functions ============

  /**
   * @notice Generates a deterministic salt for CREATE2 deployment
   * @dev Salt = keccak256(borrower ++ timestamp)
   * @param borrower The borrower's address
   * @param timestamp The creation timestamp
   * @return The generated salt
   */
  function _generateSalt(address borrower, uint256 timestamp) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(borrower, timestamp));
  }
}
