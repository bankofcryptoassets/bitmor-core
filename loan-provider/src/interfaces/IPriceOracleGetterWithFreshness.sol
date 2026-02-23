// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {IPriceOracleGetter} from "./IPriceOracleGetter.sol";

/**
 * @title IPriceOracleGetterWithFreshness
 * @author Bitmor Protocol
 * @notice Extends IPriceOracleGetter with a timestamp-aware price getter for staleness validation
 */
interface IPriceOracleGetterWithFreshness is IPriceOracleGetter {
    /**
     * @notice Returns the price and last update timestamp of `asset`
     * @param asset The address of the asset to query
     * @return price The price of the asset
     * @return updatedAt The timestamp when the price was last updated
     */
    function getAssetPriceWithTimestamp(address asset) external view returns (uint256 price, uint256 updatedAt);
}
