// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {DataTypes} from "../protocol/libraries/types/DataTypes.sol";
import {ReserveLogic} from "../protocol/libraries/logic/ReserveLogic.sol";

contract ReserveLogicHarness {
    using ReserveLogic for DataTypes.ReserveData;

    DataTypes.ReserveData internal _reserve;

    // ─── Storage setters ────────────────────────────────────────
    function setLiquidityIndex(uint128 index) external {
        _reserve.liquidityIndex = index;
    }

    function setVariableBorrowIndex(uint128 index) external {
        _reserve.variableBorrowIndex = index;
    }

    function setCurrentLiquidityRate(uint128 rate) external {
        _reserve.currentLiquidityRate = rate;
    }

    function setCurrentVariableBorrowRate(uint128 rate) external {
        _reserve.currentVariableBorrowRate = rate;
    }

    function setLastUpdateTimestamp(uint40 ts) external {
        _reserve.lastUpdateTimestamp = ts;
    }

    // ─── Storage readers ────────────────────────────────────────
    function getLiquidityIndex() external view returns (uint128) {
        return _reserve.liquidityIndex;
    }

    function getVariableBorrowIndex() external view returns (uint128) {
        return _reserve.variableBorrowIndex;
    }

    function getLastUpdateTimestamp() external view returns (uint40) {
        return _reserve.lastUpdateTimestamp;
    }

    // ─── Library functions under test ───────────────────────────
    function getNormalizedIncome() external view returns (uint256) {
        return _reserve.getNormalizedIncome();
    }

    function getNormalizedDebt() external view returns (uint256) {
        return _reserve.getNormalizedDebt();
    }
}
