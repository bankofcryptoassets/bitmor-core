// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

/**
 * @title IPriceOracleGetter
 * @author Aave
 * @notice Interface for the Aave/Bitmor price oracle used for asset pricing
 */
interface IPriceOracleGetter {
    /**
     * @notice Returns the price of `asset` in the base currency (ETH/USD)
     * @param asset The address of the asset to query the price for
     * @return The price of the asset
     */
    function getAssetPrice(address asset) external view returns (uint256);
}
