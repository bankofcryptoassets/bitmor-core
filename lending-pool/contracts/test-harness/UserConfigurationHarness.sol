// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {DataTypes} from "../protocol/libraries/types/DataTypes.sol";
import {UserConfiguration} from "../protocol/libraries/configuration/UserConfiguration.sol";

contract UserConfigurationHarness {
    using UserConfiguration for DataTypes.UserConfigurationMap;

    DataTypes.UserConfigurationMap internal _config;

    // ─── Constants ──────────────────────────────────────────────
    function BORROWING_MASK() external pure returns (uint256) {
        return UserConfiguration.BORROWING_MASK;
    }

    // ─── Raw data access ────────────────────────────────────────
    function setData(uint256 data) external {
        _config.data = data;
    }

    function getData() external view returns (uint256) {
        return _config.data;
    }

    // ─── Storage setters ────────────────────────────────────────
    function setBorrowing(uint256 reserveIndex, bool borrowing) external {
        _config.setBorrowing(reserveIndex, borrowing);
    }

    function setUsingAsCollateral(uint256 reserveIndex, bool usingAsCollateral) external {
        _config.setUsingAsCollateral(reserveIndex, usingAsCollateral);
    }

    // ─── Memory getters ─────────────────────────────────────────
    function isUsingAsCollateralOrBorrowing(uint256 reserveIndex) external view returns (bool) {
        DataTypes.UserConfigurationMap memory cfg = _config;
        return cfg.isUsingAsCollateralOrBorrowing(reserveIndex);
    }

    function isBorrowing(uint256 reserveIndex) external view returns (bool) {
        DataTypes.UserConfigurationMap memory cfg = _config;
        return cfg.isBorrowing(reserveIndex);
    }

    function isUsingAsCollateral(uint256 reserveIndex) external view returns (bool) {
        DataTypes.UserConfigurationMap memory cfg = _config;
        return cfg.isUsingAsCollateral(reserveIndex);
    }

    function isBorrowingAny() external view returns (bool) {
        DataTypes.UserConfigurationMap memory cfg = _config;
        return cfg.isBorrowingAny();
    }

    function isEmpty() external view returns (bool) {
        DataTypes.UserConfigurationMap memory cfg = _config;
        return cfg.isEmpty();
    }
}
