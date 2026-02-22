// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {IPriceOracleGetter} from "../../interfaces/IPriceOracleGetter.sol";
import {Errors} from "../helpers/Errors.sol";

/// @title IAaveOracle
/// @dev Extended interface to access Chainlink source addresses from AaveOracle
interface IAaveOracle is IPriceOracleGetter {
    function getSourceOfAsset(address asset) external view returns (address);
}

/// @title IChainlinkAggregatorV3
/// @dev Minimal Chainlink AggregatorV3Interface for latestRoundData
interface IChainlinkAggregatorV3 {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @title OracleLogic
/// @author Bitmor Protocol
/// @notice Library for fetching oracle prices with Chainlink freshness validation
/// @dev Wraps IPriceOracleGetter.getAssetPrice() with updatedAt staleness checks.
///      Only used for BTC/collateral price fetches. USDC (stable) skips freshness checks.
library OracleLogic {
    /// @notice Fetches the asset price from the oracle after validating Chainlink freshness
    /// @dev If `getSourceOfAsset()` returns address(0) (e.g. bvBTC which derives from BTC),
    ///      the freshness check is skipped. This is safe because the underlying BTC source
    ///      is validated separately at its own call site.
    /// @param oracle The AaveOracle address
    /// @param asset The asset to price
    /// @param maxStaleness Maximum allowed age of the Chainlink price update in seconds
    /// @return price The asset price in oracle-native precision
    function getValidatedPrice(address oracle, address asset, uint256 maxStaleness)
        internal
        view
        returns (uint256 price)
    {
        _validateFreshness(oracle, asset, maxStaleness);
        price = IPriceOracleGetter(oracle).getAssetPrice(asset);
        if (price == 0) revert Errors.InvalidAssetPrice();
    }

    /// @dev Checks that the Chainlink source for `asset` has been updated within `maxStaleness` seconds
    function _validateFreshness(address oracle, address asset, uint256 maxStaleness) private view {
        address source = IAaveOracle(oracle).getSourceOfAsset(asset);
        // If no Chainlink source (uses fallback or derived price), skip freshness check
        if (source == address(0)) return;

        (, int256 answer,, uint256 updatedAt,) = IChainlinkAggregatorV3(source).latestRoundData();
        if (answer <= 0) revert Errors.InvalidAssetPrice();
        if (block.timestamp - updatedAt > maxStaleness) {
            revert Errors.StaleOraclePrice();
        }
    }
}
