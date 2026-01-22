// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";
import {MockUSDC, MockCbBTC} from "@bitmor/mocks/MintableERC20.sol";
import {MockChainlinkOracle} from "../../test/mock/MockChainlinkOracle.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {DeploymentConstants} from "./DeploymentConstants.sol";

/// @title DeployPhase1
/// @author Bitmor Protocol
/// @notice Consolidated Phase 1 deployment for local development
/// @dev Deploys: AccessManager, MockTokens, MockOracles, BTCVault
/// @custom:security Only for local Anvil deployments (chainId 31337)
contract DeployPhase1 is Script {
    /// @notice Deployed AccessManager address
    address public accessManager;
    /// @notice Deployed MockUSDC address
    address public mockUsdc;
    /// @notice Deployed MockCbBTC address
    address public mockCbBTC;
    /// @notice Deployed BTC/USD oracle address
    address public btcOracle;
    /// @notice Deployed USDC/USD oracle address
    address public usdcOracle;
    /// @notice Deployed BTCVault address
    address public btcVault;

    /// @notice Main entry point for Phase 1 deployment
    /// @dev Deploys all Phase 1 contracts and saves addresses to deployments.json
    function run() external {
        require(block.chainid == DeploymentConstants.LOCAL_CHAIN_ID, "DeployPhase1: only for local");

        console2.log("=== Phase 1: Local Deployment ===");

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

        // 4. BTCVault
        btcVault = address(new BTCVault(mockCbBTC, accessManager));
        console2.log("BTCVault:", btcVault);

        vm.stopBroadcast();

        // 5. Save to deployments.json
        _saveDeployments();

        console2.log("=== Phase 1 Complete ===");
    }

    /// @notice Saves deployed addresses to deployments.json
    /// @dev Creates JSON structure compatible with HelperConfig._readLocalDeployment()
    function _saveDeployments() internal {
        string memory networkConfig = string.concat(
            "{",
            '"accessManager":"',
            vm.toString(accessManager),
            '",',
            '"collateralAsset":"',
            vm.toString(btcVault),
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
            '"',
            "}"
        );

        string memory fullJson =
            string.concat('{"deployments":{"31337":{"network":"localhost","networkConfig":', networkConfig, "}}}");

        vm.writeFile("./deployments.json", fullJson);
        console2.log("Saved to deployments.json");
    }
}
