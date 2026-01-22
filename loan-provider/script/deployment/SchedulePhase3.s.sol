// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {DeploymentHelper} from "../helpers/DeploymentHelper.s.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";
import {ILoan} from "@bitmor/interfaces/ILoan.sol";
import {DeploymentConstants} from "./DeploymentConstants.sol";

/// @title SchedulePhase3
/// @author Bitmor Protocol
/// @notice Schedules timelocked operations after roles are granted on-chain
/// @dev Must run AFTER DeployPhase3.s.sol has been broadcast and confirmed
/// @custom:security Only for local Anvil deployments (chainId 31337)
contract SchedulePhase3 is Script, DeploymentHelper {
    // ===== Constants =====
    uint256 constant STRATEGY_CAP = type(uint256).max;

    // ===== Config =====
    HelperConfig public helperConfig;
    BitmorAccessManager public manager;

    // ===== Addresses (loaded from deployments.json) =====
    address public accessManager;
    address public loan;
    address public btcVault;
    address public usdcVault;
    address public loanVaultFactory;
    address public aaveStrategy;
    address public usdcStrategy;

    /// @notice Main entry point - schedules all timelocked operations
    function run() external {
        require(isLocalChain(), "SchedulePhase3: only for local");

        console2.log("=== Phase 3b: Schedule Operations ===");

        helperConfig = new HelperConfig();
        _loadDeployedAddresses();

        vm.startBroadcast();

        manager = BitmorAccessManager(accessManager);
        _scheduleOperations();

        vm.stopBroadcast();

        console2.log("=== Phase 3b Complete ===");
        console2.log("Advance time by 1 day, then run ExecutePhase3.s.sol");
    }

    /// @notice Loads deployed addresses from deployments.json
    /// @dev Reads directly from JSON to avoid DevOpsTools memory issues with multiple broadcast files
    function _loadDeployedAddresses() internal {
        string memory json = vm.readFile("./deployments.json");
        string memory base = ".deployments.31337.networkConfig.";

        accessManager = vm.parseJsonAddress(json, string.concat(base, "accessManager"));
        loan = vm.parseJsonAddress(json, string.concat(base, "loan"));
        btcVault = vm.parseJsonAddress(json, string.concat(base, "collateralAsset"));
        usdcVault = vm.parseJsonAddress(json, string.concat(base, "usdcVault"));
        loanVaultFactory = vm.parseJsonAddress(json, string.concat(base, "loanVaultFactory"));
        aaveStrategy = vm.parseJsonAddress(json, string.concat(base, "aaveStrategy"));
        usdcStrategy = vm.parseJsonAddress(json, string.concat(base, "usdcStrategy"));

        console2.log("Loaded addresses from deployments.json");
        console2.log("  AccessManager:", accessManager);
        console2.log("  Loan:", loan);
        console2.log("  BTCVault:", btcVault);
        console2.log("  USDCVault:", usdcVault);
    }

    /// @notice Schedules all timelocked operations for execution after delay
    /// @dev Adds SCHEDULE_BUFFER to account for block.timestamp drift between simulation and broadcast
    function _scheduleOperations() internal {
        uint48 when =
            uint48(block.timestamp + DeploymentConstants.EXECUTION_DELAY + DeploymentConstants.SCHEDULE_BUFFER);

        // LPM_SLOW Operations (Loan config) - use HelperConfig getters
        manager.schedule(loan, abi.encodeCall(ILoan.setLoanVaultFactory, (loanVaultFactory)), when);
        manager.schedule(loan, abi.encodeCall(ILoan.setGracePeriod, (helperConfig.getGracePeriod())), when);
        manager.schedule(loan, abi.encodeCall(ILoan.setLiquidationBuffer, (helperConfig.getLiquidationBuffer())), when);
        manager.schedule(loan, abi.encodeCall(ILoan.setPremiumCollector, (helperConfig.getPremiumCollector())), when);
        manager.schedule(loan, abi.encodeCall(ILoan.setPreClosureFee, (helperConfig.getPreClosureFee())), when);

        // BVC Operations (BTCVault strategy)
        manager.schedule(btcVault, abi.encodeWithSignature("setMaxStrategies(uint256)", 5), when);
        manager.schedule(
            btcVault, abi.encodeWithSignature("addStrategy(address,uint256)", aaveStrategy, STRATEGY_CAP), when
        );

        // UVC Operations (USDCVault strategy)
        manager.schedule(usdcVault, abi.encodeWithSignature("setStrategy(address)", usdcStrategy), when);

        console2.log("Operations scheduled for:", when);
    }
}
