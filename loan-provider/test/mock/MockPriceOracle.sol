// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@solady/tokens/ERC20.sol";
import {IPriceOracleGetter} from "@bitmor/interfaces/IPriceOracleGetter.sol";
import {ERC4626} from "@solady/tokens/ERC4626.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

/// @title MockPriceOracle
/// @notice Mock price oracle for unit testing
/// @dev Allows setting and getting asset prices with test helpers
/// //! TODO: this needs to be changed to provide the similar setup as AaveOracle in lendingpool.
contract MockPriceOracle is IPriceOracleGetter {
    using FixedPointMathLib for uint256;

    mapping(address => uint256) private _prices;

    address public btcVault;
    address public btc;

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

    /// @notice Get the price of an asset
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

    /// @notice Get the price of an asset
    /// @param asset The asset address
    /// @return The price in 8 decimals
    function _getAssetPrice(address asset) internal view returns (uint256) {
        return _prices[asset];
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
