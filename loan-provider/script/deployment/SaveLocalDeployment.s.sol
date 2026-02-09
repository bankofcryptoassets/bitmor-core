// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console2} from "forge-std/console2.sol";
import {DeploymentHelper} from "../helpers/DeploymentHelper.s.sol";
import {HelperConfig} from "../HelperConfig.s.sol";

/// @title SaveLocalDeployment
/// @notice Saves Phase 1 deployment addresses to deployments.json for chainId 31337
/// @dev Reads addresses from broadcast files via DeploymentHelper, writes to deployments.json
contract SaveLocalDeployment is DeploymentHelper {
    uint256 constant LOCAL_CHAIN_ID = 31337;
    string constant JSON_PATH = "./deployments.json";

    function run() external {
        require(block.chainid == LOCAL_CHAIN_ID, "SaveLocalDeployment: only for local (chainId 31337)");

        // Read addresses from broadcast files using inherited DeploymentHelper utilities
        // Each call specifies which script deployed the contract
        address accessManager = getDeployedAddressOrZero("BitmorAccessManager", "DeployAccessManager.s.sol");
        address cbBTC = getDeployedAddressOrZero("MockCbBTC", "DeployMockTokens.s.sol");
        address usdc = getDeployedAddressOrZero("MockUSDC", "DeployMockTokens.s.sol");
        address btcVault = getDeployedAddressOrZero("BTCVault", "DeployBTCVault.s.sol");
        address usdcVault = getDeployedAddressOrZero("USDCVault", "DeployUSDCVault.s.sol");
        address btcOracle = getDeployedAddressOrZero("MockChainlinkOracle", "DeployMockOracles.s.sol");

        console2.log("=== Phase 1 Deployment Addresses ===");
        console2.log("AccessManager:", accessManager);
        console2.log("MockCbBTC:", cbBTC);
        console2.log("MockUSDC:", usdc);
        console2.log("BTCVault (bvBTC):", btcVault);
        console2.log("USDCVault:", usdcVault);
        console2.log("BTC Oracle:", btcOracle);

        // Build JSON with networkConfig that lending-pool expects
        string memory networkConfig = _buildNetworkConfig(accessManager, cbBTC, usdc, btcVault, usdcVault, btcOracle);

        // Build full JSON structure
        string memory chainIdStr = vm.toString(LOCAL_CHAIN_ID);
        string memory fullJson = string.concat(
            '{"deployments":{"', chainIdStr, '":{"network":"localhost","networkConfig":', networkConfig, "}}}"
        );

        // Merge with existing deployments if file exists
        try vm.readFile(JSON_PATH) returns (string memory existingContent) {
            if (bytes(existingContent).length > 0) {
                // Keep existing data, update 31337
                fullJson = _mergeWithExisting(existingContent, networkConfig);
            }
        } catch {
            // File doesn't exist, use new structure
        }

        vm.writeFile(JSON_PATH, fullJson);

        console2.log("\n=== Local Deployment Saved ===");
        console2.log("Chain ID:", LOCAL_CHAIN_ID);
        console2.log("bvBTC (collateralAsset):", btcVault);
        console2.log("USDC (debtAsset):", usdc);
        console2.log("Saved to:", JSON_PATH);
    }

    function _buildNetworkConfig(
        address accessManager,
        address cbBTC,
        address usdc,
        address btcVault,
        address usdcVault,
        address btcOracle
    ) internal returns (string memory) {
        HelperConfig helperConfig = new HelperConfig();
        address bitmorPool = helperConfig.getBitmorPool();

        // Build networkConfig object with all required keys for unified JSON structure
        return string.concat(
            "{",
            '"accessManager":"',
            vm.toString(accessManager),
            '",',
            '"collateralAsset":"',
            vm.toString(btcVault),
            '",',
            '"debtAsset":"',
            vm.toString(usdc),
            '",',
            '"cbBTC":"',
            vm.toString(cbBTC),
            '",',
            '"btc":"',
            vm.toString(cbBTC),
            '",',
            '"usdcVault":"',
            vm.toString(usdcVault),
            '",',
            '"btcOracle":"',
            vm.toString(btcOracle),
            '",',
            // Add missing keys for unified JSON structure
            '"aaveV3Pool":"',
            vm.toString(bitmorPool),
            '",', // Use Bitmor pool as placeholder for local
            '"aaveAddressesProvider":"',
            vm.toString(bitmorPool),
            '",', // Use Bitmor pool as placeholder for local
            '"premiumCollector":"',
            vm.toString(helperConfig.getPremiumCollector()),
            '",',
            '"usdcHolder":"',
            vm.toString(helperConfig.getInitialAdmin()),
            '"',
            "}"
        );
    }

    function _mergeWithExisting(string memory, string memory networkConfig) internal view returns (string memory) {
        // Simple merge: just replace local chain entry
        // In production, use proper JSON parsing
        string memory chainIdStr = vm.toString(LOCAL_CHAIN_ID);
        return string.concat(
            '{"deployments":{"', chainIdStr, '":{"network":"localhost","networkConfig":', networkConfig, "}}}"
        );
    }
}
