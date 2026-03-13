// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/Script.sol";
import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";
import {MockUSDC, MockCbBTC} from "../../../test/mock/MintableERC20.sol";
import {MockChainlinkOracle} from "../../../test/mock/MockChainlinkOracle.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {MockAaveV3Pool} from "../../../test/mock/MockAaveV3Pool.sol";
import {DeploymentConstants} from "../DeploymentConstants.sol";
import {LocalRolesConfig} from "@bitmor-config/LocalRolesConfig.sol";
import {HelperConfig} from "../../HelperConfig.s.sol";

/**
 * @title DeployPhase1Local
 * @author Bitmor Protocol
 * @notice Phase 1 local deployment: AccessManager, mock tokens/oracles, BTCVault (UUPS proxy), MockAaveV3Pool
 * @dev Replaces the original DeployPhase1.s.sol for the upgradeable architecture.
 * Key change: BTCVault is deployed as a UUPS proxy via `_deployUUPSProxy()` instead of `new BTCVault(...)`.
 * All other contracts (AccessManager, mocks) are deployed directly since they are not upgradeable.
 * @custom:security Only for local Anvil deployments (chainId 31337)
 */
contract DeployPhase1Local is LocalRolesConfig {
    /// @notice Deployed BitmorAccessManager address
    address public accessManager;

    /// @notice Deployed MockUSDC address
    address public mockUsdc;

    /// @notice Deployed MockCbBTC address
    address public mockCbBTC;

    /// @notice Deployed BTC/USD mock oracle address
    address public btcOracle;

    /// @notice Deployed USDC/USD mock oracle address
    address public usdcOracle;

    /// @notice Deployed BTCVault proxy address
    address public btcVault;

    /// @notice Deployed BTCVault implementation address
    address public btcVaultImpl;

    /// @notice Deployed MockAaveV3Pool address
    address public mockAaveV3Pool;

    /// @notice Main entry point for Phase 1 local deployment
    /// @dev Deploys all Phase 1 contracts and persists addresses to deployments.json.
    /// Deployment order:
    /// 1. BitmorAccessManager (direct deploy, owned by `msg.sender`)
    /// 2. MockUSDC + MockCbBTC (direct deploy)
    /// 3. MockChainlinkOracle for BTC/USD and USDC/USD (direct deploy)
    /// 4. BTCVault as UUPS proxy (via `_deployUUPSProxy`)
    /// 5. MockAaveV3Pool (direct deploy)
    function run() external {
        _preflightPhase1(DeploymentConstants.LOCAL_CHAIN_ID);

        console2.log("=== Phase 1: Local Deployment (Upgradeable) ===");

        vm.startBroadcast();

        // 1. AccessManager
        accessManager = address(new BitmorAccessManager(msg.sender));
        console2.log("AccessManager:", accessManager);

        // 2. Mock Tokens
        mockUsdc = address(new MockUSDC());
        mockCbBTC = address(new MockCbBTC());
        console2.log("MockUSDC:", mockUsdc);
        console2.log("MockCbBTC:", mockCbBTC);

        // 3. Mock Oracles
        btcOracle = address(
            new MockChainlinkOracle(
                DeploymentConstants.ORACLE_DECIMALS,
                DeploymentConstants.BTC_USD_PRICE,
                DeploymentConstants.BTC_USD_DESCRIPTION
            )
        );
        usdcOracle = address(
            new MockChainlinkOracle(
                DeploymentConstants.ORACLE_DECIMALS,
                DeploymentConstants.USDC_USD_PRICE,
                DeploymentConstants.USDC_USD_DESCRIPTION
            )
        );
        console2.log("BTC Oracle:", btcOracle);
        console2.log("USDC Oracle:", usdcOracle);

        // 4. BTCVault (UUPS proxy)
        // Upgrades.deployUUPSProxy deploys the implementation internally — read its
        // address from the proxy's EIP-1967 slot rather than deploying a second copy.
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.ProtocolConfig memory pc = helperConfig.getProtocolConfig();
        btcVault = _deployUUPSProxy(
            "BTCVault.sol", abi.encodeCall(BTCVault.initialize, (mockCbBTC, accessManager, pc.maxStrategies))
        );
        btcVaultImpl = _getProxyImplementation(btcVault);
        console2.log("BTCVault proxy:", btcVault);
        console2.log("BTCVault impl:", btcVaultImpl);

        // 5. Mock Aave V3 Pool
        mockAaveV3Pool = address(new MockAaveV3Pool());
        console2.log("MockAaveV3Pool:", mockAaveV3Pool);

        vm.stopBroadcast();

        // 6. Save to deployments.json
        _savePhase1();

        // 7. Write deployment manifest
        _writeManifest("Phase1");

        console2.log("=== Phase 1 Complete ===");
    }

    /// @notice Persists all Phase 1 addresses to deployments.json
    /// @dev Builds a JSON key-value string and delegates to `_mergeAndSave()`.
    /// Includes both `collateralAsset` (BTCVault proxy) and `btcVaultImpl` (implementation)
    /// for HelperConfig compatibility.
    function _savePhase1() internal {
        string memory keys = string.concat(
            '"accessManager":"',
            vm.toString(accessManager),
            '",',
            '"collateralAsset":"',
            vm.toString(btcVault),
            '",',
            '"btcVaultImpl":"',
            vm.toString(btcVaultImpl),
            '",',
            '"debtAsset":"',
            vm.toString(mockUsdc),
            '",',
            '"cbBTC":"',
            vm.toString(mockCbBTC),
            '",',
            '"btc":"',
            vm.toString(mockCbBTC),
            '",',
            '"btcOracle":"',
            vm.toString(btcOracle),
            '",',
            '"usdcOracle":"',
            vm.toString(usdcOracle),
            '",',
            '"aaveV3Pool":"',
            vm.toString(mockAaveV3Pool),
            '",',
            '"aaveAddressesProvider":"',
            vm.toString(mockAaveV3Pool),
            '"'
        );

        _mergeAndSave(keys, DeploymentConstants.LOCAL_CHAIN_ID, "localhost");
    }
}
