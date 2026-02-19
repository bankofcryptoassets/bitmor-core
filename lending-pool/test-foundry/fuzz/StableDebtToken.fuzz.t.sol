// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.13 <0.9.0;

import "forge-std/Test.sol";

interface IStableDebtTokenHarness {
    function initialize(
        address pool,
        address underlyingAsset,
        address incentivesController,
        uint8 debtTokenDecimals,
        string memory debtTokenName,
        string memory debtTokenSymbol,
        bytes calldata params
    ) external;

    function mint(
        address user,
        address onBehalfOf,
        uint256 amount,
        uint256 rate
    ) external returns (bool);

    function balanceOf(address user) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function getUserStableRate(address user) external view returns (uint256);
    function getAverageStableRate() external view returns (uint256);
    function principalBalanceOf(address user) external view returns (uint256);
}

contract StableDebtTokenFuzzTest is Test {
    IStableDebtTokenHarness stableDebt;
    address mockPool;

    uint256 constant RAY = 1e27;
    uint256 constant SECONDS_PER_YEAR = 365 days;
    uint256 constant START_TIME = 1_000_000;

    function setUp() public {
        mockPool = deployCode("StableDebtTokenHarness.sol:MockPoolForStableDebt");
        stableDebt = IStableDebtTokenHarness(
            deployCode("StableDebtTokenHarness.sol:StableDebtTokenHarness")
        );

        vm.warp(START_TIME);

        stableDebt.initialize(
            mockPool,
            address(0xbeef),    // underlyingAsset
            address(0),         // incentivesController
            18,                 // decimals
            "Test Stable Debt",
            "sTEST",
            ""
        );
    }

    /// @dev Helper: mint for user via pool prank
    function _mint(address user, uint256 amount, uint256 rate) internal {
        vm.prank(mockPool);
        stableDebt.mint(user, user, amount, rate);
    }

    // ============================================================
    //           User Stable Rate (via mint + getUserStableRate)
    // ============================================================

    function testFuzz_newStableRate_ZeroBalanceReturnsMintRate(
        uint256 amount,
        uint256 newRate
    ) public {
        // When currentBalance == 0, the weighted average is just newRate
        amount = bound(amount, 1e18, 1e30);
        newRate = bound(newRate, 1e22, RAY);

        address user = makeAddr("user_zero_bal");
        _mint(user, amount, newRate);

        uint256 result = stableDebt.getUserStableRate(user);

        // Allow ±1 rounding tolerance from rayMul/rayDiv
        assertApproxEqAbs(result, newRate, 1, "zero balance should return mint rate");
    }

    function testFuzz_newStableRate_BoundedByRates(
        uint256 currentRate,
        uint256 currentBalance,
        uint256 amount,
        uint256 newRate
    ) public {
        // Weighted average should lie between min and max rate
        currentRate = bound(currentRate, 1e22, RAY / 2);
        newRate = bound(newRate, 1e22, RAY / 2);
        currentBalance = bound(currentBalance, 1e18, 1e30);
        amount = bound(amount, 1e18, 1e30);

        address user = makeAddr("user_bounded");
        _mint(user, currentBalance, currentRate);
        _mint(user, amount, newRate);

        uint256 result = stableDebt.getUserStableRate(user);

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
    ) public {
        currentRate = bound(currentRate, 1e22, RAY / 2);
        currentBalance = bound(currentBalance, 1e18, 1e30);
        amount = bound(amount, 1e18, 1e30);
        newRate1 = bound(newRate1, 1e22, RAY / 2);
        newRate2 = bound(newRate2, newRate1, RAY / 2);

        address user = makeAddr("user_mono");
        _mint(user, currentBalance, currentRate);

        uint256 snap = vm.snapshot();

        // Scenario 1: second mint at newRate1
        _mint(user, amount, newRate1);
        uint256 result1 = stableDebt.getUserStableRate(user);

        vm.revertTo(snap);

        // Scenario 2: second mint at newRate2 (>= newRate1)
        _mint(user, amount, newRate2);
        uint256 result2 = stableDebt.getUserStableRate(user);

        assertLe(result1, result2 + 1, "higher new rate should give higher or equal result");
    }

    function testFuzz_newStableRate_EqualRatesReturnSame(
        uint256 rate,
        uint256 currentBalance,
        uint256 amount
    ) public {
        // If currentRate == newRate, the weighted average should be the same rate
        rate = bound(rate, 1e22, RAY / 2);
        currentBalance = bound(currentBalance, 1e18, 1e30);
        amount = bound(amount, 1e18, 1e30);

        address user = makeAddr("user_equal");
        _mint(user, currentBalance, rate);
        _mint(user, amount, rate);

        uint256 result = stableDebt.getUserStableRate(user);

        assertApproxEqAbs(result, rate, 2, "equal rates should return approximately the same rate");
    }

    // ============================================================
    //        Average Stable Rate (via mint + getAverageStableRate)
    // ============================================================

    function testFuzz_avgStableRate_ZeroPreviousSupply(
        uint256 rate,
        uint256 amount
    ) public {
        // When previousSupply == 0, result = rate
        rate = bound(rate, 1e22, RAY);
        amount = bound(amount, 1e18, 1e30);

        address user = makeAddr("user_avg_zero");
        _mint(user, amount, rate);

        uint256 result = stableDebt.getAverageStableRate();

        assertApproxEqAbs(result, rate, 1, "zero previous supply should return mint rate");
    }

    function testFuzz_avgStableRate_BoundedByRates(
        uint256 currentAvgRate,
        uint256 previousSupply,
        uint256 rate,
        uint256 amount
    ) public {
        currentAvgRate = bound(currentAvgRate, 1e22, RAY / 2);
        rate = bound(rate, 1e22, RAY / 2);
        previousSupply = bound(previousSupply, 1e18, 1e30);
        amount = bound(amount, 1e18, 1e30);

        address user1 = makeAddr("user_avg_bounded1");
        address user2 = makeAddr("user_avg_bounded2");
        _mint(user1, previousSupply, currentAvgRate);
        _mint(user2, amount, rate);

        uint256 result = stableDebt.getAverageStableRate();

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
    ) public {
        currentAvgRate = bound(currentAvgRate, 1e22, RAY / 2);
        previousSupply = bound(previousSupply, 1e18, 1e30);
        amount = bound(amount, 1e18, 1e30);
        rate1 = bound(rate1, 1e22, RAY / 2);
        rate2 = bound(rate2, rate1, RAY / 2);

        address user1 = makeAddr("user_avg_mono1");
        _mint(user1, previousSupply, currentAvgRate);

        uint256 snap = vm.snapshot();

        // Scenario 1: new mint at rate1
        address user2 = makeAddr("user_avg_mono2");
        _mint(user2, amount, rate1);
        uint256 avg1 = stableDebt.getAverageStableRate();

        vm.revertTo(snap);

        // Scenario 2: new mint at rate2 (>= rate1)
        _mint(user2, amount, rate2);
        uint256 avg2 = stableDebt.getAverageStableRate();

        assertLe(avg1, avg2 + 1, "higher mint rate should increase avg rate");
    }

    // ============================================================
    //       Accrued Balance (via mint + vm.warp + balanceOf)
    // ============================================================

    function testFuzz_accruedBalance_ZeroPrincipalReturnsZero(
        uint256 timeDelta
    ) public {
        timeDelta = bound(timeDelta, 0, 10 * SECONDS_PER_YEAR);

        address user = makeAddr("user_zero_principal");

        vm.warp(START_TIME + timeDelta);
        uint256 result = stableDebt.balanceOf(user);

        assertEq(result, 0, "zero principal should return zero accrued balance");
    }

    function testFuzz_accruedBalance_ZeroTimeDeltaReturnsPrincipal(
        uint256 principal,
        uint256 stableRate
    ) public {
        principal = bound(principal, 1, 1e30);
        stableRate = bound(stableRate, 0, RAY);

        address user = makeAddr("user_zero_time");
        _mint(user, principal, stableRate);

        // balanceOf at same timestamp (timeDelta=0) returns principal
        uint256 result = stableDebt.balanceOf(user);

        assertEq(result, principal, "zero time delta should return principal");
    }

    function testFuzz_accruedBalance_MonotonicInTime(
        uint256 principal,
        uint256 stableRate,
        uint256 time1,
        uint256 time2
    ) public {
        principal = bound(principal, 1e18, 1e30);
        stableRate = bound(stableRate, 1e22, RAY / 2);
        time1 = bound(time1, START_TIME, START_TIME + 5 * SECONDS_PER_YEAR);
        time2 = bound(time2, time1, START_TIME + 10 * SECONDS_PER_YEAR);

        address user = makeAddr("user_time_mono");
        _mint(user, principal, stableRate);

        vm.warp(time1);
        uint256 bal1 = stableDebt.balanceOf(user);

        vm.warp(time2);
        uint256 bal2 = stableDebt.balanceOf(user);

        assertLe(bal1, bal2, "longer time should give larger or equal accrued balance");
    }

    function testFuzz_accruedBalance_MonotonicInRate(
        uint256 principal,
        uint256 rate1,
        uint256 rate2,
        uint256 timeDelta
    ) public {
        principal = bound(principal, 1e18, 1e30);
        rate1 = bound(rate1, 0, RAY / 2);
        rate2 = bound(rate2, rate1, RAY / 2);
        timeDelta = bound(timeDelta, 1 days, 5 * SECONDS_PER_YEAR);

        address user = makeAddr("user_rate_mono");

        uint256 snap = vm.snapshot();

        // Scenario 1: mint at rate1
        _mint(user, principal, rate1);
        vm.warp(START_TIME + timeDelta);
        uint256 bal1 = stableDebt.balanceOf(user);

        vm.revertTo(snap);

        // Scenario 2: mint at rate2 (>= rate1)
        _mint(user, principal, rate2);
        vm.warp(START_TIME + timeDelta);
        uint256 bal2 = stableDebt.balanceOf(user);

        assertLe(bal1, bal2, "higher rate should give larger or equal accrued balance");
    }

    function testFuzz_accruedBalance_AlwaysGtePrincipal(
        uint256 principal,
        uint256 stableRate,
        uint256 timeDelta
    ) public {
        principal = bound(principal, 1, 1e30);
        stableRate = bound(stableRate, 0, RAY);
        timeDelta = bound(timeDelta, 0, 10 * SECONDS_PER_YEAR);

        address user = makeAddr("user_gte");
        _mint(user, principal, stableRate);

        vm.warp(START_TIME + timeDelta);
        uint256 result = stableDebt.balanceOf(user);

        assertGe(result, principal, "accrued balance should always be >= principal");
    }

    // ============================================================
    //        Total Supply (via mint + vm.warp + totalSupply)
    // ============================================================

    function testFuzz_totalSupply_ZeroPrincipalReturnsZero(
        uint256 timeDelta
    ) public {
        timeDelta = bound(timeDelta, 0, 10 * SECONDS_PER_YEAR);

        vm.warp(START_TIME + timeDelta);
        uint256 result = stableDebt.totalSupply();

        assertEq(result, 0, "zero principal supply should return zero");
    }

    function testFuzz_totalSupply_ZeroTimeDeltaReturnsPrincipal(
        uint256 principalSupply,
        uint256 avgRate
    ) public {
        principalSupply = bound(principalSupply, 1, 1e30);
        avgRate = bound(avgRate, 0, RAY);

        address user = makeAddr("user_ts_zero");
        _mint(user, principalSupply, avgRate);

        uint256 result = stableDebt.totalSupply();

        assertEq(result, principalSupply, "zero time delta should return principal supply");
    }

    function testFuzz_totalSupply_MonotonicInTime(
        uint256 principalSupply,
        uint256 avgRate,
        uint256 time1,
        uint256 time2
    ) public {
        principalSupply = bound(principalSupply, 1e18, 1e30);
        avgRate = bound(avgRate, 1e22, RAY / 2);
        time1 = bound(time1, START_TIME, START_TIME + 5 * SECONDS_PER_YEAR);
        time2 = bound(time2, time1, START_TIME + 10 * SECONDS_PER_YEAR);

        address user = makeAddr("user_ts_time");
        _mint(user, principalSupply, avgRate);

        vm.warp(time1);
        uint256 supply1 = stableDebt.totalSupply();

        vm.warp(time2);
        uint256 supply2 = stableDebt.totalSupply();

        assertLe(supply1, supply2, "longer time should give larger or equal total supply");
    }

    function testFuzz_totalSupply_MonotonicInRate(
        uint256 principalSupply,
        uint256 rate1,
        uint256 rate2,
        uint256 timeDelta
    ) public {
        principalSupply = bound(principalSupply, 1e18, 1e30);
        rate1 = bound(rate1, 0, RAY / 2);
        rate2 = bound(rate2, rate1, RAY / 2);
        timeDelta = bound(timeDelta, 1 days, 5 * SECONDS_PER_YEAR);

        address user = makeAddr("user_ts_rate");

        uint256 snap = vm.snapshot();

        // Scenario 1: mint at rate1
        _mint(user, principalSupply, rate1);
        vm.warp(START_TIME + timeDelta);
        uint256 supply1 = stableDebt.totalSupply();

        vm.revertTo(snap);

        // Scenario 2: mint at rate2 (>= rate1)
        _mint(user, principalSupply, rate2);
        vm.warp(START_TIME + timeDelta);
        uint256 supply2 = stableDebt.totalSupply();

        assertLe(supply1, supply2, "higher rate should give larger or equal total supply");
    }

    function testFuzz_totalSupply_AlwaysGtePrincipal(
        uint256 principalSupply,
        uint256 avgRate,
        uint256 timeDelta
    ) public {
        principalSupply = bound(principalSupply, 1, 1e30);
        avgRate = bound(avgRate, 0, RAY);
        timeDelta = bound(timeDelta, 0, 10 * SECONDS_PER_YEAR);

        address user = makeAddr("user_ts_gte");
        _mint(user, principalSupply, avgRate);

        vm.warp(START_TIME + timeDelta);
        uint256 result = stableDebt.totalSupply();

        assertGe(result, principalSupply, "total supply should always be >= principal supply");
    }
}
