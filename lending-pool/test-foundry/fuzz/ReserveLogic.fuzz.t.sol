// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.13 <0.9.0;

import "forge-std/Test.sol";

interface IReserveLogicHarness {
    function setLiquidityIndex(uint128 index) external;
    function setVariableBorrowIndex(uint128 index) external;
    function setCurrentLiquidityRate(uint128 rate) external;
    function setCurrentVariableBorrowRate(uint128 rate) external;
    function setLastUpdateTimestamp(uint40 ts) external;
    function getLiquidityIndex() external view returns (uint128);
    function getVariableBorrowIndex() external view returns (uint128);
    function getLastUpdateTimestamp() external view returns (uint40);
    function getNormalizedIncome() external view returns (uint256);
    function getNormalizedDebt() external view returns (uint256);
}

contract ReserveLogicFuzzTest is Test {
    IReserveLogicHarness h;

    uint256 constant RAY = 1e27;
    uint128 constant RAY_128 = uint128(RAY);
    uint256 constant MAX_RATE = 1e27; // 100% APR
    uint256 constant SECONDS_PER_YEAR = 365 days;
    uint256 constant MAX_TIME_DELTA = 10 * SECONDS_PER_YEAR;

    function setUp() public {
        h = IReserveLogicHarness(deployCode("ReserveLogicHarness.sol"));
    }

    // ============================================================
    //                   getNormalizedIncome
    // ============================================================

    function testFuzz_normalizedIncome_SameTimestamp(uint128 index) public {
        // When lastUpdateTimestamp == block.timestamp, returns liquidityIndex unchanged
        index = uint128(bound(uint256(index), RAY, type(uint128).max));
        uint40 ts = uint40(block.timestamp);

        h.setLiquidityIndex(index);
        h.setCurrentLiquidityRate(uint128(bound(uint256(MAX_RATE), 0, MAX_RATE)));
        h.setLastUpdateTimestamp(ts);

        assertEq(
            h.getNormalizedIncome(),
            uint256(index),
            "normalized income should equal liquidityIndex when timestamp matches"
        );
    }

    function testFuzz_normalizedIncome_AlwaysGteIndex(uint128 rate, uint256 timeDelta) public {
        // Normalized income should always be >= initial index (interest accrues, never negative)
        rate = uint128(bound(uint256(rate), 0, MAX_RATE));
        timeDelta = bound(timeDelta, 0, MAX_TIME_DELTA);
        uint40 start = uint40(block.timestamp);

        h.setLiquidityIndex(RAY_128);
        h.setCurrentLiquidityRate(rate);
        h.setLastUpdateTimestamp(start);

        vm.warp(uint256(start) + timeDelta);
        uint256 income = h.getNormalizedIncome();
        assertGe(income, RAY, "normalized income should always be >= initial index (RAY)");
    }

    function testFuzz_normalizedIncome_MonotonicInTime(
        uint128 rate,
        uint256 t1,
        uint256 t2
    ) public {
        // Longer elapsed time → higher normalized income
        rate = uint128(bound(uint256(rate), 1, MAX_RATE));
        t1 = bound(t1, 0, MAX_TIME_DELTA);
        t2 = bound(t2, t1, MAX_TIME_DELTA);
        uint40 start = uint40(block.timestamp);

        h.setLiquidityIndex(RAY_128);
        h.setCurrentLiquidityRate(rate);
        h.setLastUpdateTimestamp(start);

        vm.warp(uint256(start) + t1);
        uint256 income1 = h.getNormalizedIncome();

        // Reset to same start state for second measurement
        h.setLiquidityIndex(RAY_128);
        h.setCurrentLiquidityRate(rate);
        h.setLastUpdateTimestamp(start);

        vm.warp(uint256(start) + t2);
        uint256 income2 = h.getNormalizedIncome();

        assertLe(income1, income2, "normalized income should be monotonically increasing in time");
    }

    function testFuzz_normalizedIncome_MonotonicInRate(
        uint128 rate1,
        uint128 rate2,
        uint256 timeDelta
    ) public {
        // Higher rate → higher normalized income
        rate1 = uint128(bound(uint256(rate1), 0, MAX_RATE));
        rate2 = uint128(bound(uint256(rate2), uint256(rate1), MAX_RATE));
        timeDelta = bound(timeDelta, 1, MAX_TIME_DELTA);
        uint40 start = uint40(block.timestamp);

        h.setLiquidityIndex(RAY_128);
        h.setCurrentLiquidityRate(rate1);
        h.setLastUpdateTimestamp(start);
        vm.warp(uint256(start) + timeDelta);
        uint256 income1 = h.getNormalizedIncome();

        h.setLiquidityIndex(RAY_128);
        h.setCurrentLiquidityRate(rate2);
        h.setLastUpdateTimestamp(start);
        // warp is already at start + timeDelta
        uint256 income2 = h.getNormalizedIncome();

        assertLe(income1, income2, "normalized income should be monotonically increasing in rate");
    }

    function testFuzz_normalizedIncome_ZeroRate(uint256 timeDelta) public {
        // Zero rate → income remains at base index regardless of time
        timeDelta = bound(timeDelta, 0, MAX_TIME_DELTA);
        uint40 start = uint40(block.timestamp);

        h.setLiquidityIndex(RAY_128);
        h.setCurrentLiquidityRate(0);
        h.setLastUpdateTimestamp(start);

        vm.warp(uint256(start) + timeDelta);
        assertEq(
            h.getNormalizedIncome(),
            RAY,
            "normalized income with zero rate should equal base index"
        );
    }

    function testFuzz_normalizedIncome_ScalesWithIndex(uint128 index, uint256 timeDelta) public {
        // Higher starting index → higher normalized income (proportional scaling)
        // Using small timeDelta and a fixed rate to avoid overflow
        index = uint128(bound(uint256(index), RAY, type(uint128).max / 2));
        timeDelta = bound(timeDelta, 1, SECONDS_PER_YEAR);
        uint40 start = uint40(block.timestamp);
        uint128 rate = uint128(RAY / 10); // 10% APR

        h.setLiquidityIndex(RAY_128);
        h.setCurrentLiquidityRate(rate);
        h.setLastUpdateTimestamp(start);
        vm.warp(uint256(start) + timeDelta);
        uint256 incomeBase = h.getNormalizedIncome();

        h.setLiquidityIndex(index);
        h.setCurrentLiquidityRate(rate);
        h.setLastUpdateTimestamp(start);
        // warp is already at start + timeDelta
        uint256 incomeScaled = h.getNormalizedIncome();

        // incomeScaled = linearInterest(rate, timeDelta).rayMul(index)
        // incomeBase = linearInterest(rate, timeDelta).rayMul(RAY) = linearInterest(rate, timeDelta)
        // So incomeScaled should be >= incomeBase when index >= RAY
        if (index >= RAY_128) {
            assertGe(
                incomeScaled,
                incomeBase,
                "higher index should yield higher normalized income"
            );
        }
    }

    // ============================================================
    //                   getNormalizedDebt
    // ============================================================

    function testFuzz_normalizedDebt_SameTimestamp(uint128 index) public {
        // When lastUpdateTimestamp == block.timestamp, returns variableBorrowIndex unchanged
        index = uint128(bound(uint256(index), RAY, type(uint128).max));
        uint40 ts = uint40(block.timestamp);

        h.setVariableBorrowIndex(index);
        h.setCurrentVariableBorrowRate(uint128(bound(uint256(MAX_RATE), 0, MAX_RATE)));
        h.setLastUpdateTimestamp(ts);

        assertEq(
            h.getNormalizedDebt(),
            uint256(index),
            "normalized debt should equal variableBorrowIndex when timestamp matches"
        );
    }

    function testFuzz_normalizedDebt_AlwaysGteIndex(uint128 rate, uint256 timeDelta) public {
        // Normalized debt should always be >= initial index
        rate = uint128(bound(uint256(rate), 0, MAX_RATE));
        timeDelta = bound(timeDelta, 0, MAX_TIME_DELTA);
        uint40 start = uint40(block.timestamp);

        h.setVariableBorrowIndex(RAY_128);
        h.setCurrentVariableBorrowRate(rate);
        h.setLastUpdateTimestamp(start);

        vm.warp(uint256(start) + timeDelta);
        uint256 debt = h.getNormalizedDebt();
        assertGe(debt, RAY, "normalized debt should always be >= initial index (RAY)");
    }

    function testFuzz_normalizedDebt_MonotonicInTime(
        uint128 rate,
        uint256 t1,
        uint256 t2
    ) public {
        // Longer elapsed time → higher normalized debt
        rate = uint128(bound(uint256(rate), 1, MAX_RATE));
        t1 = bound(t1, 0, MAX_TIME_DELTA);
        t2 = bound(t2, t1, MAX_TIME_DELTA);
        uint40 start = uint40(block.timestamp);

        h.setVariableBorrowIndex(RAY_128);
        h.setCurrentVariableBorrowRate(rate);
        h.setLastUpdateTimestamp(start);

        vm.warp(uint256(start) + t1);
        uint256 debt1 = h.getNormalizedDebt();

        h.setVariableBorrowIndex(RAY_128);
        h.setCurrentVariableBorrowRate(rate);
        h.setLastUpdateTimestamp(start);

        vm.warp(uint256(start) + t2);
        uint256 debt2 = h.getNormalizedDebt();

        assertLe(debt1, debt2, "normalized debt should be monotonically increasing in time");
    }

    function testFuzz_normalizedDebt_MonotonicInRate(
        uint128 rate1,
        uint128 rate2,
        uint256 timeDelta
    ) public {
        // Higher rate → higher normalized debt
        rate1 = uint128(bound(uint256(rate1), 0, MAX_RATE));
        rate2 = uint128(bound(uint256(rate2), uint256(rate1), MAX_RATE));
        timeDelta = bound(timeDelta, 1, MAX_TIME_DELTA);
        uint40 start = uint40(block.timestamp);

        h.setVariableBorrowIndex(RAY_128);
        h.setCurrentVariableBorrowRate(rate1);
        h.setLastUpdateTimestamp(start);
        vm.warp(uint256(start) + timeDelta);
        uint256 debt1 = h.getNormalizedDebt();

        h.setVariableBorrowIndex(RAY_128);
        h.setCurrentVariableBorrowRate(rate2);
        h.setLastUpdateTimestamp(start);
        uint256 debt2 = h.getNormalizedDebt();

        assertLe(debt1, debt2, "normalized debt should be monotonically increasing in rate");
    }

    function testFuzz_normalizedDebt_ZeroRate(uint256 timeDelta) public {
        // Zero rate → debt remains at base index
        timeDelta = bound(timeDelta, 0, MAX_TIME_DELTA);
        uint40 start = uint40(block.timestamp);

        h.setVariableBorrowIndex(RAY_128);
        h.setCurrentVariableBorrowRate(0);
        h.setLastUpdateTimestamp(start);

        vm.warp(uint256(start) + timeDelta);
        assertEq(
            h.getNormalizedDebt(),
            RAY,
            "normalized debt with zero rate should equal base index"
        );
    }

    // ============================================================
    //          Income uses linear, Debt uses compounded
    // ============================================================

    function testFuzz_incomeVsDebt_CompoundedGteLinear(
        uint128 rate,
        uint256 timeDelta
    ) public {
        // Compounded interest >= linear interest for same rate and time
        // This means normalizedDebt (compounded) >= normalizedIncome (linear) when starting from same index
        // Note: Due to integer truncation in ratePerSecond, compound can slightly undershoot linear.
        // We test closeness instead of strict >=.
        rate = uint128(bound(uint256(rate), 0, MAX_RATE));
        timeDelta = bound(timeDelta, 1, MAX_TIME_DELTA);
        uint40 start = uint40(block.timestamp);

        // Set both to same initial state
        h.setLiquidityIndex(RAY_128);
        h.setCurrentLiquidityRate(rate);
        h.setVariableBorrowIndex(RAY_128);
        h.setCurrentVariableBorrowRate(rate);
        h.setLastUpdateTimestamp(start);

        vm.warp(uint256(start) + timeDelta);

        uint256 income = h.getNormalizedIncome(); // linear
        uint256 debt = h.getNormalizedDebt(); // compounded

        // Compound can be slightly below linear due to ratePerSecond truncation.
        // But the deficit is bounded by timeDelta (max 1 unit truncation per second).
        if (debt < income) {
            assertLe(
                income - debt,
                timeDelta,
                "compound vs linear gap should be bounded by timeDelta"
            );
        }
    }
}
