// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@solady/tokens/ERC20.sol";
import {IPriceOracleGetterWithFreshness} from "@bitmor/interfaces/IPriceOracleGetterWithFreshness.sol";
import {ERC4626} from "@solady/tokens/ERC4626.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

/// @title MockPriceOracle
/// @author Bitmor Protocol
/// @notice Mock price oracle for unit testing with configurable asset prices and staleness
/// @dev Implements IPriceOracleGetterWithFreshness. For `btcVault`, computes price as BTC price
///      scaled by the vault's share-to-asset conversion rate. All other assets return stored prices directly.
contract MockPriceOracle is IPriceOracleGetterWithFreshness {
    using FixedPointMathLib for uint256;

    /// @dev Mapping of asset address to price (8 decimals, e.g., 100000e8 = $100,000)
    mapping(address => uint256) private _prices;

    /// @dev Mapping of asset address to last updated timestamp
    mapping(address => uint256) private _lastUpdatedAt;

    /// @notice Address of the BTC vault whose price is derived from share conversion
    address public btcVault;

    /// @notice Address of the underlying BTC token used for vault price derivation
    address public btc;

    /// @notice Creates a new MockPriceOracle
    /// @param _btcVault Address of the BTC vault (price derived from share-to-asset ratio)
    /// @param _btc Address of the underlying BTC token
    constructor(address _btcVault, address _btc) {
        btcVault = _btcVault;
        btc = _btc;
    }

    /// @notice Set the price for an asset
    /// @param asset The asset address
    /// @param price The price in 8 decimals (e.g., 100000e8 = $100,000)
    function setAssetPrice(address asset, uint256 price) external {
        _prices[asset] = price;
    }

    /// @notice Get the price of an asset in USD (8 decimals)
    /// @dev For `btcVault`, derives price from BTC price scaled by vault share-to-asset ratio.
    ///      For all other assets, returns the stored price directly.
    /// @param asset The asset address
    /// @return The price in 8 decimals
    function getAssetPrice(address asset) external view override returns (uint256) {
        if (asset == btcVault) {
            uint256 oneShare = 10 ** ERC4626(btcVault).decimals();
            uint256 pricePerShare = ERC4626(btcVault).convertToAssets(oneShare);
            uint256 btcPrice = _getAssetPrice(asset);

            return btcPrice.mulDiv(pricePerShare, (10 ** ERC20(btc).decimals()));
        }

        return _getAssetPrice(asset);
    }

    /// @notice Returns the price and last update timestamp for an asset
    /// @dev For `btcVault`, derives price from BTC and uses BTC's timestamp.
    ///      For assets without a custom timestamp, returns block.timestamp (effectively fresh).
    /// @param asset The asset address
    /// @return price The price in 8 decimals
    /// @return updatedAt The timestamp of the last price update
    function getAssetPriceWithTimestamp(address asset)
        external
        view
        override
        returns (uint256 price, uint256 updatedAt)
    {
        if (asset == btcVault) {
            uint256 oneShare = 10 ** ERC4626(btcVault).decimals();
            uint256 pricePerShare = ERC4626(btcVault).convertToAssets(oneShare);
            uint256 btcPrice = _getAssetPrice(asset);

            price = btcPrice.mulDiv(pricePerShare, (10 ** ERC20(btc).decimals()));
            // Use BTC's timestamp for bvBTC (mirrors AaveOracle behavior)
            updatedAt = _getUpdatedAt(btc);
            return (price, updatedAt);
        }

        price = _getAssetPrice(asset);
        updatedAt = _getUpdatedAt(asset);
    }

    /// @dev Returns the stored price for `asset` from the internal mapping
    /// @param asset The asset address
    /// @return The price in 8 decimals
    function _getAssetPrice(address asset) internal view returns (uint256) {
        return _prices[asset];
    }

    /// @dev Returns the stored updatedAt timestamp, defaulting to block.timestamp if not set
    function _getUpdatedAt(address asset) internal view returns (uint256) {
        uint256 ts = _lastUpdatedAt[asset];
        return ts == 0 ? block.timestamp : ts;
    }

    /// @notice Make an asset's oracle price stale by setting its update timestamp
    /// @param asset The asset address
    /// @param timestamp The timestamp to set (use a past timestamp to make stale)
    function makeStale(address asset, uint256 timestamp) external {
        _lastUpdatedAt[asset] = timestamp;
    }

    /// @notice Reset an asset to "fresh" by clearing its custom timestamp
    /// @param asset The asset address
    function makeFresh(address asset) external {
        delete _lastUpdatedAt[asset];
    }

    /// @notice Drop an asset's price by a percentage
    /// @param asset The asset address
    /// @param dropPercent Percentage to drop (e.g., 50 = 50% drop)
    /// @return newPrice The new price after drop
    function dropPrice(address asset, uint256 dropPercent) external returns (uint256 newPrice) {
        require(dropPercent <= 100, "Drop too high");
        uint256 currentPrice = _prices[asset];
        newPrice = (currentPrice * (100 - dropPercent)) / 100;
        _prices[asset] = newPrice;
    }
}
