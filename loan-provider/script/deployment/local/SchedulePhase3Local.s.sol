// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {DeploymentHelper} from "../../helpers/DeploymentHelper.s.sol";
import {HelperConfig} from "../../HelperConfig.s.sol";
import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";
import {ILoan} from "@bitmor/interfaces/ILoan.sol";
import {IBitmorAddressesProvider} from "@bitmor/interfaces/IBitmorAddressesProvider.sol";
import {DeploymentConstants} from "../DeploymentConstants.sol";

/// @title SchedulePhase3Local
/// @author Bitmor Protocol
/// @notice Schedules timelocked operations after roles are granted on-chain
/// @dev Must run AFTER DeployPhase3Local.s.sol has been broadcast and confirmed
/// @custom:security Only for local Anvil deployments (chainId 31337)
contract SchedulePhase3Local is Script, DeploymentHelper {
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
    address public bitmorAddressesProvider;
    address public swapper;
    address public autoRepayment;

    /// @notice Main entry point - schedules all timelocked operations
    function run() external {
        require(isLocalChain(), "SchedulePhase3Local: only for local");

        console2.log("=== Phase 3b: Schedule Operations ===");

        helperConfig = new HelperConfig();
        _loadDeployedAddresses();

        vm.startBroadcast();

        manager = BitmorAccessManager(accessManager);
        _scheduleOperations();

        vm.stopBroadcast();

        console2.log("=== Phase 3b Complete ===");
        console2.log("Advance time by 1 day, then run ExecutePhase3Local.s.sol");
    }

    /// @notice Loads deployed addresses using HelperConfig getters
    function _loadDeployedAddresses() internal {
        accessManager = helperConfig.getAccessManager();
        loan = helperConfig.getLoan();
        btcVault = helperConfig.getBTCVault();
        usdcVault = helperConfig.getUSDCVault();
        loanVaultFactory = helperConfig.getLoanVaultFactory();
        aaveStrategy = helperConfig.getAaveTokenizedStrategy();
        usdcStrategy = helperConfig.getUSDCStrategy();
        bitmorAddressesProvider = helperConfig.getBitmorAddressesProvider();
        swapper = helperConfig.getSwapper();
        autoRepayment = helperConfig.getAutoRepayer();

        console2.log("Loaded addresses from HelperConfig");
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
        manager.schedule(loan, abi.encodeCall(ILoan.setBitmorAddressesProvider, (bitmorAddressesProvider)), when);
        manager.schedule(loan, abi.encodeCall(ILoan.setGracePeriod, (helperConfig.getGracePeriod())), when);
        manager.schedule(loan, abi.encodeCall(ILoan.setPreClosureFee, (helperConfig.getPreClosureFee())), when);
        manager.schedule(loan, abi.encodeCall(ILoan.setMaxDuration, (helperConfig.getMaxDuration())), when);

        // BitmorAddressesProvider Operations
        manager.schedule(
            bitmorAddressesProvider, abi.encodeCall(IBitmorAddressesProvider.setVaultFactory, (loanVaultFactory)), when
        );
        manager.schedule(bitmorAddressesProvider, abi.encodeCall(IBitmorAddressesProvider.setSwapper, (swapper)), when);
        manager.schedule(
            bitmorAddressesProvider,
            abi.encodeCall(IBitmorAddressesProvider.setPremiumCollector, (helperConfig.getPremiumCollector())),
            when
        );
        manager.schedule(
            bitmorAddressesProvider, abi.encodeCall(IBitmorAddressesProvider.setAutoRepayer, (autoRepayment)), when
        );

        // Loan parameter configuration (required for loan creation to work)
        // setMaxBTCAmount must come first: setMinBTCAmount reverts if min > max (default 0)
        manager.schedule(loan, abi.encodeCall(ILoan.setMaxBTCAmount, (10e8)), when); // 10 BTC max
        manager.schedule(loan, abi.encodeCall(ILoan.setMinBTCAmount, (0.01e8)), when); // 0.01 BTC min
        manager.schedule(loan, abi.encodeCall(ILoan.setSlippageForSwap, (50)), when); // 0.5%
        manager.schedule(loan, abi.encodeCall(ILoan.setSlippageForSharesToAsset, (100)), when); // 1%
        manager.schedule(loan, abi.encodeCall(ILoan.setMinDepositBps, (30_00)), when); // 30%

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
