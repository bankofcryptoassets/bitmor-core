// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.13 <0.9.0;

import "forge-std/Test.sol";

interface IMathUtilsHarness {
    function SECONDS_PER_YEAR() external pure returns (uint256);
    function calculateLinearInterest(uint256 rate, uint40 lastUpdateTimestamp) external view returns (uint256);
    function calculateCompoundedInterest(uint256 rate, uint40 lastUpdateTimestamp, uint256 currentTimestamp) external pure returns (uint256);
}

contract MathUtilsFuzzTest is Test {
    IMathUtilsHarness h;

    uint256 RAY;
    uint256 SECONDS_PER_YEAR;
    uint256 MAX_RATE;
    uint256 MAX_TIME_DELTA;

    function setUp() public {
        h = IMathUtilsHarness(deployCode("MathUtilsHarness.sol"));
        RAY = 1e27;
        SECONDS_PER_YEAR = h.SECONDS_PER_YEAR();
        MAX_RATE = 1e27; // 100% APR
        MAX_TIME_DELTA = 10 * SECONDS_PER_YEAR; // 10 years
    }

    // ============================================================
    //                  calculateLinearInterest
    // ============================================================

    function testFuzz_linearInterest_ZeroElapsed(uint256 rate) public {
        // When block.timestamp == lastUpdateTimestamp, result == RAY
        rate = bound(rate, 0, MAX_RATE);
        uint40 ts = uint40(block.timestamp);
        vm.warp(ts);
        assertEq(
            h.calculateLinearInterest(rate, ts),
            RAY,
            "linear interest with zero elapsed should return RAY"
        );
    }

    function testFuzz_linearInterest_OneYear(uint256 rate) public {
        // After exactly 1 year: result == RAY + rate
        rate = bound(rate, 0, MAX_RATE);
        uint40 start = uint40(block.timestamp);
        vm.warp(uint256(start) + SECONDS_PER_YEAR);
        assertEq(
            h.calculateLinearInterest(rate, start),
            RAY + rate,
            "linear interest after 1 year should equal RAY + rate"
        );
    }

    function testFuzz_linearInterest_AlwaysGteRay(uint256 rate, uint256 timeDelta) public {
        // Result should always be >= RAY (interest cannot be negative)
        rate = bound(rate, 0, MAX_RATE);
        timeDelta = bound(timeDelta, 0, MAX_TIME_DELTA);
        uint40 start = uint40(block.timestamp);
        vm.warp(uint256(start) + timeDelta);
        assertGe(
            h.calculateLinearInterest(rate, start),
            RAY,
            "linear interest should always be >= RAY"
        );
    }

    function testFuzz_linearInterest_MonotonicInTime(uint256 rate, uint256 t1, uint256 t2) public {
        // Longer elapsed time should yield higher interest
        rate = bound(rate, 1, MAX_RATE);
        t1 = bound(t1, 0, MAX_TIME_DELTA);
        t2 = bound(t2, t1, MAX_TIME_DELTA);
        uint40 start = uint40(block.timestamp);

        vm.warp(uint256(start) + t1);
        uint256 r1 = h.calculateLinearInterest(rate, start);

        vm.warp(uint256(start) + t2);
        uint256 r2 = h.calculateLinearInterest(rate, start);

        assertLe(r1, r2, "linear interest should be monotonic in time");
    }

    function testFuzz_linearInterest_MonotonicInRate(uint256 rate1, uint256 rate2, uint256 timeDelta) public {
        // Higher rate should yield higher interest (for same time)
        rate1 = bound(rate1, 0, MAX_RATE);
        rate2 = bound(rate2, rate1, MAX_RATE);
        timeDelta = bound(timeDelta, 1, MAX_TIME_DELTA);
        uint40 start = uint40(block.timestamp);
        vm.warp(uint256(start) + timeDelta);

        uint256 r1 = h.calculateLinearInterest(rate1, start);
        uint256 r2 = h.calculateLinearInterest(rate2, start);

        assertLe(r1, r2, "linear interest should be monotonic in rate");
    }

    function testFuzz_linearInterest_ZeroRate(uint256 timeDelta) public {
        // Zero rate should always return RAY regardless of time
        timeDelta = bound(timeDelta, 0, MAX_TIME_DELTA);
        uint40 start = uint40(block.timestamp);
        vm.warp(uint256(start) + timeDelta);
        assertEq(
            h.calculateLinearInterest(0, start),
            RAY,
            "linear interest with zero rate should return RAY"
        );
    }

    // ============================================================
    //                calculateCompoundedInterest
    // ============================================================

    function testFuzz_compoundedInterest_ZeroElapsed(uint256 rate) public view {
        // When currentTimestamp == lastUpdateTimestamp, result == RAY
        rate = bound(rate, 0, MAX_RATE);
        uint40 ts = uint40(block.timestamp);
        assertEq(
            h.calculateCompoundedInterest(rate, ts, uint256(ts)),
            RAY,
            "compounded interest with zero elapsed should return RAY"
        );
    }

    function testFuzz_compoundedInterest_AlwaysGteRay(uint256 rate, uint256 timeDelta) public view {
        // Result should always be >= RAY
        rate = bound(rate, 0, MAX_RATE);
        timeDelta = bound(timeDelta, 0, MAX_TIME_DELTA);
        uint40 start = uint40(block.timestamp);
        assertGe(
            h.calculateCompoundedInterest(rate, start, uint256(start) + timeDelta),
            RAY,
            "compounded interest should always be >= RAY"
        );
    }

    function testFuzz_compoundedInterest_MonotonicInTime(uint256 rate, uint256 t1, uint256 t2) public view {
        // Longer elapsed time should yield higher interest
        rate = bound(rate, 1, MAX_RATE);
        t1 = bound(t1, 0, MAX_TIME_DELTA);
        t2 = bound(t2, t1, MAX_TIME_DELTA);
        uint40 start = uint40(block.timestamp);

        uint256 r1 = h.calculateCompoundedInterest(rate, start, uint256(start) + t1);
        uint256 r2 = h.calculateCompoundedInterest(rate, start, uint256(start) + t2);

        assertLe(r1, r2, "compounded interest should be monotonic in time");
    }

    function testFuzz_compoundedInterest_MonotonicInRate(uint256 rate1, uint256 rate2, uint256 timeDelta) public view {
        // Higher rate should yield higher interest
        rate1 = bound(rate1, 0, MAX_RATE);
        rate2 = bound(rate2, rate1, MAX_RATE);
        timeDelta = bound(timeDelta, 1, MAX_TIME_DELTA);
        uint40 start = uint40(block.timestamp);

        uint256 r1 = h.calculateCompoundedInterest(rate1, start, uint256(start) + timeDelta);
        uint256 r2 = h.calculateCompoundedInterest(rate2, start, uint256(start) + timeDelta);

        assertLe(r1, r2, "compounded interest should be monotonic in rate");
    }

    function testFuzz_compoundedInterest_CloseToLinear(uint256 rate, uint256 timeDelta) public {
        // The 3-term binomial approximation uses ratePerSecond = rate / SECONDS_PER_YEAR
        // (integer division), then multiplies by time. Linear interest does rate * time / SECONDS_PER_YEAR
        // (single division). The different truncation order means compound can slightly undershoot linear.
        // Mathematically (1+x)^n >= 1+nx, but integer truncation of ratePerSecond breaks this.
        // We verify they are close: |compound - linear| <= timeDelta (max 1 unit per second of truncation).
        rate = bound(rate, 0, MAX_RATE);
        timeDelta = bound(timeDelta, 1, MAX_TIME_DELTA);
        uint40 start = uint40(block.timestamp);
        vm.warp(uint256(start) + timeDelta);

        uint256 linear = h.calculateLinearInterest(rate, start);
        uint256 compounded = h.calculateCompoundedInterest(rate, start, uint256(start) + timeDelta);

        // Compound's higher-order terms add value, but truncation of ratePerSecond loses at most
        // 1 unit per second in the first-order term, so the max deficit is bounded by timeDelta.
        if (compounded < linear) {
            assertLe(
                linear - compounded,
                timeDelta,
                "compound vs linear gap should be bounded by timeDelta"
            );
        }
    }

    function testFuzz_compoundedInterest_ZeroRate(uint256 timeDelta) public view {
        // Zero rate should always return RAY
        timeDelta = bound(timeDelta, 0, MAX_TIME_DELTA);
        uint40 start = uint40(block.timestamp);
        assertEq(
            h.calculateCompoundedInterest(0, start, uint256(start) + timeDelta),
            RAY,
            "compounded interest with zero rate should return RAY"
        );
    }

    function testFuzz_compoundedInterest_OneSecond(uint256 rate) public view {
        // With 1 second elapsed, compounded ≈ linear (first-order term dominates)
        rate = bound(rate, 0, MAX_RATE);
        uint40 start = uint40(block.timestamp);

        uint256 compounded = h.calculateCompoundedInterest(rate, start, uint256(start) + 1);
        uint256 ratePerSecond = rate / SECONDS_PER_YEAR;
        uint256 expected = RAY + ratePerSecond;

        assertEq(
            compounded,
            expected,
            "compounded interest for 1 second should equal RAY + ratePerSecond"
        );
    }
}
