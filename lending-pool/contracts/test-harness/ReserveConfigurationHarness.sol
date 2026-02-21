// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {DataTypes} from "../protocol/libraries/types/DataTypes.sol";
import {ReserveConfiguration} from "../protocol/libraries/configuration/ReserveConfiguration.sol";

contract ReserveConfigurationHarness {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    DataTypes.ReserveConfigurationMap internal _config;

    // ─── Constants ──────────────────────────────────────────────
    function MAX_VALID_LTV() external pure returns (uint256) {
        return ReserveConfiguration.MAX_VALID_LTV;
    }

    function MAX_VALID_LIQUIDATION_THRESHOLD() external pure returns (uint256) {
        return ReserveConfiguration.MAX_VALID_LIQUIDATION_THRESHOLD;
    }

    function MAX_VALID_LIQUIDATION_BONUS() external pure returns (uint256) {
        return ReserveConfiguration.MAX_VALID_LIQUIDATION_BONUS;
    }

    function MAX_VALID_DECIMALS() external pure returns (uint256) {
        return ReserveConfiguration.MAX_VALID_DECIMALS;
    }

    function MAX_VALID_RESERVE_FACTOR() external pure returns (uint256) {
        return ReserveConfiguration.MAX_VALID_RESERVE_FACTOR;
    }

    // ─── Raw data access ────────────────────────────────────────
    function setData(uint256 data) external {
        _config.data = data;
    }

    function getData() external view returns (uint256) {
        return _config.data;
    }

    // ─── Setters (memory → storage) ─────────────────────────────
    function setLtv(uint256 ltv) external {
        DataTypes.ReserveConfigurationMap memory cfg = _config;
        cfg.setLtv(ltv);
        _config = cfg;
    }

    function setLiquidationThreshold(uint256 threshold) external {
        DataTypes.ReserveConfigurationMap memory cfg = _config;
        cfg.setLiquidationThreshold(threshold);
        _config = cfg;
    }

    function setLiquidationBonus(uint256 bonus) external {
        DataTypes.ReserveConfigurationMap memory cfg = _config;
        cfg.setLiquidationBonus(bonus);
        _config = cfg;
    }

    function setDecimals(uint256 decimals) external {
        DataTypes.ReserveConfigurationMap memory cfg = _config;
        cfg.setDecimals(decimals);
        _config = cfg;
    }

    function setActive(bool active) external {
        DataTypes.ReserveConfigurationMap memory cfg = _config;
        cfg.setActive(active);
        _config = cfg;
    }

    function setFrozen(bool frozen) external {
        DataTypes.ReserveConfigurationMap memory cfg = _config;
        cfg.setFrozen(frozen);
        _config = cfg;
    }

    function setBorrowingEnabled(bool enabled) external {
        DataTypes.ReserveConfigurationMap memory cfg = _config;
        cfg.setBorrowingEnabled(enabled);
        _config = cfg;
    }

    function setStableRateBorrowingEnabled(bool enabled) external {
        DataTypes.ReserveConfigurationMap memory cfg = _config;
        cfg.setStableRateBorrowingEnabled(enabled);
        _config = cfg;
    }

    function setReserveFactor(uint256 reserveFactor) external {
        DataTypes.ReserveConfigurationMap memory cfg = _config;
        cfg.setReserveFactor(reserveFactor);
        _config = cfg;
    }

    // ─── Storage getters ────────────────────────────────────────
    function getLtv() external view returns (uint256) {
        return _config.getLtv();
    }

    function getLiquidationThreshold() external view returns (uint256) {
        return _config.getLiquidationThreshold();
    }

    function getLiquidationBonus() external view returns (uint256) {
        return _config.getLiquidationBonus();
    }

    function getDecimals() external view returns (uint256) {
        return _config.getDecimals();
    }

    function getActive() external view returns (bool) {
        return _config.getActive();
    }

    function getReserveFactor() external view returns (uint256) {
        return _config.getReserveFactor();
    }

    // ─── Batch getters (storage) ────────────────────────────────
    function getFlags() external view returns (bool, bool, bool, bool) {
        return _config.getFlags();
    }

    function getParams()
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256)
    {
        return _config.getParams();
    }

    // ─── Batch getters (memory / pure) ──────────────────────────
    function getParamsMemory()
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256)
    {
        DataTypes.ReserveConfigurationMap memory cfg = _config;
        return cfg.getParamsMemory();
    }

    function getFlagsMemory() external view returns (bool, bool, bool, bool) {
        DataTypes.ReserveConfigurationMap memory cfg = _config;
        return cfg.getFlagsMemory();
    }
}
