// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/Script.sol";
import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {DeploymentConstants} from "../DeploymentConstants.sol";
import {MainnetRolesConfig} from "@bitmor-config/MainnetRolesConfig.sol";
import {HelperConfig} from "../../HelperConfig.s.sol";

/**
 * @title DeployPhase1Mainnet
 * @author Bitmor Protocol
 * @notice Phase 1 mainnet deployment: AccessManager and BTCVault (UUPS proxy)
 * @dev Deploys only protocol-owned contracts. No mock deployments on mainnet; all external
 * protocol addresses (Aave V3, cbBTC, oracles) are resolved via HelperConfig at runtime.
 *
 * Key differences from DeployPhase1Local:
 * - No MockUSDC, MockCbBTC, MockOracles, or MockAaveV3Pool
 * - Uses real cbBTC address as BTCVault underlying
 * - Inherits MainnetRolesConfig (multisig-based grantees)
 * - Addresses saved to deployments/8453/latest.json by bitmor-deploy CLI after broadcast
 *
 * @custom:security For Base mainnet deployment (chainId 8453). Verify all addresses before broadcast.
 */
contract DeployPhase1Mainnet is MainnetRolesConfig {
    /// @notice Deployed BitmorAccessManager address
    address public accessManager;

    /// @notice Deployed BTCVault proxy address
    address public btcVault;

    /// @notice Deployed BTCVault implementation address
    address public btcVaultImpl;

    /**
     * @notice Main entry point for Phase 1 mainnet deployment
     * @dev Deploys only protocol-owned contracts:
     * 1. BitmorAccessManager (direct deploy, owned by `msg.sender`)
     * 2. BTCVault as UUPS proxy (via `_deployUUPSProxy`)
     *
     * External protocol addresses are NOT deployed; they are resolved at runtime by HelperConfig.
     */
    /// @notice cbBTC address resolved from HelperConfig
    address public cbBTCAddr;

    function run() external {
        _preflightPhase1(DeploymentConstants.BASE_MAINNET_CHAIN_ID);

        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.ProtocolConfig memory pc = helperConfig.getProtocolConfig();
        cbBTCAddr = helperConfig.getCbBTC();

        require(cbBTCAddr != address(0), "DeployPhase1Mainnet: set CBBTC_BASE_MAINNET in HelperConfig");
        require(cbBTCAddr.code.length > 0, "DeployPhase1Mainnet: cbBTC has no bytecode");

        console2.log("=== Phase 1: Mainnet Deployment (Upgradeable) ===");

        vm.startBroadcast();

        // 1. AccessManager
        accessManager = address(new BitmorAccessManager(msg.sender));
        console2.log("AccessManager:", accessManager);

        // 2. BTCVault (UUPS proxy) — uses real cbBTC as underlying
        // Upgrades.deployUUPSProxy deploys the implementation internally — read its
        // address from the proxy's EIP-1967 slot rather than deploying a second copy.
        btcVault = _deployUUPSProxy(
            "BTCVault.sol", abi.encodeCall(BTCVault.initialize, (cbBTCAddr, accessManager, pc.maxStrategies))
        );
        btcVaultImpl = _getProxyImplementation(btcVault);
        console2.log("BTCVault proxy:", btcVault);
        console2.log("BTCVault impl:", btcVaultImpl);

        vm.stopBroadcast();

        console2.log("=== Phase 1 Complete ===");
    }
}
