// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {DeploymentHelper} from "../../helpers/DeploymentHelper.s.sol";
import {HelperConfig} from "../../HelperConfig.s.sol";
import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";

/// @title ExecutePhase3Local
/// @author Bitmor Protocol
/// @notice Executes scheduled AccessManager operations after time has advanced
/// @dev Run this after SchedulePhase3Local and after advancing Anvil time by 1 day.
///      Most config is now handled in initializers or admin direct calls in the deploy script.
///      Only strategy wiring (addStrategy, setStrategy) and oracle reconfiguration remain.
/// @custom:security Only for local Anvil deployments (chainId 31337)
contract ExecutePhase3Local is Script, DeploymentHelper {
    // ===== Constants =====
    uint256 constant STRATEGY_CAP = type(uint256).max;

    // ===== Config =====
    HelperConfig public helperConfig;
    BitmorAccessManager public manager;

    // ===== Addresses (loaded from deployments.json) =====
    address public btcVault;
    address public usdcVault;
    address public aaveStrategy;
    address public usdcStrategy;
    address public aaveOracle;
    address public mockCbBTC;

    /// @notice Main entry point - executes all scheduled operations
    function run() public {
        require(isLocalChain(), "ExecutePhase3Local: only for local");

        console2.log("=== Phase 3c: Execute Scheduled Operations ===");

        helperConfig = new HelperConfig();
        _loadAddresses();

        vm.startBroadcast();

        // Execute BVC operations (BTCVault strategy)
        console2.log("Executing BTCVault strategy setup...");
        manager.execute(btcVault, abi.encodeWithSignature("addStrategy(address,uint256)", aaveStrategy, STRATEGY_CAP));
        console2.log("BTCVault strategy setup complete.");

        // Execute UVC operations (USDCVault strategy)
        console2.log("Executing USDCVault strategy setup...");
        manager.execute(usdcVault, abi.encodeWithSignature("setStrategy(address)", usdcStrategy));
        console2.log("USDCVault strategy setup complete.");

        // Reconfigure AaveOracle to use real bvBTC pricing path
        // Now that BTCVault has a strategy wired (via addStrategy above), convertToAssets() works.
        // Enable the special bvBTC pricing: price = btcPrice * BTCVault.convertToAssets(1e8) / 1e8
        _reconfigureOracleForBvBTC();

        vm.stopBroadcast();

        console2.log("=== Phase 3c Complete - All operations executed ===");
    }

    /// @notice Loads all required addresses using HelperConfig getters
    function _loadAddresses() internal {
        address accessManager = helperConfig.getAccessManager();
        manager = BitmorAccessManager(accessManager);

        btcVault = helperConfig.getBTCVault();
        usdcVault = helperConfig.getUSDCVault();
        aaveStrategy = helperConfig.getAaveTokenizedStrategy();
        usdcStrategy = helperConfig.getUSDCStrategy();
        aaveOracle = helperConfig.getOracle();
        mockCbBTC = helperConfig.getCbBTC();

        console2.log("Loaded addresses from HelperConfig:");
        console2.log("  AccessManager:", accessManager);
        console2.log("  BTCVault:", btcVault);
        console2.log("  USDCVault:", usdcVault);
        console2.log("  AaveOracle:", aaveOracle);
    }

    /// @notice Reconfigures AaveOracle to use the real bvBTC pricing path
    /// @dev Called after addStrategy so BTCVault.convertToAssets() works correctly.
    ///      In DeployPhase3Local, the bvBTC path was disabled (setbvBTC(address(0))) because
    ///      the strategy wasn't wired yet. Now we enable it:
    ///      1. Set s_bvBTC = btcVault so getAssetPrice detects the bvBTC path
    ///      2. Set s_btc = mockCbBTC so btcPrice lookup works
    ///      3. Remove btcVault from direct assetsSources (no longer needs direct oracle)
    function _reconfigureOracleForBvBTC() internal {
        console2.log("Reconfiguring AaveOracle for real bvBTC pricing path...");

        // Enable the special bvBTC pricing path
        (bool okBvBtc,) = aaveOracle.call(abi.encodeWithSignature("setbvBTC(address)", btcVault));
        require(okBvBtc, "Failed to setbvBTC");
        console2.log("  setbvBTC:", btcVault);

        // Ensure s_btc is set (should already be from DeployPhase3Local, but confirm)
        (bool okBtc,) = aaveOracle.call(abi.encodeWithSignature("setBTC(address)", mockCbBTC));
        require(okBtc, "Failed to setBTC");
        console2.log("  setBTC:", mockCbBTC);

        // Update assetsSources: remove btcVault from direct pricing (it now uses convertToAssets path).
        // Keep mockCbBTC and mockUsdc with their direct oracle sources.
        address btcOracleAddr = helperConfig.getBtcUsdOracle();
        address usdcOracleAddr = helperConfig.getUsdcUsdOracle();
        address mockUsdc = helperConfig.getUSDC();

        address[] memory assets = new address[](2);
        address[] memory sources = new address[](2);
        assets[0] = mockCbBTC;
        assets[1] = mockUsdc;
        sources[0] = btcOracleAddr;
        sources[1] = usdcOracleAddr;
        (bool ok,) = aaveOracle.call(abi.encodeWithSignature("setAssetSources(address[],address[])", assets, sources));
        require(ok, "Failed to update oracle sources");
        console2.log("  Updated assetsSources (cbBTC, USDC direct; bvBTC via convertToAssets)");
        console2.log("AaveOracle bvBTC pricing path active.");
    }
}
