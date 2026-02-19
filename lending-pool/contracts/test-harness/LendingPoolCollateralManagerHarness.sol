// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {LendingPoolCollateralManager} from "../protocol/lendingpool/LendingPoolCollateralManager.sol";
import {ILendingPoolAddressesProvider} from "../interfaces/ILendingPoolAddressesProvider.sol";
import {DataTypes} from "../protocol/libraries/types/DataTypes.sol";
import {ReserveConfiguration} from "../protocol/libraries/configuration/ReserveConfiguration.sol";

/// @dev Mock price oracle for LPCM harness tests
contract MockPriceOracleForLPCM {
    mapping(address => uint256) internal _prices;

    function setAssetPrice(address asset, uint256 price) external {
        _prices[asset] = price;
    }

    function getAssetPrice(address asset) external view returns (uint256) {
        return _prices[asset];
    }
}

/// @dev Mock addresses provider — only implements getPriceOracle() for the harness
contract MockAddressesProviderForLPCM {
    address internal _oracle;

    function setOracle(address oracle_) external {
        _oracle = oracle_;
    }

    function getPriceOracle() external view returns (address) {
        return _oracle;
    }
}

/// @dev Harness that inherits from the real LendingPoolCollateralManager
/// and exposes _calculateAvailableCollateralToLiquidate for fuzz testing.
contract LendingPoolCollateralManagerHarness is LendingPoolCollateralManager {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    /// @dev Configure harness storage: addresses provider and reserve configurations.
    function setupState(
        address addressesProvider,
        address collateralAsset,
        address debtAsset,
        uint256 collateralDecimals,
        uint256 debtAssetDecimals,
        uint256 liquidationBonus
    ) external {
        _addressesProvider = ILendingPoolAddressesProvider(addressesProvider);

        DataTypes.ReserveConfigurationMap memory collateralConfig;
        collateralConfig.setLiquidationBonus(liquidationBonus);
        collateralConfig.setDecimals(collateralDecimals);
        _reserves[collateralAsset].configuration = collateralConfig;

        DataTypes.ReserveConfigurationMap memory debtConfig;
        debtConfig.setDecimals(debtAssetDecimals);
        _reserves[debtAsset].configuration = debtConfig;
    }

    /// @dev Expose _calculateAvailableCollateralToLiquidate for external testing.
    function exposed_calculateAvailableCollateralToLiquidate(
        address collateralAsset,
        address debtAsset,
        uint256 debtToCover,
        uint256 userCollateralBalance
    ) external view returns (uint256, uint256, uint256) {
        return _calculateAvailableCollateralToLiquidate(
            _reserves[collateralAsset],
            _reserves[debtAsset],
            collateralAsset,
            debtAsset,
            debtToCover,
            userCollateralBalance
        );
    }

    /// @dev Expose _calculateProtocolFee for external testing.
    function exposed_calculateProtocolFee(
        uint256 maxCollateralToLiquidate,
        uint256 liquidationBonusPercent,
        uint256 liquidationFee
    ) external pure returns (uint256 protocolFee, uint256 liquidatorCollateral) {
        return _calculateProtocolFee(maxCollateralToLiquidate, liquidationBonusPercent, liquidationFee);
    }
}
