// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {DeploymentBase} from "../deployment/DeploymentBase.s.sol";

/// @title MainnetRolesConfig
/// @notice Role grantee configuration for Base mainnet deployment
/// @dev Each role category maps to a different multisig with appropriate security level
/// @custom:security Review all addresses before mainnet deployment
abstract contract MainnetRolesConfig is DeploymentBase {
    /// @dev 2-of-3 multisig for fast operational actions (pause, liquidation, reallocation)
    // TODO: Replace with actual multisig addresses before mainnet deployment
    address constant OPERATIONS_MULTISIG = address(0);
    /// @dev 3-of-5 multisig for slow governance actions (unpause, strategy changes, state updates)
    address constant GOVERNANCE_MULTISIG = address(0);
    /// @dev 4-of-7 multisig for contract upgrades (48h delay)
    address constant UPGRADER_MULTISIG = address(0);
    /// @dev 2-of-3 multisig for cancelling pending delayed operations
    address constant GUARDIAN_MULTISIG = address(0);

    /// @inheritdoc DeploymentBase
    function _getRoleGrantees() internal pure override returns (RoleGrantees memory) {
        require(OPERATIONS_MULTISIG != address(0), "MainnetRolesConfig: set OPERATIONS_MULTISIG");
        require(GOVERNANCE_MULTISIG != address(0), "MainnetRolesConfig: set GOVERNANCE_MULTISIG");
        require(UPGRADER_MULTISIG != address(0), "MainnetRolesConfig: set UPGRADER_MULTISIG");

        return RoleGrantees({
            admin: GOVERNANCE_MULTISIG,
            executor: OPERATIONS_MULTISIG,
            lpcm: address(0),
            lpmFast: OPERATIONS_MULTISIG,
            lpmSlow: GOVERNANCE_MULTISIG,
            are: OPERATIONS_MULTISIG,
            bvmFast: OPERATIONS_MULTISIG,
            bvmSlow: GOVERNANCE_MULTISIG,
            bvc: GOVERNANCE_MULTISIG,
            bvaFast: OPERATIONS_MULTISIG,
            bvaSlow: GOVERNANCE_MULTISIG,
            bvd: address(0),
            uvmFast: OPERATIONS_MULTISIG,
            uvmSlow: GOVERNANCE_MULTISIG,
            uvc: GOVERNANCE_MULTISIG,
            uva: address(0),
            upgrader: UPGRADER_MULTISIG
        });
    }
}
