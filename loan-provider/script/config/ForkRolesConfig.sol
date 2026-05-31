// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {DeploymentBase} from "../deployment/DeploymentBase.s.sol";

/// @title ForkRolesConfig
/// @notice Role grantee configuration for fork deployments (Base mainnet fork on Anvil)
/// @dev All roles granted to deployer (msg.sender) like local, but fork uses Base mainnet state
/// so real execution delays from RolesData.sol are preserved (1-day slow, 48h upgrades)
abstract contract ForkRolesConfig is DeploymentBase {
    /// @inheritdoc DeploymentBase
    function _getRoleGrantees() internal view override returns (RoleGrantees memory) {
        return RoleGrantees({
            admin: msg.sender,
            executor: msg.sender,
            lpcm: address(0),
            lpmFast: msg.sender,
            lpmSlow: msg.sender,
            are: msg.sender,
            bvmFast: msg.sender,
            bvmSlow: msg.sender,
            bvc: msg.sender,
            bvaFast: msg.sender,
            bvaSlow: msg.sender,
            bvd: address(0),
            uvmFast: msg.sender,
            uvmSlow: msg.sender,
            uvc: msg.sender,
            uva: address(0),
            upgrader: msg.sender
        });
    }
}
