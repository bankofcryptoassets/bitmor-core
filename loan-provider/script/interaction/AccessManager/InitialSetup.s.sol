// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";
import {RolesData} from "@bitmor/accessManager/RolesData.sol";
import {HelperConfig} from "../../HelperConfig.s.sol";

/// @title InitialSetup
/// @author Bitmor Protocol
/// @notice Sets up all roles and permissions for the deployed AccessManager contract
/// @dev Configures the complete role-based access control system for Bitmor Protocol
/// @custom:security This script grants significant permissions - should only be run by authorized deployer
contract InitialSetup is Script {
    /// @dev Configuration helper instance for retrieving deployment addresses and role data
    HelperConfig config;
    /// @dev AccessManager contract instance to configure
    BitmorAccessManager manager;

    /**
     * @dev Setup sequence for each role:
     * 1. Label role (human-readable name)
     * 2. Set admin role (who can manage this role)
     * 3. Set guardian role (who can cancel operations)
     * 4. Set grant delay (time before role grants take effect)
     * 5. Set function selectors (which functions this role can call)
     * 6. Grant role to designated address
     */

    /// @notice Grants a role to an address with specified execution delay
    /// @dev Uses vm.broadcast() to send transaction during script execution
    /// @param roleId The role identifier to grant
    /// @param grantee The address receiving the role
    /// @param executionDelay Time delay for operations using this role (0 = immediate)
    function _grantRole(uint64 roleId, address grantee, uint32 executionDelay) internal {
        vm.broadcast();
        manager.grantRole(roleId, grantee, executionDelay);
    }

    /// @notice Sets which functions a role can call on a target contract
    /// @dev Maps function selectors to role requirements for access control
    /// @param target The contract address these selectors apply to
    /// @param selectors Array of function selectors (bytes4)
    /// @param roleId The role required to call these functions
    function _setTargetSelectors(address target, bytes4[] memory selectors, uint64 roleId) internal {
        vm.broadcast();
        manager.setTargetFunctionRole(target, selectors, roleId);
    }

    /// @notice Sets the grant delay for a role
    /// @dev Grant delay is the time between granting a role and it becoming active
    /// @param roleId The role to configure
    /// @param grantDelay Time delay before granted role becomes effective
    function _setGrantDelay(uint64 roleId, uint32 grantDelay) internal {
        vm.broadcast();
        manager.setGrantDelay(roleId, grantDelay);
    }

    /// @notice Sets up a guardian for a role with cancellation privileges
    /// @dev Guardians can cancel scheduled operations for roles they guard
    /// @param roleId The role to assign a guardian to
    /// @param guardian Guardian configuration including address and guardian role ID
    /// @custom:security Guardian should be different address/entity than role holder
    function _setGuardian(uint64 roleId, RolesData.RoleGuardian memory guardian) internal {
        if (guardian.isContract) {
            _validateContract(guardian.grantee);
        }

        // Grant the guardian role with immediate execution (0 delay)
        _grantRole(guardian.id, guardian.grantee, 0);
        vm.broadcast();
        // Assign this guardian to protect the specified role
        manager.setRoleGuardian(roleId, guardian.id);
    }

    /// @notice Sets the admin role for another role
    /// @dev The admin role can grant and revoke the specified role
    /// @param roleId The role to assign an admin to
    /// @param adminId The role ID that will become the admin (typically 0 for ADMIN)
    function _setAdmin(uint64 roleId, uint64 adminId) internal {
        vm.broadcast();
        manager.setRoleAdmin(roleId, adminId);
    }

    /// @notice Sets a human-readable label for a role
    /// @dev Labels help with role identification and documentation
    /// @param roleId The role to label
    /// @param label Human-readable name for the role
    function _setRoleLabel(uint64 roleId, string memory label) internal {
        vm.broadcast();
        manager.labelRole(roleId, label);
    }

    /// @notice Performs complete initial setup of all roles and permissions
    /// @dev Iterates through all roles and configures them according to RolesData specifications
    /// @custom:security This function grants extensive permissions - validate all role configurations
    function _initialSetup() internal {
        config = new HelperConfig();
        manager = BitmorAccessManager(config.getAccessManager());

        HelperConfig.RoleData[] memory roles = config.getAllRoles();

        uint256 rolesLength = roles.length;

        if (rolesLength == 0) return;

        uint256 i = 0;
        for (i; i < rolesLength; i++) {
            HelperConfig.RoleData memory role = roles[i];

            // Set human-readable label for the role
            _setRoleLabel(role.id, role.label);

            // Set admin role if specified (who can manage this role)
            if (role.adminRoleId > 0) {
                _setAdmin(role.id, role.adminRoleId);
            }

            // Set guardian if role has guardian protection
            if (role.isGuarded) {
                _setGuardian(role.id, role.guardian);
            }

            // Set grant delay if specified (delay before role becomes active)
            if (role.grantDelay > 0) {
                _setGrantDelay(role.id, role.grantDelay);
            }

            // Set function selectors if specified (which functions role can call)
            if (role.selectors.length > 0) {
                _setTargetSelectors(role.target, role.selectors, role.id);
            }

            // Validate grantee is a contract if required
            if (role.isContract) {
                _validateContract(role.grantee);
            }

            // Finally, grant the role to the designated address
            _grantRole(role.id, role.grantee, role.executionDelay);
        }
    }

    /// @notice Main entry point for the initial setup script
    /// @dev Called by `forge script` to execute the complete role setup
    /// @custom:deployment Use with --broadcast flag to actually execute setup transactions
    function run() public {
        _initialSetup();
    }

    /// @notice Validates that an address is a contract (has code)
    /// @dev Used to ensure contract-based roles are only granted to actual contracts
    /// @param toCheck The address to validate
    /// @custom:security Prevents accidentally granting contract roles to EOAs
    function _validateContract(address toCheck) internal view {
        if (!(toCheck.code.length > 0)) revert("NOT_CONTRACT");
    }
}
