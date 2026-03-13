// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {DeploymentHelper} from "../../helpers/DeploymentHelper.s.sol";
import {HelperConfig} from "../../HelperConfig.s.sol";
import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";
import {DeploymentConstants} from "../DeploymentConstants.sol";

/**
 * @title SchedulePhase3Mainnet
 * @author Bitmor Protocol
 * @notice Schedules timelocked operations after roles are granted on-chain for mainnet
 * @dev Must run AFTER DeployPhase3Mainnet.s.sol has been broadcast and confirmed on-chain.
 *      Most config is now handled in initializers or admin direct calls in the deploy script.
 *      Only strategy wiring (addStrategy, setStrategy) still requires schedule/execute.
 *
 * Key differences from SchedulePhase3Local:
 * - Chain check: BASE_MAINNET_CHAIN_ID (8453)
 * - No `isLocalChain()` usage
 * - No ExecutePhase3 counterpart script — on mainnet, operations are executed via the
 *   governance multisig (GOVERNANCE_MULTISIG) after the timelock expires
 *
 * @custom:security For Base mainnet deployment (chainId 8453). Operations will be executable
 * after EXECUTION_DELAY (1 day) + SCHEDULE_BUFFER (10 min) has elapsed.
 */
contract SchedulePhase3Mainnet is Script, DeploymentHelper {
    // ===== Constants =====
    uint256 constant STRATEGY_CAP = type(uint256).max;

    // ===== Config =====
    HelperConfig public helperConfig;
    BitmorAccessManager public manager;

    // ===== Addresses (loaded from deployments.json) =====
    address public accessManager;
    address public btcVault;
    address public usdcVault;
    address public aaveStrategy;
    address public usdcStrategy;

    /// @notice Main entry point - schedules all timelocked operations for mainnet
    function run() external {
        require(
            block.chainid == DeploymentConstants.BASE_MAINNET_CHAIN_ID,
            "SchedulePhase3Mainnet: wrong chain, expected Base mainnet (8453)"
        );

        console2.log("=== Phase 3b: Schedule Operations (Mainnet) ===");

        helperConfig = new HelperConfig();
        _loadDeployedAddresses();

        vm.startBroadcast();

        manager = BitmorAccessManager(accessManager);
        _scheduleOperations();

        vm.stopBroadcast();

        console2.log("=== Phase 3b Complete ===");
        console2.log("Operations will be executable after the timelock period.");
        console2.log("Execute via governance multisig after delay expires.");
    }

    /// @notice Loads deployed addresses using HelperConfig getters
    function _loadDeployedAddresses() internal {
        accessManager = helperConfig.getAccessManager();
        btcVault = helperConfig.getBTCVault();
        usdcVault = helperConfig.getUSDCVault();
        aaveStrategy = helperConfig.getAaveTokenizedStrategy();
        usdcStrategy = helperConfig.getUSDCStrategy();

        console2.log("Loaded addresses from HelperConfig");
        console2.log("  AccessManager:", accessManager);
        console2.log("  BTCVault:", btcVault);
        console2.log("  USDCVault:", usdcVault);
    }

    /// @notice Schedules timelocked strategy-wiring operations for execution after delay
    /// @dev Adds SCHEDULE_BUFFER to account for block.timestamp drift between simulation and broadcast.
    ///      Only strategy operations remain — all other config is now set in initializers or direct admin calls.
    function _scheduleOperations() internal {
        uint48 when =
            uint48(block.timestamp + DeploymentConstants.EXECUTION_DELAY + DeploymentConstants.SCHEDULE_BUFFER);

        // BVC Operations (BTCVault strategy)
        manager.schedule(
            btcVault, abi.encodeWithSignature("addStrategy(address,uint256)", aaveStrategy, STRATEGY_CAP), when
        );

        // UVC Operations (USDCVault strategy)
        manager.schedule(usdcVault, abi.encodeWithSignature("setStrategy(address)", usdcStrategy), when);

        console2.log("Operations scheduled for:", when);
    }
}
