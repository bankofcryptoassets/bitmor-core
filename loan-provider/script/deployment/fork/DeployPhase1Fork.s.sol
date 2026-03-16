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
/// Saves to deployments.json under key "31337-fork" (via _getChainKey()).
/// Also persists external protocol addresses (USDC, Aave V3) so DeployLibraries can read them.
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

        _savePhase1(helperConfig);
        _writeManifest("Phase1");

        console2.log("=== Phase 1 Complete ===");
    }

    /// @notice Persists Phase 1 addresses plus external protocol addresses needed by DeployLibraries
    /// @dev DeployLibraries._readChunk1/2 requires debtAsset, aaveV3Pool, aaveAddressesProvider
    /// to exist in deployments.json. On local these come from mocks; on fork we must
    /// persist the real addresses here so DeployLibraries can read them.
    function _savePhase1(HelperConfig helperConfig) internal {
        address usdcAddr = helperConfig.getUSDC();
        address aaveV3Pool = helperConfig.getAaveV3Pool();
        address aaveAddressesProvider = helperConfig.getAaveAddressesProvider();

        string memory keys = string.concat(
            '"accessManager":"',
            vm.toString(accessManager),
            '","collateralAsset":"',
            vm.toString(btcVault),
            '","btcVaultImpl":"',
            vm.toString(btcVaultImpl),
            '","cbBTC":"',
            vm.toString(cbBTCAddr),
            '","btc":"',
            vm.toString(cbBTCAddr),
            '","debtAsset":"',
            vm.toString(usdcAddr),
            '","aaveV3Pool":"',
            vm.toString(aaveV3Pool),
            '","aaveAddressesProvider":"',
            vm.toString(aaveAddressesProvider),
            '"'
        );

        _mergeAndSave(keys, helperConfig.getChainKey(), "base-fork");
    }
}
