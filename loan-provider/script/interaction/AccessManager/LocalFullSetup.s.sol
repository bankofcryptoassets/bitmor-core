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
        // Grant each guardian role and set its relationship - scoped per pair
        {
            (, uint64 guardianId,) = rolesData.GUARDIAN_LPM_SLOW();
            (,,,, uint64 guardedId,,,,,) = rolesData.LPM_SLOW();
            manager.grantRole(guardianId, admin, 0);
            manager.setRoleGuardian(guardedId, guardianId);
        }
        {
            (, uint64 guardianId,) = rolesData.GUARDIAN_BVM_SLOW();
            (,,,, uint64 guardedId,,,,,) = rolesData.BVM_SLOW();
            manager.grantRole(guardianId, admin, 0);
            manager.setRoleGuardian(guardedId, guardianId);
        }
        {
            (, uint64 guardianId,) = rolesData.GUARDIAN_BVC();
            (,,,, uint64 guardedId,,,,,) = rolesData.BVC();
            manager.grantRole(guardianId, admin, 0);
            manager.setRoleGuardian(guardedId, guardianId);
        }
        {
            (, uint64 guardianId,) = rolesData.GUARDIAN_BVA_SLOW();
            (,,,, uint64 guardedId,,,,,) = rolesData.BVA_SLOW();
            manager.grantRole(guardianId, admin, 0);
            manager.setRoleGuardian(guardedId, guardianId);
        }
        {
            (, uint64 guardianId,) = rolesData.GUARDIAN_UVM_SLOW();
            (,,,, uint64 guardedId,,,,,) = rolesData.UVM_SLOW();
            manager.grantRole(guardianId, admin, 0);
            manager.setRoleGuardian(guardedId, guardianId);
        }
        {
            (, uint64 guardianId,) = rolesData.GUARDIAN_UVC();
            (,,,, uint64 guardedId,,,,,) = rolesData.UVC();
            manager.grantRole(guardianId, admin, 0);
            manager.setRoleGuardian(guardedId, guardianId);
        }
    }

    /// @notice Full guardian setup for production networks
    /// @dev Uses _setGuardian from InitialSetup which handles role grants and relationships
    function _setupProductionGuardians() internal {
        {
            (,,,, uint64 guardedId,,,,,) = rolesData.LPM_SLOW();
            (address grantee, uint64 gId, bool isContract) = rolesData.GUARDIAN_LPM_SLOW();
            _setGuardian(guardedId, RolesData.RoleGuardian(grantee, gId, isContract));
        }
        {
            (,,,, uint64 guardedId,,,,,) = rolesData.BVM_SLOW();
            (address grantee, uint64 gId, bool isContract) = rolesData.GUARDIAN_BVM_SLOW();
            _setGuardian(guardedId, RolesData.RoleGuardian(grantee, gId, isContract));
        }
        {
            (,,,, uint64 guardedId,,,,,) = rolesData.BVC();
            (address grantee, uint64 gId, bool isContract) = rolesData.GUARDIAN_BVC();
            _setGuardian(guardedId, RolesData.RoleGuardian(grantee, gId, isContract));
        }
        {
            (,,,, uint64 guardedId,,,,,) = rolesData.BVA_SLOW();
            (address grantee, uint64 gId, bool isContract) = rolesData.GUARDIAN_BVA_SLOW();
            _setGuardian(guardedId, RolesData.RoleGuardian(grantee, gId, isContract));
        }
        {
            (,,,, uint64 guardedId,,,,,) = rolesData.UVM_SLOW();
            (address grantee, uint64 gId, bool isContract) = rolesData.GUARDIAN_UVM_SLOW();
            _setGuardian(guardedId, RolesData.RoleGuardian(grantee, gId, isContract));
        }
        {
            (,,,, uint64 guardedId,,,,,) = rolesData.UVC();
            (address grantee, uint64 gId, bool isContract) = rolesData.GUARDIAN_UVC();
            _setGuardian(guardedId, RolesData.RoleGuardian(grantee, gId, isContract));
        }
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
        manager.schedule(loan, abi.encodeCall(ILoan.setPremiumCollector, (config.getPremiumCollector())), when);
        manager.schedule(loan, abi.encodeCall(ILoan.setPreClosureFee, (config.getPreClosureFee())), when);
        manager.schedule(loan, abi.encodeCall(ILoan.setMaxDuration, (config.getMaxDuration())), when);

        // BVC Operations (BTCVault strategy) - if strategy deployed
        address aaveStrategy = config.getAaveTokenizedStrategy();
        if (aaveStrategy != address(0)) {
            manager.schedule(btcVault, abi.encodeWithSignature("addStrategy(address)", aaveStrategy), when);
        }

        // UVC Operations (USDCVault strategy) - if strategy deployed
        address usdcStrategy = config.getUSDCStrategy();
        if (usdcStrategy != address(0)) {
            StrategyConfig.StrategyDeploymentConfig memory stratConfig = strategyConfig.getStrategyConfig();
            manager.schedule(usdcVault, abi.encodeWithSignature("setStrategy(address)", usdcStrategy), when);
            manager.schedule(
                usdcVault,
                abi.encodeWithSignature("updateExternalAllocation(uint256)", stratConfig.usdcVault.aaveAllocation),
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
        manager.execute(loan, abi.encodeCall(ILoan.setPremiumCollector, (config.getPremiumCollector())));
        manager.execute(loan, abi.encodeCall(ILoan.setPreClosureFee, (config.getPreClosureFee())));
        manager.execute(loan, abi.encodeCall(ILoan.setMaxDuration, (config.getMaxDuration())));

        // BVC Operations
        address aaveStrategy = config.getAaveTokenizedStrategy();
        if (aaveStrategy != address(0)) {
            manager.execute(btcVault, abi.encodeWithSignature("addStrategy(address)", aaveStrategy));
        }

        // UVC Operations
        address usdcStrategy = config.getUSDCStrategy();
        if (usdcStrategy != address(0)) {
            StrategyConfig.StrategyDeploymentConfig memory stratConfig = strategyConfig.getStrategyConfig();
            manager.execute(usdcVault, abi.encodeWithSignature("setStrategy(address)", usdcStrategy));
            manager.execute(
                usdcVault,
                abi.encodeWithSignature("updateExternalAllocation(uint256)", stratConfig.usdcVault.aaveAllocation)
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
