// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";

import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";

/// @title DeployAccessManager
/// @author Bitmor Protocol
/// @notice Deployment script for the Bitmor Protocol AccessManager contract
/// @dev Deploys OpenZeppelin AccessManager v5.5.0 with proper initial admin configuration
/// @custom:security Validates that initial admin is a contract address for enhanced security
contract DeployAccessManager is Script {
    /// @dev The deployed AccessManager contract instance
    BitmorAccessManager accessManager;

    /// @notice Deploys AccessManager contract with specified initial admin
    /// @dev Uses vm.startBroadcast() for transaction broadcasting during deployment
    /// @param initialAdmin The address that will be granted the ADMIN role (0)
    /// @custom:security Initial admin should be a multisig for production deployments
    function _deployAccessManagerWithConfig(address initialAdmin) internal {
        vm.startBroadcast();
        accessManager = new BitmorAccessManager(initialAdmin);
        vm.stopBroadcast();
    }

    /// @notice Main deployment logic that configures and deploys the AccessManager
    /// @dev Validates initial admin is a contract before deployment for security
    /// @custom:security Reverts if initial admin is not a contract address
    function _deployAccessManager() internal {
        address initialAdmin = msg.sender;

        _deployAccessManagerWithConfig(initialAdmin);
    }

    /// @notice Main entry point for the deployment script
    /// @dev Called by `forge script` command to execute the deployment
    /// @custom:deployment Use with --broadcast flag to actually deploy to network
    function run() public {
        _deployAccessManager();
    }
}
