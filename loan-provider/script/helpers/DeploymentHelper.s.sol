// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {HelperConfig} from "../HelperConfig.s.sol";

/// @title DeploymentHelper
/// @author Bitmor Protocol
/// @notice Common utilities for deployment scripts
/// @dev Provides wrappers for DevOpsTools, lending-pool JSON reading, and time manipulation
contract DeploymentHelper is Script {
    // ===== DevOpsTools Wrappers =====

    /// @notice Gets the most recently deployed address for a contract
    /// @param contractName The name of the contract
    /// @return The deployed address
    function getDeployedAddress(string memory contractName) internal view returns (address) {
        return DevOpsTools.get_most_recent_deployment(contractName, block.chainid);
    }

    /// @notice Gets the most recently deployed address or zero if not found
    /// @param contractName The name of the contract
    /// @return The deployed address or address(0) if not deployed
    function getDeployedAddressOrZero(string memory contractName) internal view returns (address) {
        try this._getDeployedAddressExternal(contractName) returns (address addr) {
            return addr;
        } catch {
            return address(0);
        }
    }

    /// @notice External wrapper for DevOpsTools call (needed for try/catch)
    /// @dev This function is external to enable try/catch pattern
    /// @param contractName The name of the contract
    /// @return The deployed address
    function _getDeployedAddressExternal(string memory contractName) external view returns (address) {
        return DevOpsTools.get_most_recent_deployment(contractName, block.chainid);
    }

    /// @notice Gets deployed address and reverts if not found
    /// @param contractName The name of the contract
    /// @return addr The deployed address (reverts if zero)
    function requireDeployed(string memory contractName) internal view returns (address addr) {
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
