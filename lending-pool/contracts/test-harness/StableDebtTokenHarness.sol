// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {WadRayMath} from "../protocol/libraries/math/WadRayMath.sol";
import {MathUtils} from "../protocol/libraries/math/MathUtils.sol";
import {SafeMath} from "../dependencies/openzeppelin/contracts/SafeMath.sol";

/// @dev Harness that exposes the pure math used in StableDebtToken.
/// Tests the weighted average stable rate calculation, balance accrual, and total supply accrual.
contract StableDebtTokenHarness {
    using WadRayMath for uint256;
    using SafeMath for uint256;

    /// @dev Mirrors the newStableRate calculation from StableDebtToken.mint():
    /// newStableRate = (currentRate * currentBalance + amount * newRate) / (currentBalance + amount)
    /// All in ray precision.
    function calculateNewStableRate(
        uint256 currentRate,
        uint256 currentBalance,
        uint256 amount,
        uint256 newRate
    ) external pure returns (uint256) {
        return currentRate
            .rayMul(currentBalance.wadToRay())
            .add(amount.wadToRay().rayMul(newRate))
            .rayDiv(currentBalance.add(amount).wadToRay());
    }

    /// @dev Mirrors the average stable rate update from StableDebtToken.mint():
    /// newAvg = (currentAvg * previousSupply + rate * amount) / nextSupply
    function calculateNewAvgStableRate(
        uint256 currentAvgRate,
        uint256 previousSupply,
        uint256 rate,
        uint256 amount
    ) external pure returns (uint256) {
        uint256 nextSupply = previousSupply.add(amount);
        return currentAvgRate
            .rayMul(previousSupply.wadToRay())
            .add(rate.rayMul(amount.wadToRay()))
            .rayDiv(nextSupply.wadToRay());
    }

    /// @dev Mirrors StableDebtToken.balanceOf():
    /// balance = principalBalance * compoundedInterest(rate, timeDelta)
    function calculateAccruedBalance(
        uint256 principalBalance,
        uint256 stableRate,
        uint40 lastUpdateTimestamp,
        uint256 currentTimestamp
    ) external pure returns (uint256) {
        if (principalBalance == 0) return 0;
        uint256 cumulatedInterest = MathUtils.calculateCompoundedInterest(
            stableRate, lastUpdateTimestamp, currentTimestamp
        );
        return principalBalance.rayMul(cumulatedInterest);
    }

    /// @dev Mirrors StableDebtToken._calcTotalSupply():
    /// totalSupply = principalSupply * compoundedInterest(avgRate, lastTimestamp)
    function calculateTotalSupply(
        uint256 principalSupply,
        uint256 avgRate,
        uint40 lastSupplyTimestamp,
        uint256 currentTimestamp
    ) external pure returns (uint256) {
        if (principalSupply == 0) return 0;
        uint256 cumulatedInterest = MathUtils.calculateCompoundedInterest(
            avgRate, lastSupplyTimestamp, currentTimestamp
        );
        return principalSupply.rayMul(cumulatedInterest);
    }

    function RAY() external pure returns (uint256) {
        return WadRayMath.ray();
    }

    function SECONDS_PER_YEAR() external pure returns (uint256) {
        return 365 days;
    }
}
