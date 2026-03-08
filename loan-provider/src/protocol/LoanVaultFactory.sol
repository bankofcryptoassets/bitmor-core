// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {ILoanVault} from "../interfaces/ILoanVault.sol";
import {ILoanVaultFactory} from "../interfaces/ILoanVaultFactory.sol";
import {Errors} from "../libraries/helpers/Errors.sol";

/**
 * @title LoanVaultFactory
 * @author Bitmor Protocol
 * @notice Factory for deploying LoanVault instances using CREATE2
 * @dev Uses BeaconProxy pattern for upgradeable deployment.
 * Produces deterministic addresses that can be computed before deployment.
 *
 * ## Design
 * - Uses BeaconProxy for upgradeable proxy deployment
 * - CREATE2 enables deterministic address computation
 * - Salt is derived from borrower address and timestamp
 * - Only the authorized Loan contract can create vaults
 *
 * ## Benefits
 * - Upgradeable: All LoanVaults can be upgraded via the beacon
 * - Predictable: Addresses can be computed off-chain
 * - Secure: Only Loan contract can create vaults
 *
 * @custom:security Only authorized Loan contract can create vaults
 */
contract LoanVaultFactory is ILoanVaultFactory {
    // ============ State Variables ============

    /**
     * @notice The UpgradeableBeacon that points to the LoanVault implementation
     */
    address public immutable i_BEACON;

    /**
     * @notice The Loan contract authorized to create vaults
     */
    address public immutable i_LOAN;

    // ============ Modifiers ============

    modifier onlyLoanContract() {
        if (msg.sender != i_LOAN) revert Errors.UnauthorizedCaller();
        _;
    }

    // ============ Constructor ============

    /**
     * @notice Initializes the factory with the beacon and loan contract
     * @param _beacon The UpgradeableBeacon address for LoanVault
     * @param _loan The Loan contract address authorized to create vaults
     */
    constructor(address _beacon, address _loan) {
        if (_beacon == address(0)) revert Errors.ZeroAddress();
        if (_loan == address(0)) revert Errors.ZeroAddress();

        i_BEACON = _beacon;
        i_LOAN = _loan;
    }

    // ============ Public Functions ============

    /**
     * @notice Computes the deterministic address for a vault before deployment
     * @dev Uses CREATE2 formula: keccak256(0xff ++ factory ++ salt ++ keccak256(creationCode))
     * @param borrower The borrower's address
     * @param timestamp The creation timestamp
     * @return The predicted vault address
     */
    function computeAddress(address borrower, uint256 timestamp) external view returns (address) {
        bytes32 salt = _generateSalt(borrower, timestamp);
        bytes memory initData = abi.encodeCall(ILoanVault.initialize, (i_LOAN, borrower));
        bytes memory creationCode = abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(i_BEACON, initData));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(creationCode)));
        return address(uint160(uint256(hash)));
    }

    /**
     * @notice Creates a new LoanVault using CREATE2 with BeaconProxy
     * @param borrower The user creating the loan
     * @param timestamp The creation timestamp (for salt generation)
     * @return vault The address of the newly created vault
     * @custom:access Restricted to the authorized Loan contract
     */
    function createLoanVault(address borrower, uint256 timestamp) external onlyLoanContract returns (address vault) {
        // Generate deterministic salt from borrower and timestamp
        bytes32 salt = _generateSalt(borrower, timestamp);

        // Encode initialization data for the BeaconProxy
        bytes memory initData = abi.encodeCall(ILoanVault.initialize, (i_LOAN, borrower));

        // Deploy BeaconProxy using CREATE2 (deterministic address)
        vault = address(new BeaconProxy{salt: salt}(i_BEACON, initData));

        emit LoanVaultFactory__VaultCreated(vault, borrower, salt);

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
