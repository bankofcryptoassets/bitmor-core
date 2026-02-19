// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

/// @title StrategyConfig
/// @author Bitmor Protocol
/// @notice Configuration for vault strategy deployments
/// @dev Provides chain-aware strategy configuration separate from network config
contract StrategyConfig is Script {
    /// @notice Configuration for BTCVault strategy deployment
    struct BTCVaultStrategyConfig {
        bool deployAaveStrategy;
        /// @dev Whether to deploy AaveTokenizedStrategy
        address yieldSource;
    }

    /// @dev Aave pool address for AaveTokenizedStrategy

    /// @notice Configuration for USDCVault strategy deployment
    struct USDCVaultStrategyConfig {
        bool deployUSDCStrategy;
        /// @dev Whether to deploy USDCStrategy
        address aavePool;
        /// @dev Aave V3 pool address
        address blpPool;
        /// @dev Bitmor Lending Pool address
        uint256 aaveAllocation;
        /// @dev Basis points for Aave allocation (e.g., 8000 = 80%)
        uint256 minimumDeltaRequired;
    }

    /// @dev Basis points threshold for reallocation

    /// @notice Complete strategy deployment configuration
    struct StrategyDeploymentConfig {
        BTCVaultStrategyConfig btcVault;
        USDCVaultStrategyConfig usdcVault;
    }

    /// @dev Cached HelperConfig instance to avoid redundant instantiation
    HelperConfig internal _cachedHelperConfig;

    /// @notice Returns strategy configuration for current chain
    /// @dev Creates a new HelperConfig instance internally
    /// @return config The strategy deployment configuration
    function getStrategyConfig() public returns (StrategyDeploymentConfig memory config) {
        return getStrategyConfig(new HelperConfig());
    }

    /// @notice Returns strategy configuration using provided HelperConfig
    /// @dev Use this overload when you already have a HelperConfig instance to avoid redundant instantiation
    /// @param helperConfig Existing HelperConfig instance to read from
    /// @return config The strategy deployment configuration
    function getStrategyConfig(HelperConfig helperConfig) public returns (StrategyDeploymentConfig memory config) {
        _cachedHelperConfig = helperConfig;

        if (block.chainid == helperConfig.CHAIN_ID_LOCAL()) {
            return _getLocalStrategyConfig();
        } else if (block.chainid == helperConfig.CHAIN_ID_BASE_SEPOLIA()) {
            return _getBaseSepoliaStrategyConfig();
        }
        revert("StrategyConfig: unsupported chain");
    }

    /// @notice Returns the cached HelperConfig instance
    /// @dev Returns the HelperConfig used in the last getStrategyConfig call
    /// @return The cached HelperConfig or reverts if not set
    function getCachedHelperConfig() public view returns (HelperConfig) {
        require(address(_cachedHelperConfig) != address(0), "StrategyConfig: no cached config");
        return _cachedHelperConfig;
    }

    /// @notice Returns strategy config for local Anvil deployment
    function _getLocalStrategyConfig() internal view returns (StrategyDeploymentConfig memory) {
        address aaveV3Pool = _cachedHelperConfig.getAaveV3Pool();
        address bitmorPool = _cachedHelperConfig.getBitmorPool();

        return StrategyDeploymentConfig({
            btcVault: BTCVaultStrategyConfig({deployAaveStrategy: true, yieldSource: aaveV3Pool}),
            usdcVault: USDCVaultStrategyConfig({
                deployUSDCStrategy: true,
                aavePool: aaveV3Pool,
                blpPool: bitmorPool,
                aaveAllocation: _cachedHelperConfig.getAaveAllocation(),
                minimumDeltaRequired: _cachedHelperConfig.getMinimumDeltaRequired()
            })
        });
    }

    /// @notice Returns strategy config for Base Sepolia deployment
    function _getBaseSepoliaStrategyConfig() internal view returns (StrategyDeploymentConfig memory) {
        address aaveV3Pool = _cachedHelperConfig.getAaveV3Pool();
        address bitmorPool = _cachedHelperConfig.getBitmorPool();

        return StrategyDeploymentConfig({
            btcVault: BTCVaultStrategyConfig({deployAaveStrategy: true, yieldSource: aaveV3Pool}),
            usdcVault: USDCVaultStrategyConfig({
                deployUSDCStrategy: true,
                aavePool: aaveV3Pool,
                blpPool: bitmorPool,
                aaveAllocation: _cachedHelperConfig.getAaveAllocation(),
                minimumDeltaRequired: _cachedHelperConfig.getMinimumDeltaRequired()
            })
        });
    }
}
