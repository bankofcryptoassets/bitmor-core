// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {GenericLogic} from "../protocol/libraries/logic/GenericLogic.sol";

contract GenericLogicHarness {
    function HEALTH_FACTOR_LIQUIDATION_THRESHOLD() external pure returns (uint256) {
        return GenericLogic.HEALTH_FACTOR_LIQUIDATION_THRESHOLD;
    }

    function calculateHealthFactorFromBalances(
        uint256 totalCollateralInETH,
        uint256 totalDebtInETH,
        uint256 liquidationThreshold
    ) external pure returns (uint256) {
        return
            GenericLogic.calculateHealthFactorFromBalances(
                totalCollateralInETH,
                totalDebtInETH,
                liquidationThreshold
            );
    }

    function calculateAvailableBorrowsETH(
        uint256 totalCollateralInETH,
        uint256 totalDebtInETH,
        uint256 ltv
    ) external pure returns (uint256) {
        return
            GenericLogic.calculateAvailableBorrowsETH(
                totalCollateralInETH,
                totalDebtInETH,
                ltv
            );
    }
}
