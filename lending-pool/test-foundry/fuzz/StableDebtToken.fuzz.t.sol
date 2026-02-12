// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.13 <0.9.0;

import "forge-std/Test.sol";

interface IStableDebtTokenHarness {
    function RAY() external pure returns (uint256);
    function SECONDS_PER_YEAR() external pure returns (uint256);

    function calculateNewStableRate(
        uint256 currentRate,
        uint256 currentBalance,
        uint256 amount,
        uint256 newRate
    ) external pure returns (uint256);

    function calculateNewAvgStableRate(
        uint256 currentAvgRate,
        uint256 previousSupply,
        uint256 rate,
        uint256 amount
    ) external pure returns (uint256);

    function calculateAccruedBalance(
        uint256 principalBalance,
        uint256 stableRate,
        uint40 lastUpdateTimestamp,
        uint256 currentTimestamp
    ) external pure returns (uint256);

    function calculateTotalSupply(
        uint256 principalSupply,
        uint256 avgRate,
        uint40 lastSupplyTimestamp,
        uint256 currentTimestamp
    ) external pure returns (uint256);
}

contract StableDebtTokenFuzzTest is Test {
    IStableDebtTokenHarness h;

    uint256 constant RAY = 1e27;
    uint256 constant SECONDS_PER_YEAR = 365 days;

    function setUp() public {
        h = IStableDebtTokenHarness(deployCode("StableDebtTokenHarness.sol"));
    }

    // ============================================================
    //                   calculateNewStableRate
    // ============================================================

    function testFuzz_newStableRate_ZeroBalanceReturnsMintRate(
        uint256 amount,
        uint256 newRate
    ) public view {
        // When currentBalance == 0, the weighted average is just newRate
        amount = bound(amount, 1e18, 1e30);
        newRate = bound(newRate, 1e22, RAY);

        uint256 result = h.calculateNewStableRate(0, 0, amount, newRate);

        // Allow ±1 rounding tolerance from rayMul/rayDiv
        assertApproxEqAbs(result, newRate, 1, "zero balance should return mint rate");
    }

    function testFuzz_newStableRate_BoundedByRates(
        uint256 currentRate,
        uint256 currentBalance,
        uint256 amount,
        uint256 newRate
    ) public view {
        // Weighted average should lie between min and max rate
        currentRate = bound(currentRate, 1e22, RAY / 2);
        newRate = bound(newRate, 1e22, RAY / 2);
        currentBalance = bound(currentBalance, 1e18, 1e30);
        amount = bound(amount, 1e18, 1e30);

        uint256 result = h.calculateNewStableRate(currentRate, currentBalance, amount, newRate);

        uint256 minRate = currentRate < newRate ? currentRate : newRate;
        uint256 maxRate = currentRate > newRate ? currentRate : newRate;

        assertGe(result + 1, minRate, "weighted rate should be >= min component rate");
        assertLe(result, maxRate + 1, "weighted rate should be <= max component rate");
    }

    function testFuzz_newStableRate_MonotonicInNewRate(
        uint256 currentRate,
        uint256 currentBalance,
        uint256 amount,
        uint256 newRate1,
        uint256 newRate2
    ) public view {
        currentRate = bound(currentRate, 1e22, RAY / 2);
        currentBalance = bound(currentBalance, 1e18, 1e30);
        amount = bound(amount, 1e18, 1e30);
        newRate1 = bound(newRate1, 1e22, RAY / 2);
        newRate2 = bound(newRate2, newRate1, RAY / 2);

        uint256 result1 = h.calculateNewStableRate(currentRate, currentBalance, amount, newRate1);
        uint256 result2 = h.calculateNewStableRate(currentRate, currentBalance, amount, newRate2);

        assertLe(result1, result2 + 1, "higher new rate should give higher or equal result");
    }

    function testFuzz_newStableRate_EqualRatesReturnSame(
        uint256 rate,
        uint256 currentBalance,
        uint256 amount
    ) public view {
        // If currentRate == newRate, the weighted average should be the same rate
        rate = bound(rate, 1e22, RAY / 2);
        currentBalance = bound(currentBalance, 1e18, 1e30);
        amount = bound(amount, 1e18, 1e30);

        uint256 result = h.calculateNewStableRate(rate, currentBalance, amount, rate);

        assertApproxEqAbs(result, rate, 2, "equal rates should return approximately the same rate");
    }

    // ============================================================
    //                  calculateNewAvgStableRate
    // ============================================================

    function testFuzz_avgStableRate_ZeroPreviousSupply(
        uint256 rate,
        uint256 amount
    ) public view {
        // When previousSupply == 0, result = rate
        rate = bound(rate, 1e22, RAY);
        amount = bound(amount, 1e18, 1e30);

        uint256 result = h.calculateNewAvgStableRate(0, 0, rate, amount);

        assertApproxEqAbs(result, rate, 1, "zero previous supply should return mint rate");
    }

    function testFuzz_avgStableRate_BoundedByRates(
        uint256 currentAvgRate,
        uint256 previousSupply,
        uint256 rate,
        uint256 amount
    ) public view {
        currentAvgRate = bound(currentAvgRate, 1e22, RAY / 2);
        rate = bound(rate, 1e22, RAY / 2);
        previousSupply = bound(previousSupply, 1e18, 1e30);
        amount = bound(amount, 1e18, 1e30);

        uint256 result = h.calculateNewAvgStableRate(currentAvgRate, previousSupply, rate, amount);

        uint256 minRate = currentAvgRate < rate ? currentAvgRate : rate;
        uint256 maxRate = currentAvgRate > rate ? currentAvgRate : rate;

        assertGe(result + 1, minRate, "avg rate should be >= min rate");
        assertLe(result, maxRate + 1, "avg rate should be <= max rate");
    }

    function testFuzz_avgStableRate_MonotonicInRate(
        uint256 currentAvgRate,
        uint256 previousSupply,
        uint256 rate1,
        uint256 rate2,
        uint256 amount
    ) public view {
        currentAvgRate = bound(currentAvgRate, 1e22, RAY / 2);
        previousSupply = bound(previousSupply, 1e18, 1e30);
        amount = bound(amount, 1e18, 1e30);
        rate1 = bound(rate1, 1e22, RAY / 2);
        rate2 = bound(rate2, rate1, RAY / 2);

        uint256 result1 = h.calculateNewAvgStableRate(currentAvgRate, previousSupply, rate1, amount);
        uint256 result2 = h.calculateNewAvgStableRate(currentAvgRate, previousSupply, rate2, amount);

        assertLe(result1, result2 + 1, "higher mint rate should increase avg rate");
    }

    // ============================================================
    //                   calculateAccruedBalance
    // ============================================================

    function testFuzz_accruedBalance_ZeroPrincipalReturnsZero(
        uint256 stableRate,
        uint40 lastUpdate,
        uint256 currentTs
    ) public view {
        stableRate = bound(stableRate, 0, RAY);
        lastUpdate = uint40(bound(uint256(lastUpdate), 1, type(uint40).max / 2));
        currentTs = bound(currentTs, uint256(lastUpdate), uint256(lastUpdate) + 10 * SECONDS_PER_YEAR);

        uint256 result = h.calculateAccruedBalance(0, stableRate, lastUpdate, currentTs);

        assertEq(result, 0, "zero principal should return zero accrued balance");
    }

    function testFuzz_accruedBalance_ZeroTimeDeltaReturnsPrincipal(
        uint256 principal,
        uint256 stableRate,
        uint40 timestamp
    ) public view {
        principal = bound(principal, 1, 1e30);
        stableRate = bound(stableRate, 0, RAY);
        timestamp = uint40(bound(uint256(timestamp), 1, type(uint40).max / 2));

        uint256 result = h.calculateAccruedBalance(principal, stableRate, timestamp, uint256(timestamp));

        // compoundedInterest at timeDelta=0 returns RAY, so result = principal
        assertEq(result, principal, "zero time delta should return principal");
    }

    function testFuzz_accruedBalance_MonotonicInTime(
        uint256 principal,
        uint256 stableRate,
        uint40 lastUpdate,
        uint256 time1,
        uint256 time2
    ) public view {
        principal = bound(principal, 1e18, 1e30);
        stableRate = bound(stableRate, 1e22, RAY / 2);
        lastUpdate = uint40(bound(uint256(lastUpdate), 1, 1e9));
        time1 = bound(time1, uint256(lastUpdate), uint256(lastUpdate) + 5 * SECONDS_PER_YEAR);
        time2 = bound(time2, time1, uint256(lastUpdate) + 10 * SECONDS_PER_YEAR);

        uint256 bal1 = h.calculateAccruedBalance(principal, stableRate, lastUpdate, time1);
        uint256 bal2 = h.calculateAccruedBalance(principal, stableRate, lastUpdate, time2);

        assertLe(bal1, bal2, "longer time should give larger or equal accrued balance");
    }

    function testFuzz_accruedBalance_MonotonicInRate(
        uint256 principal,
        uint256 rate1,
        uint256 rate2,
        uint40 lastUpdate,
        uint256 currentTs
    ) public view {
        principal = bound(principal, 1e18, 1e30);
        rate1 = bound(rate1, 0, RAY / 2);
        rate2 = bound(rate2, rate1, RAY / 2);
        lastUpdate = uint40(bound(uint256(lastUpdate), 1, 1e9));
        currentTs = bound(currentTs, uint256(lastUpdate) + 1 days, uint256(lastUpdate) + 5 * SECONDS_PER_YEAR);

        uint256 bal1 = h.calculateAccruedBalance(principal, rate1, lastUpdate, currentTs);
        uint256 bal2 = h.calculateAccruedBalance(principal, rate2, lastUpdate, currentTs);

        assertLe(bal1, bal2, "higher rate should give larger or equal accrued balance");
    }

    function testFuzz_accruedBalance_AlwaysGtePrincipal(
        uint256 principal,
        uint256 stableRate,
        uint40 lastUpdate,
        uint256 currentTs
    ) public view {
        principal = bound(principal, 1, 1e30);
        stableRate = bound(stableRate, 0, RAY);
        lastUpdate = uint40(bound(uint256(lastUpdate), 1, 1e9));
        currentTs = bound(currentTs, uint256(lastUpdate), uint256(lastUpdate) + 10 * SECONDS_PER_YEAR);

        uint256 result = h.calculateAccruedBalance(principal, stableRate, lastUpdate, currentTs);

        assertGe(result, principal, "accrued balance should always be >= principal");
    }

    // ============================================================
    //                   calculateTotalSupply
    // ============================================================

    function testFuzz_totalSupply_ZeroPrincipalReturnsZero(
        uint256 avgRate,
        uint40 lastTs,
        uint256 currentTs
    ) public view {
        avgRate = bound(avgRate, 0, RAY);
        lastTs = uint40(bound(uint256(lastTs), 1, type(uint40).max / 2));
        currentTs = bound(currentTs, uint256(lastTs), uint256(lastTs) + 10 * SECONDS_PER_YEAR);

        uint256 result = h.calculateTotalSupply(0, avgRate, lastTs, currentTs);

        assertEq(result, 0, "zero principal supply should return zero");
    }

    function testFuzz_totalSupply_ZeroTimeDeltaReturnsPrincipal(
        uint256 principalSupply,
        uint256 avgRate,
        uint40 timestamp
    ) public view {
        principalSupply = bound(principalSupply, 1, 1e30);
        avgRate = bound(avgRate, 0, RAY);
        timestamp = uint40(bound(uint256(timestamp), 1, type(uint40).max / 2));

        uint256 result = h.calculateTotalSupply(principalSupply, avgRate, timestamp, uint256(timestamp));

        assertEq(result, principalSupply, "zero time delta should return principal supply");
    }

    function testFuzz_totalSupply_MonotonicInTime(
        uint256 principalSupply,
        uint256 avgRate,
        uint40 lastTs,
        uint256 time1,
        uint256 time2
    ) public view {
        principalSupply = bound(principalSupply, 1e18, 1e30);
        avgRate = bound(avgRate, 1e22, RAY / 2);
        lastTs = uint40(bound(uint256(lastTs), 1, 1e9));
        time1 = bound(time1, uint256(lastTs), uint256(lastTs) + 5 * SECONDS_PER_YEAR);
        time2 = bound(time2, time1, uint256(lastTs) + 10 * SECONDS_PER_YEAR);

        uint256 supply1 = h.calculateTotalSupply(principalSupply, avgRate, lastTs, time1);
        uint256 supply2 = h.calculateTotalSupply(principalSupply, avgRate, lastTs, time2);

        assertLe(supply1, supply2, "longer time should give larger or equal total supply");
    }

    function testFuzz_totalSupply_MonotonicInRate(
        uint256 principalSupply,
        uint256 rate1,
        uint256 rate2,
        uint40 lastTs,
        uint256 currentTs
    ) public view {
        principalSupply = bound(principalSupply, 1e18, 1e30);
        rate1 = bound(rate1, 0, RAY / 2);
        rate2 = bound(rate2, rate1, RAY / 2);
        lastTs = uint40(bound(uint256(lastTs), 1, 1e9));
        currentTs = bound(currentTs, uint256(lastTs) + 1 days, uint256(lastTs) + 5 * SECONDS_PER_YEAR);

        uint256 supply1 = h.calculateTotalSupply(principalSupply, rate1, lastTs, currentTs);
        uint256 supply2 = h.calculateTotalSupply(principalSupply, rate2, lastTs, currentTs);

        assertLe(supply1, supply2, "higher rate should give larger or equal total supply");
    }

    function testFuzz_totalSupply_AlwaysGtePrincipal(
        uint256 principalSupply,
        uint256 avgRate,
        uint40 lastTs,
        uint256 currentTs
    ) public view {
        principalSupply = bound(principalSupply, 1, 1e30);
        avgRate = bound(avgRate, 0, RAY);
        lastTs = uint40(bound(uint256(lastTs), 1, 1e9));
        currentTs = bound(currentTs, uint256(lastTs), uint256(lastTs) + 10 * SECONDS_PER_YEAR);

        uint256 result = h.calculateTotalSupply(principalSupply, avgRate, lastTs, currentTs);

        assertGe(result, principalSupply, "total supply should always be >= principal supply");
    }
}
