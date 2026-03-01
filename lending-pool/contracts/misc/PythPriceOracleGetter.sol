// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import { Ownable } from "../dependencies/openzeppelin/contracts/Ownable.sol";
import { IERC20Detailed } from "../dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import { SafeMath } from "../dependencies/openzeppelin/contracts/SafeMath.sol";

import { IPyth, PythStructs } from "../dependencies/pythNetwork/IPyth.sol";
import { IPriceOracleGetter } from "../interfaces/IPriceOracleGetter.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";

/**
 * @title PythPriceOracleGetter
 * @author Bitmor Protocol
 * @notice Fallback oracle for AaveOracle
 */
contract PythPriceOracleGetter is IPriceOracleGetter, Ownable {
    using SafeMath for uint256;

    event PythPriceOracleGetter__AssetSourceUpdated(address indexed asset, bytes32 indexed source);

    mapping(address => bytes32) private assetsSources;

    address public immutable PYTH;
    address public immutable BASE_CURRENCY;
    uint256 public immutable BASE_CURRENCY_UNIT;
    address public s_btc;
    address public s_bvBTC;

    uint256 public constant MAX_STALENESS = 3600;
    uint256 public constant PRICE_PRECISION = 10 ** 8;

    /// @notice Constructor
    /// @dev No fallback oracle -- this is the terminal oracle.
    /// @param pyth Pyth contract address
    /// @param assets The addresses of the assets
    /// @param sources The address of the source of each asset
    /// @param btc The address of the BTC token used for price derivation
    /// @param bvBTC The address of the bvBTC vault used for share-to-asset conversion
    /// @param baseCurrency the base currency used for the price quotes. If USD is used, base currency is 0x0
    /// @param baseCurrencyUnit the unit of the base currency
    constructor(
        address pyth,
        address[] memory assets,
        bytes32[] memory sources,
        address btc,
        address bvBTC,
        address baseCurrency,
        uint256 baseCurrencyUnit
    ) public {
        _setAssetsSources(assets, sources);
        _setBTC(btc);
        _setbvBTC(bvBTC);
        BASE_CURRENCY = baseCurrency;
        BASE_CURRENCY_UNIT = baseCurrencyUnit;
        PYTH = pyth;

        emit PriceOracleGetter__BaseCurrencySet(baseCurrency, baseCurrencyUnit);
    }

    /// @notice This is a fallback oracle.
    function setFallbackOracle(address fallbackOracle) external override onlyOwner {
        revert("PythPriceOracleGetter__FallbackOracleNotSupported");
    }

    /**
     * @notice External function called by the owner to set or replace sources of assets
     * @param assets The addresses of the assets
     * @param sources The Pyth price feed ID of each asset
     */
    function setAssetSources(
        address[] calldata assets,
        bytes32[] calldata sources
    ) external onlyOwner {
        _setAssetsSources(assets, sources);
    }

    /// @inheritdoc IPriceOracleGetter
    function setBTC(address _btc) external override onlyOwner {
        _setBTC(_btc);
    }

    /// @inheritdoc IPriceOracleGetter
    function setbvBTC(address _bvBTC) external override onlyOwner {
        _setbvBTC(_bvBTC);
    }

    /// @notice This is a fallback oracle.
    function getFallbackOracle() external view override returns (address) {
        return address(0);
    }

    /// @inheritdoc IPriceOracleGetter
    function getAssetPrice(address asset) public view override returns (uint256) {
        if (asset == s_bvBTC) {
            uint256 btcPrice = _getAssetPrice(s_btc);
            uint256 oneShare = 10 ** uint256(IERC20Detailed(s_bvBTC).decimals());
            uint256 assetPerShare = IERC4626(s_bvBTC).previewRedeem(oneShare);

            return btcPrice.mul(assetPerShare).div(10 ** uint256(IERC20Detailed(s_btc).decimals()));
        }
        return _getAssetPrice(asset);
    }

    /// @inheritdoc IPriceOracleGetter
    function getAssetsPrices(
        address[] calldata assets
    ) external view override returns (uint256[] memory) {
        uint256[] memory prices = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            prices[i] = getAssetPrice(assets[i]);
        }
        return prices;
    }

    /**
     * @notice Gets the Pyth price feed ID for an asset address
     * @param asset The address of the asset
     * @return The Pyth price feed ID
     */
    function getSourceOfAsset(address asset) external view returns (bytes32) {
        return assetsSources[asset];
    }

    function _getAssetPrice(address asset) internal view returns (uint256) {
        bytes32 source = assetsSources[asset];

        require(source != bytes32(0), "FallbackOracle__NoSource");

        PythStructs.Price memory price = IPyth(PYTH).getPriceNoOlderThan(source, MAX_STALENESS);

        require(price.price > 0, "PythPriceOracleGetter__PriceNotFound");

        uint256 priceValue = (uint256(uint64(price.price)) * PRICE_PRECISION) /
            (10 ** uint256(uint32(-1 * price.expo)));

        if (priceValue > 0) {
            return priceValue;
        } else {
            revert("PythPriceOracleGetter__PriceNotFound");
        }
    }

    function _setBTC(address _btc) internal {
        s_btc = _btc;
        emit PriceOracleGetter__BTCAddressUpdated(_btc);
    }

    function _setbvBTC(address _bvBTC) internal {
        s_bvBTC = _bvBTC;
        emit PriceOracleGetter__BVBTCAddressUpdated(_bvBTC);
    }

    /**
     * @notice Internal function to set the sources for each asset
     * @param assets The addresses of the assets
     * @param sources The address of the source of each asset
     */
    function _setAssetsSources(address[] memory assets, bytes32[] memory sources) internal {
        require(assets.length == sources.length, "INCONSISTENT_PARAMS_LENGTH");
        for (uint256 i = 0; i < assets.length; i++) {
            assetsSources[assets[i]] = sources[i];
            emit PythPriceOracleGetter__AssetSourceUpdated(assets[i], sources[i]);
        }
    }
}
