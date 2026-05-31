// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/Script.sol";
import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";
import {MockUSDC, MockCbBTC} from "../../../test/mock/MintableERC20.sol";
import {ChainlinkOracleWrapper} from "../../../test/mock/ChainlinkOracleWrapper.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {MockAaveV3Pool} from "../../../test/mock/MockAaveV3Pool.sol";
import {DeploymentConstants} from "../DeploymentConstants.sol";
import {TestnetRolesConfig} from "@bitmor-config/TestnetRolesConfig.sol";
import {HelperConfig} from "../../HelperConfig.s.sol";

/**
 * @title DeployPhase1Testnet
 * @author Bitmor Protocol
 * @notice Phase 1 Base Sepolia testnet deployment: AccessManager, mock tokens, Chainlink oracle wrappers, BTCVault (UUPS proxy),
 *         MockAaveV3Pool
 * @dev Replaces the original DeployPhase1.s.sol for the upgradeable architecture.
 * Key change: BTCVault is deployed as a UUPS proxy via `_deployUUPSProxy()` instead of `new BTCVault(...)`.
 * All other contracts (AccessManager, mocks) are deployed directly since they are not upgradeable.
 * @custom:security Only for Base Sepolia testnet deployments (chainId 84532)
 */
contract DeployPhase1Testnet is TestnetRolesConfig {
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

    /// @notice Main entry point for Phase 1 Base Sepolia testnet deployment
    /// @dev Deploys all Phase 1 contracts. Address persistence is handled externally.
    /// Deployment order:
    /// 1. BitmorAccessManager (direct deploy, owned by `msg.sender`)
    /// 2. MockUSDC + MockCbBTC (direct deploy)
    /// 3. ChainlinkOracleWrapper for BTC/USD and USDC/USD (wrapping real Chainlink feeds)
    /// 4. BTCVault as UUPS proxy (via `_deployUUPSProxy`)
    /// 5. MockAaveV3Pool (direct deploy)
    function run() external {
        _preflightPhase1(DeploymentConstants.BASE_SEPOLIA_CHAIN_ID);

        console2.log("=== Phase 1: Base Sepolia Testnet Deployment (Upgradeable) ===");

        vm.startBroadcast();

        // 1. AccessManager
        accessManager = address(new BitmorAccessManager(msg.sender));
        console2.log("AccessManager:", accessManager);

        // 2. Mock Tokens
        mockUsdc = address(new MockUSDC());
        mockCbBTC = address(new MockCbBTC());
        console2.log("MockUSDC:", mockUsdc);
        console2.log("MockCbBTC:", mockCbBTC);

        // 3. Chainlink Oracle Wrappers (wrap real feeds with override capability)
        btcOracle = address(new ChainlinkOracleWrapper(DeploymentConstants.BASE_SEPOLIA_BTC_USD_FEED));
        usdcOracle = address(new ChainlinkOracleWrapper(DeploymentConstants.BASE_SEPOLIA_USDC_USD_FEED));
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

        console2.log("=== Phase 1 Complete ===");
    }
}
