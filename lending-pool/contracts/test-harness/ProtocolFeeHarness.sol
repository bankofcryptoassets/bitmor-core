// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {SafeMath} from "../dependencies/openzeppelin/contracts/SafeMath.sol";
import {PercentageMath} from "../protocol/libraries/math/PercentageMath.sol";

/// @dev Standalone harness replicating LendingPoolCollateralManager._calculateProtocolFee
contract ProtocolFeeHarness {
    using SafeMath for uint256;
    using PercentageMath for uint256;

    function calculateProtocolFee(
        uint256 maxCollateralToLiquidate,
        uint256 liquidationBonusPercent,
        uint256 liquidationFee
    ) external pure returns (uint256 protocolFee, uint256 liquidatorCollateral) {
        if (liquidationFee == 0) return (0, maxCollateralToLiquidate);

        uint256 baseCollateral = maxCollateralToLiquidate.percentDiv(liquidationBonusPercent);
        uint256 bonusCollateral = maxCollateralToLiquidate.sub(baseCollateral);
        protocolFee = bonusCollateral.percentMul(liquidationFee);
        liquidatorCollateral = maxCollateralToLiquidate.sub(protocolFee);
    }
}
