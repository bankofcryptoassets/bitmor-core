// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {DeploymentHelper} from "../../helpers/DeploymentHelper.s.sol";
import {HelperConfig} from "../../HelperConfig.s.sol";
import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";
import {DeploymentConstants} from "../DeploymentConstants.sol";

/// @title ExecutePhase3Fork
/// @notice Executes scheduled strategy operations on a Base mainnet fork
/// @dev Run after SchedulePhase3Fork and after advancing Anvil time. Requires FORK=base env var.
/// No oracle reconfiguration needed — Phase 2 set the bvBTC pricing path and it was never disabled.
/// @custom:security For local fork deployments only (Anvil forking Base mainnet, chain ID 31337)
contract ExecutePhase3Fork is Script, DeploymentHelper {
    uint256 constant STRATEGY_CAP = type(uint96).max;

    HelperConfig public helperConfig;
    BitmorAccessManager public manager;

    address public btcVault;
    address public usdcVault;
    address public aaveStrategy;
    address public usdcStrategy;

    function run() public {
        require(
            block.chainid == DeploymentConstants.LOCAL_CHAIN_ID, "ExecutePhase3Fork: expected chain 31337 (Anvil fork)"
        );

        console2.log("=== Phase 3c: Execute Scheduled Operations (Fork) ===");

        helperConfig = new HelperConfig();
        address accessManager = helperConfig.getAccessManager();
        manager = BitmorAccessManager(accessManager);
        btcVault = helperConfig.getBTCVault();
        usdcVault = helperConfig.getUSDCVault();
        aaveStrategy = helperConfig.getAaveTokenizedStrategy();
        usdcStrategy = helperConfig.getUSDCStrategy();

        vm.startBroadcast();

        // Execute strategy operations
        manager.execute(btcVault, abi.encodeWithSignature("addStrategy(address,uint256)", aaveStrategy, STRATEGY_CAP));
        console2.log("BTCVault strategy added");

        manager.execute(usdcVault, abi.encodeWithSignature("setStrategy(address)", usdcStrategy));
        console2.log("USDCVault strategy set");

        // No oracle reconfiguration needed on fork.
        // Phase 2 already set s_bvBTC = btcVault and s_btc = cbBTC.
        // The special bvBTC pricing path was never disabled (unlike local).
        // Now with strategies wired, convertToAssets reflects real vault state.

        vm.stopBroadcast();

        console2.log("=== Phase 3c Complete ===");
    }
}
