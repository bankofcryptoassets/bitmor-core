// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console} from "forge-std/console.sol";
import {InitialSetup} from "./InitialSetup.s.sol";
import {DeploymentHelper} from "../../helpers/DeploymentHelper.s.sol";
import {StrategyConfig} from "../../StrategyConfig.s.sol";
import {RolesData} from "@bitmor/accessManager/RolesData.sol";
import {ILoan} from "@bitmor/interfaces/ILoan.sol";

/// @title LocalFullSetup
/// @author Bitmor Protocol
/// @notice Comprehensive AccessManager setup: roles, grants, schedule, warp, execute
/// @dev Designed for local Anvil and fork deployments with time warp capability
/// @custom:security This script sets up all permissions - run with caution
contract LocalFullSetup is InitialSetup, DeploymentHelper {
    // ===== Deployed Contract Addresses =====

    address internal loan;
    address internal btcVault;
    address internal usdcVault;
    address internal autoRepayment;

    // ===== Config Instances =====

    StrategyConfig internal strategyConfig;

    /// @notice Main entry point for LocalFullSetup
    /// @param enableTimeWarp Set true for Anvil (local or fork), false for live networks
    /// @dev Steps: setup roles -> grant roles -> setup guardians -> schedule -> warp -> execute
    function run(bool enableTimeWarp) external {
        _loadDeployedAddresses();
        _loadConfigs();

        vm.startBroadcast();

        // Step 1-2: Setup target function roles and grant roles
        _initialSetup();

        // Step 3: Setup guardians (chain-aware)
        _setupGuardians();

        // Step 4: Schedule all delayed operations
        _scheduleOperations();

        vm.stopBroadcast();

        // Step 5: Time warp (if enabled)
        if (enableTimeWarp) {
            console.log("Warping time by 1 day + 1 second...");
            warpTime(1 days + 1);

            vm.startBroadcast();

            // Step 6: Execute scheduled operations
            _executeOperations();

            vm.stopBroadcast();
        } else {
            console.log("Time warp disabled. Operations scheduled but not executed.");
            console.log("Execute manually after delay or warp time externally.");
        }

        _logSummary(enableTimeWarp);
    }

    /// @notice Loads deployed contract addresses using HelperConfig
    function _loadDeployedAddresses() internal {
        loan = config.getLoan();
        btcVault = config.getBTCVault();
        usdcVault = config.getUSDCVault();
        autoRepayment = address(0); // AutoRepayment not deployed in current flow
    }

    /// @notice Loads configuration instances
    function _loadConfigs() internal {
        strategyConfig = new StrategyConfig();
        rolesData = new RolesData();
    }

    // ===== Guardian Setup =====

    /// @notice Sets up guardian roles based on chain
    /// @dev Simplified for local chain, full setup for other chains
    function _setupGuardians() internal {
        address admin = rolesData.INITIAL_ADMIN();

        if (isLocalChain()) {
            _setupSimplifiedGuardians(admin);
        } else {
            _setupProductionGuardians();
        }
    }

    /// @notice Simplified guardian setup for local testing
    /// @dev Grants all guardian roles to admin with 0 delay
    /// @param admin The admin address to grant guardian roles to
    function _setupSimplifiedGuardians(address admin) internal {
        // Get guardian role IDs (public struct getters return tuples: (grantee, id, isContract))
        (, uint64 guardianLpmSlowId,) = rolesData.GUARDIAN_LPM_SLOW();
        (, uint64 guardianBvmSlowId,) = rolesData.GUARDIAN_BVM_SLOW();
        (, uint64 guardianBvcId,) = rolesData.GUARDIAN_BVC();
        (, uint64 guardianBvaSlowId,) = rolesData.GUARDIAN_BVA_SLOW();
        (, uint64 guardianUvmSlowId,) = rolesData.GUARDIAN_UVM_SLOW();
        (, uint64 guardianUvcId,) = rolesData.GUARDIAN_UVC();

        // Get role IDs for guarded roles (tuple: target, isContract, execDelay, grantDelay, id, label, isGuarded, guardian, grantee, adminRoleId)
        (,,,, uint64 lpmSlowId,,,,,) = rolesData.LPM_SLOW();
        (,,,, uint64 bvmSlowId,,,,,) = rolesData.BVM_SLOW();
        (,,,, uint64 bvcId,,,,,) = rolesData.BVC();
        (,,,, uint64 bvaSlowId,,,,,) = rolesData.BVA_SLOW();
        (,,,, uint64 uvmSlowId,,,,,) = rolesData.UVM_SLOW();
        (,,,, uint64 uvcId,,,,,) = rolesData.UVC();

        // Grant all guardian roles to admin with 0 delay
        manager.grantRole(guardianLpmSlowId, admin, 0);
        manager.grantRole(guardianBvmSlowId, admin, 0);
        manager.grantRole(guardianBvcId, admin, 0);
        manager.grantRole(guardianBvaSlowId, admin, 0);
        manager.grantRole(guardianUvmSlowId, admin, 0);
        manager.grantRole(guardianUvcId, admin, 0);

        // Set guardian relationships
        manager.setRoleGuardian(lpmSlowId, guardianLpmSlowId);
        manager.setRoleGuardian(bvmSlowId, guardianBvmSlowId);
        manager.setRoleGuardian(bvcId, guardianBvcId);
        manager.setRoleGuardian(bvaSlowId, guardianBvaSlowId);
        manager.setRoleGuardian(uvmSlowId, guardianUvmSlowId);
        manager.setRoleGuardian(uvcId, guardianUvcId);
    }

    /// @notice Full guardian setup for production networks
    /// @dev Uses _setGuardian from InitialSetup which handles role grants and relationships
    function _setupProductionGuardians() internal {
        // Get role IDs and guardian structs
        (,,,, uint64 lpmSlowId,,,,,) = rolesData.LPM_SLOW();
        (,,,, uint64 bvmSlowId,,,,,) = rolesData.BVM_SLOW();
        (,,,, uint64 bvcId,,,,,) = rolesData.BVC();
        (,,,, uint64 bvaSlowId,,,,,) = rolesData.BVA_SLOW();
        (,,,, uint64 uvmSlowId,,,,,) = rolesData.UVM_SLOW();
        (,,,, uint64 uvcId,,,,,) = rolesData.UVC();

        // Get guardian structs
        (address g1Grantee, uint64 g1Id, bool g1IsContract) = rolesData.GUARDIAN_LPM_SLOW();
        (address g2Grantee, uint64 g2Id, bool g2IsContract) = rolesData.GUARDIAN_BVM_SLOW();
        (address g3Grantee, uint64 g3Id, bool g3IsContract) = rolesData.GUARDIAN_BVC();
        (address g4Grantee, uint64 g4Id, bool g4IsContract) = rolesData.GUARDIAN_BVA_SLOW();
        (address g5Grantee, uint64 g5Id, bool g5IsContract) = rolesData.GUARDIAN_UVM_SLOW();
        (address g6Grantee, uint64 g6Id, bool g6IsContract) = rolesData.GUARDIAN_UVC();

        _setGuardian(lpmSlowId, RolesData.RoleGuardian(g1Grantee, g1Id, g1IsContract));
        _setGuardian(bvmSlowId, RolesData.RoleGuardian(g2Grantee, g2Id, g2IsContract));
        _setGuardian(bvcId, RolesData.RoleGuardian(g3Grantee, g3Id, g3IsContract));
        _setGuardian(bvaSlowId, RolesData.RoleGuardian(g4Grantee, g4Id, g4IsContract));
        _setGuardian(uvmSlowId, RolesData.RoleGuardian(g5Grantee, g5Id, g5IsContract));
        _setGuardian(uvcId, RolesData.RoleGuardian(g6Grantee, g6Id, g6IsContract));
    }

    // ===== Schedule Operations =====

    /// @notice Schedules all delayed operations for execution after timelock
    /// @dev Schedules LPM_SLOW, BVC, and UVC operations
    function _scheduleOperations() internal {
        uint48 when = uint48(block.timestamp + 1 days);

        // LPM_SLOW Operations (Loan config)
        address loanVaultFactory = config.getLoanVaultFactory();

        manager.schedule(loan, abi.encodeCall(ILoan.setLoanVaultFactory, (loanVaultFactory)), when);
        manager.schedule(loan, abi.encodeCall(ILoan.setGracePeriod, (config.getGracePeriod())), when);
        manager.schedule(loan, abi.encodeCall(ILoan.setLiquidationBuffer, (config.getLiquidationBuffer())), when);
        manager.schedule(loan, abi.encodeCall(ILoan.setPremiumCollector, (config.getPremiumCollector())), when);
        manager.schedule(loan, abi.encodeCall(ILoan.setPreClosureFee, (config.getPreClosureFee())), when);

        // BVC Operations (BTCVault strategy) - if strategy deployed
        address aaveStrategy = config.getAaveTokenizedStrategy();
        if (aaveStrategy != address(0)) {
            manager.schedule(btcVault, abi.encodeWithSignature("addStrategy(address)", aaveStrategy), when);
        }

        // UVC Operations (USDCVault strategy) - if strategy deployed
        address usdcStrategy = config.getUSDCStrategy();
        if (usdcStrategy != address(0)) {
            StrategyConfig.StrategyDeploymentConfig memory stratConfig = strategyConfig.getStrategyConfig();
            manager.schedule(usdcVault, abi.encodeWithSignature("setNewStrategy(address)", usdcStrategy), when);
            manager.schedule(
                usdcVault,
                abi.encodeWithSignature("setYieldSourceAllocation(uint256)", stratConfig.usdcVault.aaveAllocation),
                when
            );
        }

        console.log("Operations scheduled for timestamp:", when);
    }

    // ===== Execute Operations =====

    /// @notice Executes all scheduled operations after timelock has passed
    /// @dev Must be called after time warp or waiting for delay
    function _executeOperations() internal {
        // LPM_SLOW Operations
        address loanVaultFactory = config.getLoanVaultFactory();

        manager.execute(loan, abi.encodeCall(ILoan.setLoanVaultFactory, (loanVaultFactory)));
        manager.execute(loan, abi.encodeCall(ILoan.setGracePeriod, (config.getGracePeriod())));
        manager.execute(loan, abi.encodeCall(ILoan.setLiquidationBuffer, (config.getLiquidationBuffer())));
        manager.execute(loan, abi.encodeCall(ILoan.setPremiumCollector, (config.getPremiumCollector())));
        manager.execute(loan, abi.encodeCall(ILoan.setPreClosureFee, (config.getPreClosureFee())));

        // BVC Operations
        address aaveStrategy = config.getAaveTokenizedStrategy();
        if (aaveStrategy != address(0)) {
            manager.execute(btcVault, abi.encodeWithSignature("addStrategy(address)", aaveStrategy));
        }

        // UVC Operations
        address usdcStrategy = config.getUSDCStrategy();
        if (usdcStrategy != address(0)) {
            StrategyConfig.StrategyDeploymentConfig memory stratConfig = strategyConfig.getStrategyConfig();
            manager.execute(usdcVault, abi.encodeWithSignature("setNewStrategy(address)", usdcStrategy));
            manager.execute(
                usdcVault,
                abi.encodeWithSignature("setYieldSourceAllocation(uint256)", stratConfig.usdcVault.aaveAllocation)
            );
        }

        console.log("All operations executed.");
    }

    // ===== Logging =====

    /// @notice Logs summary of LocalFullSetup execution
    /// @param timeWarpEnabled Whether time warp was enabled
    function _logSummary(bool timeWarpEnabled) internal view {
        console.log("");
        console.log("=== LocalFullSetup Complete ===");
        console.log("Loan:", loan);
        console.log("BTCVault:", btcVault);
        console.log("USDCVault:", usdcVault);
        console.log("AutoRepayment:", autoRepayment);
        console.log("Time warp enabled:", timeWarpEnabled);
    }
}
