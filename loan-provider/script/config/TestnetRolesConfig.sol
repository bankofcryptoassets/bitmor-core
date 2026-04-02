// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {DeploymentBase} from "../deployment/DeploymentBase.s.sol";

/// @title TestnetRolesConfig
/// @notice Role grantee configuration for testnet deployments (Base Sepolia)
/// @dev All roles granted to deployer (msg.sender) for testing convenience
abstract contract TestnetRolesConfig is DeploymentBase {
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
