// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {DeploymentHelper} from "../helpers/DeploymentHelper.s.sol";
import {StrategyConfig} from "../StrategyConfig.s.sol";
import {AaveTokenizedStrategy} from "@btcVault/TokenizedStrategy/AaveTokenizedStrategy.sol";
import {USDCStrategy} from "@usdcVault/USDCStrategy.sol";

/// @title DeployStrategies
/// @author Bitmor Protocol
/// @notice Deploys vault strategies based on StrategyConfig
/// @dev Deploys AaveTokenizedStrategy for BTCVault and USDCStrategy for USDCVault
contract DeployStrategies is Script, DeploymentHelper {
    /// @notice Deploys vault strategies
    /// @return aaveStrategy Address of deployed AaveTokenizedStrategy (or zero)
    /// @return usdcStrategy Address of deployed USDCStrategy (or zero)
    function run() external returns (address aaveStrategy, address usdcStrategy) {
        StrategyConfig strategyConfig = new StrategyConfig();
        StrategyConfig.StrategyDeploymentConfig memory config = strategyConfig.getStrategyConfig();

        // Get deployed vault addresses
        address btcVault = requireDeployed("BTCVault");
        address usdcVault = requireDeployed("USDCVault");

        vm.startBroadcast();

        // Deploy BTC Vault Strategy (AaveTokenizedStrategy)
        if (config.btcVault.deployAaveStrategy) {
            AaveTokenizedStrategy strategy = new AaveTokenizedStrategy(config.btcVault.yieldSource, btcVault);
            aaveStrategy = address(strategy);
            console.log("AaveTokenizedStrategy deployed:", aaveStrategy);
        }

        // Deploy USDC Vault Strategy
        // Note: USDCStrategy constructor is (vault, aave, blp)
        if (config.usdcVault.deployUSDCStrategy) {
            USDCStrategy strategy = new USDCStrategy(usdcVault, config.usdcVault.aavePool, config.usdcVault.blpPool);
            usdcStrategy = address(strategy);
            console.log("USDCStrategy deployed:", usdcStrategy);
        }

        vm.stopBroadcast();

        console.log("=== Strategies Deployed ===");
    }
}
