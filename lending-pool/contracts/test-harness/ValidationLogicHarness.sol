// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {ValidationLogic} from "../protocol/libraries/logic/ValidationLogic.sol";
import {DataTypes} from "../protocol/libraries/types/DataTypes.sol";
import {ReserveConfiguration} from "../protocol/libraries/configuration/ReserveConfiguration.sol";
import {UserConfiguration} from "../protocol/libraries/configuration/UserConfiguration.sol";

contract ValidationLogicHarness {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    DataTypes.ReserveData internal _collateralReserve;
    DataTypes.ReserveData internal _principalReserve;
    DataTypes.UserConfigurationMap internal _userConfig;

    // ─── Setup: Collateral Reserve ───────────────────────────────

    function setCollateralReserveActive(bool active) external {
        DataTypes.ReserveConfigurationMap memory cfg = _collateralReserve.configuration;
        cfg.setActive(active);
        _collateralReserve.configuration = cfg;
    }

    function setCollateralLiquidationThreshold(uint256 threshold) external {
        DataTypes.ReserveConfigurationMap memory cfg = _collateralReserve.configuration;
        cfg.setLiquidationThreshold(threshold);
        _collateralReserve.configuration = cfg;
    }

    function setCollateralReserveId(uint8 id) external {
        _collateralReserve.id = id;
    }

    // ─── Setup: Principal Reserve ────────────────────────────────

    function setPrincipalReserveActive(bool active) external {
        DataTypes.ReserveConfigurationMap memory cfg = _principalReserve.configuration;
        cfg.setActive(active);
        _principalReserve.configuration = cfg;
    }

    // ─── Setup: User Config ──────────────────────────────────────

    function setUserUsingAsCollateral(uint256 reserveIndex, bool usingAsCollateral) external {
        _userConfig.setUsingAsCollateral(reserveIndex, usingAsCollateral);
    }

    // ─── Validation functions under test ─────────────────────────

    function validateLiquidationCall(
        uint256 typeOfLiquidation,
        uint256 userHealthFactor,
        uint256 userStableDebt,
        uint256 userVariableDebt
    ) external view returns (uint256, string memory) {
        return ValidationLogic.validateLiquidationCall(
            _collateralReserve,
            _principalReserve,
            _userConfig,
            typeOfLiquidation,
            userHealthFactor,
            userStableDebt,
            userVariableDebt
        );
    }

    function validateMicroLiquidationCall(
        uint256 typeOfLiquidation,
        uint256 userStableDebt,
        uint256 userVariableDebt
    ) external view returns (uint256, string memory) {
        return ValidationLogic.validateMicroLiquidationCall(
            _collateralReserve,
            _principalReserve,
            _userConfig,
            typeOfLiquidation,
            userStableDebt,
            userVariableDebt
        );
    }
}
