// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {DeploymentHelper} from "../helpers/DeploymentHelper.s.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";
import {ILoan} from "@bitmor/interfaces/ILoan.sol";

/// @title ExecutePhase3
/// @author Bitmor Protocol
/// @notice Executes scheduled AccessManager operations after time has advanced
/// @dev Run this after SchedulePhase3 and after advancing Anvil time by 1 day
/// @custom:security Only for local Anvil deployments (chainId 31337)
contract ExecutePhase3 is Script, DeploymentHelper {
    // ===== Constants =====
    uint256 constant STRATEGY_CAP = type(uint256).max;

    // ===== Config =====
    HelperConfig public helperConfig;
    BitmorAccessManager public manager;

    // ===== Addresses (loaded from deployments.json) =====
    address public loan;
    address public btcVault;
    address public usdcVault;
    address public loanVaultFactory;
    address public aaveStrategy;
    address public usdcStrategy;

    /// @notice Main entry point - executes all scheduled operations
    function run() public {
        require(isLocalChain(), "ExecutePhase3: only for local");

        console2.log("=== Phase 3c: Execute Scheduled Operations ===");

        helperConfig = new HelperConfig();
        _loadAddresses();

        vm.startBroadcast();

        // Execute LPM_SLOW operations (Loan config)
        console2.log("Executing Loan configuration...");
        manager.execute(loan, abi.encodeCall(ILoan.setLoanVaultFactory, (loanVaultFactory)));
        manager.execute(loan, abi.encodeCall(ILoan.setGracePeriod, (helperConfig.getGracePeriod())));
        manager.execute(loan, abi.encodeCall(ILoan.setPremiumCollector, (helperConfig.getPremiumCollector())));
        manager.execute(loan, abi.encodeCall(ILoan.setPreClosureFee, (helperConfig.getPreClosureFee())));
        manager.execute(loan, abi.encodeCall(ILoan.setMaxDuration, (helperConfig.getMaxDuration())));
        console2.log("Loan configuration complete.");

        // Execute BVC operations (BTCVault strategy)
        console2.log("Executing BTCVault strategy setup...");
        manager.execute(btcVault, abi.encodeWithSignature("setMaxStrategies(uint256)", 5));
        manager.execute(btcVault, abi.encodeWithSignature("addStrategy(address,uint256)", aaveStrategy, STRATEGY_CAP));
        console2.log("BTCVault strategy setup complete.");

        // Execute UVC operations (USDCVault strategy)
        console2.log("Executing USDCVault strategy setup...");
        manager.execute(usdcVault, abi.encodeWithSignature("setStrategy(address)", usdcStrategy));
        console2.log("USDCVault strategy setup complete.");

        vm.stopBroadcast();

        console2.log("=== Phase 3c Complete - All operations executed ===");
    }

    /// @notice Loads all required addresses using HelperConfig getters
    function _loadAddresses() internal {
        address accessManager = helperConfig.getAccessManager();
        manager = BitmorAccessManager(accessManager);

        loan = helperConfig.getLoan();
        btcVault = helperConfig.getBTCVault();
        usdcVault = helperConfig.getUSDCVault();
        loanVaultFactory = helperConfig.getLoanVaultFactory();
        aaveStrategy = helperConfig.getAaveTokenizedStrategy();
        usdcStrategy = helperConfig.getUSDCStrategy();

        console2.log("Loaded addresses from HelperConfig:");
        console2.log("  AccessManager:", accessManager);
        console2.log("  Loan:", loan);
        console2.log("  BTCVault:", btcVault);
        console2.log("  USDCVault:", usdcVault);
    }
}
