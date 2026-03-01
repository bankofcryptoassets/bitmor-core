// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

/**
 * @title IPriceOracleGetter interface
 * @notice Interface for the Aave price oracle.
 */

interface IPriceOracleGetter {
    event PriceOracleGetter__BaseCurrencySet(
        address indexed baseCurrency,
        uint256 baseCurrencyUnit
    );
    event PriceOracleGetter__AssetSourceUpdated(address indexed asset, address indexed source);
    event PriceOracleGetter__BTCAddressUpdated(address indexed newBTCAddress);
    event PriceOracleGetter__BVBTCAddressUpdated(address indexed newBVBTCAddress);
    event PriceOracleGetter__FallbackOracleUpdated(address indexed fallbackOracle);

    /**
     * @notice Gets an asset price by address
     * @dev For bvBTC, uses `previewRedeem` instead of `convertToAssets` to account for
     *      exit fees, ensuring the oracle reflects the actual realizable value of collateral
     * @param asset The asset address
     */
    function getAssetPrice(address asset) external view returns (uint256);

    /**
     * @notice Gets a list of prices from a list of assets addresses
     * @param assets The list of assets addresses
     * @return The list of prices
     */
    function getAssetsPrices(address[] calldata assets) external view returns (uint256[] memory);

    /**
     * @notice Gets the address of the fallback oracle
     * @return address The address of the fallback oracle
     */
    function getFallbackOracle() external view returns (address);

    /**
     * @notice Updates the BTC token address used for price derivation
     * @param _btc The new BTC token address
     */
    function setBTC(address _btc) external;

    /**
     * @notice Updates the bvBTC vault address used for share-to-asset conversion
     * @param _bvBTC The new bvBTC vault address
     */
    function setbvBTC(address _bvBTC) external;

    /**
     * @notice Sets the fallbackOracle
     * @dev Callable only by the Aave governance
     * @param fallbackOracle The address of the fallbackOracle
     */
    function setFallbackOracle(address fallbackOracle) external;
}
