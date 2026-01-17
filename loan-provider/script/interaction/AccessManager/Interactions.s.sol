// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";

import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";
import {HelperConfig} from "../../HelperConfig.s.sol";

/// @title BaseInteraction
/// @author Bitmor Protocol
/// @notice Base contract for AccessManager interaction scripts
/// @dev Provides common functionality for retrieving AccessManager instance
abstract contract BaseInteraction is Script {
    /// @dev Configuration helper for retrieving contract addresses
    HelperConfig config;

    /// @notice Retrieves the deployed AccessManager contract instance
    /// @dev Uses HelperConfig to get the manager address from deployment artifacts
    /// @return AccessManager instance for performing operations
    function _manager() internal returns (BitmorAccessManager) {
        config = new HelperConfig();
        return BitmorAccessManager(config.getAccessManager());
    }
}

/// @title LabelRole
/// @notice Script to set a human-readable label for a role
/// @dev Requires ROLE_ID and ROLE_LABEL environment variables
contract LabelRole is BaseInteraction {
    /// @notice Sets a label for the specified role
    /// @dev Reads ROLE_ID and ROLE_LABEL from environment variables
    function run() public {
        uint64 roleId = uint64(vm.envUint("ROLE_ID"));
        string memory label = vm.envString("ROLE_LABEL");

        vm.broadcast();
        _manager().labelRole(roleId, label);
    }
}

/// @title SetRoleAdmin
/// @notice Script to set the admin role for another role
/// @dev Requires ROLE_ID and ADMIN_ROLE_ID environment variables
contract SetRoleAdmin is BaseInteraction {
    /// @notice Sets the admin role for the specified role
    /// @dev Reads ROLE_ID and ADMIN_ROLE_ID from environment variables
    function run() public {
        uint64 roleId = uint64(vm.envUint("ROLE_ID"));
        uint64 adminRoleId = uint64(vm.envUint("ADMIN_ROLE_ID"));

        vm.broadcast();
        _manager().setRoleAdmin(roleId, adminRoleId);
    }
}

/// @title SetRoleGuardian
/// @notice Script to set the guardian role for another role
/// @dev Requires ROLE_ID and GUARDIAN_ROLE_ID environment variables
contract SetRoleGuardian is BaseInteraction {
    /// @notice Sets the guardian role for the specified role
    /// @dev Reads ROLE_ID and GUARDIAN_ROLE_ID from environment variables
    function run() public {
        uint64 roleId = uint64(vm.envUint("ROLE_ID"));
        uint64 guardianRoleId = uint64(vm.envUint("GUARDIAN_ROLE_ID"));

        vm.broadcast();
        _manager().setRoleGuardian(roleId, guardianRoleId);
    }
}

/// @title SetGrantDelay
/// @notice Script to set the grant delay for a role
/// @dev Requires ROLE_ID and GRANT_DELAY environment variables
contract SetGrantDelay is BaseInteraction {
    /// @notice Sets the grant delay for the specified role
    /// @dev Reads ROLE_ID and GRANT_DELAY from environment variables
    function run() public {
        uint64 roleId = uint64(vm.envUint("ROLE_ID"));
        uint32 grantDelay = uint32(vm.envUint("GRANT_DELAY"));

        vm.broadcast();
        _manager().setGrantDelay(roleId, grantDelay);
    }
}

/// @title SetTargetFunctionRole
/// @notice Script to set which role can call specific functions on a target contract
/// @dev Requires TARGET_ADDRESS, ROLE_ID, and SELECTORS environment variables
contract SetTargetFunctionRole is BaseInteraction {
    /// @notice Sets the role requirement for specific function selectors on a target
    /// @dev Reads TARGET_ADDRESS, ROLE_ID, and SELECTORS from environment variables
    function run() public {
        address target = vm.envAddress("TARGET_ADDRESS");
        uint64 roleId = uint64(vm.envUint("ROLE_ID"));
        bytes memory selectorsData = vm.envBytes("SELECTORS");
        bytes4[] memory selectors = abi.decode(selectorsData, (bytes4[]));

        vm.broadcast();
        _manager().setTargetFunctionRole(target, selectors, roleId);
    }
}

/// @title GrantRole
/// @notice Script to grant a role to an address with specified execution delay
/// @dev Requires ROLE_ID, GRANTEE, and EXECUTION_DELAY environment variables
contract GrantRole is BaseInteraction {
    /// @notice Grants a role to the specified address
    /// @dev Reads ROLE_ID, GRANTEE, and EXECUTION_DELAY from environment variables
    function run() public {
        uint64 roleId = uint64(vm.envUint("ROLE_ID"));
        address grantee = vm.envAddress("GRANTEE");
        uint32 executionDelay = uint32(vm.envUint("EXECUTION_DELAY"));

        vm.broadcast();
        _manager().grantRole(roleId, grantee, executionDelay);
    }
}

// Example make command (LabelRole):
// ACCESS_MANAGER=0xYourManager ROLE_ID=3 ROLE_LABEL="LPM" \
// make deploy ARGS="--script script/Interactions.s.sol:LabelRole --broadcast"
