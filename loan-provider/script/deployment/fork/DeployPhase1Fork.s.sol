// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/Script.sol";
import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {DeploymentConstants} from "../DeploymentConstants.sol";
import {ForkRolesConfig} from "@bitmor-config/ForkRolesConfig.sol";
import {HelperConfig} from "../../HelperConfig.s.sol";

/// @title DeployPhase1Fork
/// @notice Phase 1 fork deployment: AccessManager and BTCVault (UUPS proxy) using real cbBTC
/// @dev Runs on Anvil forking Base mainnet (chain ID 31337, Base state). No mock deployments.
/// Address persistence is handled externally by the bitmor-deploy CLI tool.
/// @custom:security For local fork deployments only. Requires FORK=base env var.
contract DeployPhase1Fork is ForkRolesConfig {
    address public accessManager;
    address public btcVault;
    address public btcVaultImpl;
    address public cbBTCAddr;

    function run() external {
        _preflightPhase1(DeploymentConstants.LOCAL_CHAIN_ID);

        HelperConfig helperConfig = new HelperConfig();
        require(helperConfig.isForkMode(), "DeployPhase1Fork: FORK env var not set");
        HelperConfig.ProtocolConfig memory pc = helperConfig.getProtocolConfig();
        cbBTCAddr = helperConfig.getCbBTC();

        require(cbBTCAddr != address(0), "DeployPhase1Fork: set CBBTC_BASE_MAINNET in HelperConfig");
        require(cbBTCAddr.code.length > 0, "DeployPhase1Fork: cbBTC has no bytecode on fork");

        console2.log("=== Phase 1: Fork Deployment ===");

        vm.startBroadcast();

        // 1. AccessManager
        accessManager = address(new BitmorAccessManager(msg.sender));
        console2.log("AccessManager:", accessManager);

        // 2. BTCVault (UUPS proxy) — uses real cbBTC from fork
        btcVault = _deployUUPSProxy(
            "BTCVault.sol", abi.encodeCall(BTCVault.initialize, (cbBTCAddr, accessManager, pc.maxStrategies))
        );
        btcVaultImpl = _getProxyImplementation(btcVault);
        console2.log("BTCVault proxy:", btcVault);
        console2.log("BTCVault impl:", btcVaultImpl);

        vm.stopBroadcast();

        console2.log("=== Phase 1 Complete ===");
    }
}
