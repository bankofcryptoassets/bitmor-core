// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";
import {HelperConfig} from "../../HelperConfig.s.sol";
import {DeploymentConstants} from "../DeploymentConstants.sol";

/**
 * @title TransferToMultisig
 * @author Bitmor Protocol
 * @notice Transfers ADMIN role from deployer EOA to governance Safe multisig
 * @dev One-way operation. The deployer's ADMIN role is revoked after granting it to the Safe.
 * Run on testnet first to verify the Safe can operate the AccessManager before executing on mainnet.
 *
 * @custom:security This is irreversible. Verify the governance Safe can:
 * 1. Call `AccessManager.grantRole()` and `revokeRole()`
 * 2. Call `AccessManager.setTargetFunctionRole()`
 * 3. Call `AccessManager.schedule()` and `execute()`
 * before running this script on mainnet.
 */
contract TransferToMultisig is Script {
    /// @notice Transfers ADMIN to `governanceSafe` and revokes deployer
    /// @param governanceSafe The governance Safe multisig address
    function run(address governanceSafe) external {
        require(block.chainid != DeploymentConstants.LOCAL_CHAIN_ID, "TransferToMultisig: not for local");
        require(governanceSafe != address(0), "TransferToMultisig: zero governance safe");
        require(governanceSafe.code.length > 0, "TransferToMultisig: governance safe has no bytecode");

        HelperConfig config = new HelperConfig();
        BitmorAccessManager manager = BitmorAccessManager(config.getAccessManager());

        // Verify deployer currently has ADMIN role
        (bool isAdmin,) = manager.hasRole(0, msg.sender);
        require(isAdmin, "TransferToMultisig: deployer lacks ADMIN role");

        console2.log("=== Transfer ADMIN to Governance Safe ===");
        console2.log("Safe:", governanceSafe);
        console2.log("Current admin (deployer):", msg.sender);

        vm.startBroadcast();

        // 1. Grant ADMIN to Safe (role ID 0, no execution delay)
        manager.grantRole(0, governanceSafe, 0);
        console2.log("Granted ADMIN to Safe");

        // 2. Revoke ADMIN from deployer
        manager.revokeRole(0, msg.sender);
        console2.log("Revoked ADMIN from deployer");

        vm.stopBroadcast();

        // Verify transfer was successful
        (bool safeIsAdmin,) = manager.hasRole(0, governanceSafe);
        (bool deployerIsAdmin,) = manager.hasRole(0, msg.sender);
        require(safeIsAdmin, "TransferToMultisig: Safe does not have ADMIN after transfer");
        require(!deployerIsAdmin, "TransferToMultisig: deployer still has ADMIN after transfer");

        console2.log("=== Transfer Complete ===");
        console2.log("Governance Safe is now the sole ADMIN.");
    }
}
