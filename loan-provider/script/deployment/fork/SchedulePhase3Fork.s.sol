// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {DeploymentHelper} from "../../helpers/DeploymentHelper.s.sol";
import {HelperConfig} from "../../HelperConfig.s.sol";
import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";
import {DeploymentConstants} from "../DeploymentConstants.sol";

/// @title SchedulePhase3Fork
/// @notice Schedules timelocked operations on a Base mainnet fork
/// @dev Must run AFTER DeployPhase3Fork has been broadcast. Requires FORK=base env var.
/// @custom:security For local fork deployments only (Anvil forking Base mainnet, chain ID 31337)
contract SchedulePhase3Fork is Script, DeploymentHelper {
    uint256 constant STRATEGY_CAP = type(uint96).max;

    HelperConfig public helperConfig;
    BitmorAccessManager public manager;

    address public accessManager;
    address public btcVault;
    address public usdcVault;
    address public aaveStrategy;
    address public usdcStrategy;

    function run() external {
        require(
            block.chainid == DeploymentConstants.LOCAL_CHAIN_ID, "SchedulePhase3Fork: expected chain 31337 (Anvil fork)"
        );

        console2.log("=== Phase 3b: Schedule Operations (Fork) ===");

        helperConfig = new HelperConfig();
        accessManager = helperConfig.getAccessManager();
        btcVault = helperConfig.getBTCVault();
        usdcVault = helperConfig.getUSDCVault();
        aaveStrategy = helperConfig.getAaveTokenizedStrategy();
        usdcStrategy = helperConfig.getUSDCStrategy();

        vm.startBroadcast();

        manager = BitmorAccessManager(accessManager);

        uint48 when =
            uint48(block.timestamp + DeploymentConstants.EXECUTION_DELAY + DeploymentConstants.SCHEDULE_BUFFER);

        manager.schedule(
            btcVault, abi.encodeWithSignature("addStrategy(address,uint256)", aaveStrategy, STRATEGY_CAP), when
        );
        manager.schedule(usdcVault, abi.encodeWithSignature("setStrategy(address)", usdcStrategy), when);

        vm.stopBroadcast();

        console2.log("Operations scheduled for:", when);
        console2.log("=== Phase 3b Complete ===");
    }
}
