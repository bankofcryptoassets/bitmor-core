// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {stdJson} from "forge-std/StdJson.sol";

/// @title DeploymentHelper
/// @author Bitmor Protocol
/// @notice Common utilities for deployment scripts
/// @dev Provides wrappers for HelperConfig getters, lending-pool JSON reading, and time manipulation
contract DeploymentHelper is Script {
    using stdJson for string;

    // ===== Contract Address Getters =====

    /// @notice Gets the deployed address for a contract from deployments.json
    /// @dev Maps contract names to HelperConfig getters for centralized address management
    /// @param contractName The name of the contract (must match expected names)
    /// @return The deployed address
    function getDeployedAddress(string memory contractName) internal returns (address) {
        HelperConfig helperConfig = new HelperConfig();

        // Map contract names to HelperConfig getters
        if (keccak256(bytes(contractName)) == keccak256(bytes("BitmorAccessManager"))) {
            return helperConfig.getAccessManager();
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("Loan"))) {
            return helperConfig.getLoan();
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("BTCVault"))) {
            return helperConfig.getBTCVault();
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("USDCVault"))) {
            return helperConfig.getUSDCVault();
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("LoanVaultFactory"))) {
            return helperConfig.getLoanVaultFactory();
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("LoanVault"))) {
            return helperConfig.getLoanVaultImplementation();
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("AaveTokenizedStrategy"))) {
            return helperConfig.getAaveTokenizedStrategy();
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("USDCStrategy"))) {
            return helperConfig.getUSDCStrategy();
        }

        revert(string.concat("DeploymentHelper: unknown contract ", contractName));
    }

    /// @notice Gets the most recently deployed address or zero if not found
    /// @dev Reads directly from run-latest.json to avoid DevOpsTools memory issues
    /// @param contractName The name of the contract
    /// @param scriptName The script that deployed it (e.g., "DeployAccessManager.s.sol")
    /// @return The deployed address or address(0) if not deployed
    function getDeployedAddressOrZero(string memory contractName, string memory scriptName)
        internal
        view
        returns (address)
    {
        string memory broadcastPath = string.concat(
            vm.projectRoot(), "/broadcast/", scriptName, "/", vm.toString(block.chainid), "/run-latest.json"
        );

        try vm.readFile(broadcastPath) returns (string memory json) {
            // Read directly from the JSON instead of using DevOpsTools
            return _findContractInBroadcast(json, contractName);
        } catch {
            return address(0);
        }
    }

    /// @notice Finds contract address in a broadcast JSON file
    /// @param json The JSON content of the broadcast file
    /// @param contractName The contract name to find
    /// @return The contract address or address(0) if not found
    function _findContractInBroadcast(string memory json, string memory contractName) private view returns (address) {
        // Iterate through transactions array to find the contract
        for (uint256 i = 0; vm.keyExistsJson(json, string.concat("$.transactions[", vm.toString(i), "]")); i++) {
            string memory namePath = string.concat("$.transactions[", vm.toString(i), "].contractName");
            if (vm.keyExistsJson(json, namePath)) {
                string memory deployedName = json.readString(namePath);
                if (keccak256(bytes(deployedName)) == keccak256(bytes(contractName))) {
                    return json.readAddress(string.concat("$.transactions[", vm.toString(i), "].contractAddress"));
                }
            }
        }
        return address(0);
    }

    /// @notice Gets deployed address and reverts if not found
    /// @param contractName The name of the contract
    /// @return addr The deployed address (reverts if zero)
    function requireDeployed(string memory contractName) internal returns (address addr) {
        addr = getDeployedAddress(contractName);
        require(addr != address(0), string.concat(contractName, " not deployed"));
    }

    // ===== Lending Pool JSON Reader =====

    /// @notice Reads an address from lending-pool/deployed-contracts.json
    /// @dev Delegates to HelperConfig for single source of truth
    /// @param contractName The contract name key in the JSON
    /// @return The address from the JSON file
    function readLendingPoolAddress(string memory contractName) internal returns (address) {
        HelperConfig helperConfig = new HelperConfig();
        return helperConfig.readLendingPoolAddress(contractName);
    }

    // ===== Anvil Time Manipulation =====

    /// @notice Advances block.timestamp by specified seconds
    /// @dev Uses Foundry's vm.warp() cheatcode
    /// @param seconds_ Time to skip forward
    function warpTime(uint256 seconds_) internal {
        vm.warp(block.timestamp + seconds_);
    }

    /// @notice Sets block.timestamp to specific value
    /// @dev Uses Foundry's warp() cheatcode
    /// @param newTimestamp The new timestamp to set
    function warpTimeTo(uint256 newTimestamp) internal {
        vm.warp(newTimestamp);
    }

    // ===== Common Validation =====

    /// @notice Reverts if address is zero
    /// @param addr The address to check
    /// @param name Name for error message
    function requireNonZero(address addr, string memory name) internal pure {
        require(addr != address(0), string.concat(name, " is zero address"));
    }

    /// @notice Checks if current chain is local Anvil
    /// @return True if chainId is 31337
    function isLocalChain() internal view returns (bool) {
        return block.chainid == 31337;
    }
}
