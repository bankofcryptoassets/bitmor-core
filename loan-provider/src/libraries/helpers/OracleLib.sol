// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {IPriceOracleGetter} from "../../interfaces/IPriceOracleGetter.sol";
import {IPriceOracleGetterWithFreshness} from "../../interfaces/IPriceOracleGetterWithFreshness.sol";
import {Errors} from "./Errors.sol";

/**
 * @title OracleLib
 * @author Bitmor Protocol
 * @notice Library for validating oracle price freshness
 * @dev Calls `getAssetPriceWithTimestamp()` and reverts if the price is stale or zero.
 *
 * @custom:security If `updatedAt` is in the future (e.g. timestamp variance), the price
 * is treated as stale to avoid an arithmetic underflow panic.
 */
library OracleLib {
    /**
     * @notice Returns the price of `asset` after validating freshness and non-zero value
     * @param oracle The oracle address implementing IPriceOracleGetterWithFreshness
     * @param asset The asset to query
     * @param maxStaleness Maximum acceptable age of the price in seconds
     * @return price The validated price (guaranteed non-zero)
     */
    function getValidatedPrice(address oracle, address asset, uint256 maxStaleness)
        internal
        view
        returns (uint256 price)
    {
        uint256 updatedAt;
        (price, updatedAt) = IPriceOracleGetterWithFreshness(oracle).getAssetPriceWithTimestamp(asset);
        if (updatedAt > block.timestamp || block.timestamp - updatedAt > maxStaleness) {
            revert Errors.StaleOraclePrice();
        }
        if (price == 0) revert Errors.InvalidAssetPrice();
    }

    /**
     * @notice Returns the price of `asset`, with optional freshness validation
     * @dev When `maxStaleness == 0`, staleness is disabled and falls back to `getAssetPrice()`.
     * When `maxStaleness > 0`, delegates to `getValidatedPrice()` which checks freshness and zero price.
     * @param oracle The oracle address
     * @param asset The asset to query
     * @param maxStaleness Maximum acceptable age in seconds (0 = disabled)
     * @return price The asset price
     */
    function getPrice(address oracle, address asset, uint256 maxStaleness) internal view returns (uint256 price) {
        if (maxStaleness > 0) {
            return getValidatedPrice(oracle, asset, maxStaleness);
        }
        return IPriceOracleGetter(oracle).getAssetPrice(asset);
    }
}
