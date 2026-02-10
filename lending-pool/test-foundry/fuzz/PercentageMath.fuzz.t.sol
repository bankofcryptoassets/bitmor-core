// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.13 <0.9.0;

import "forge-std/Test.sol";

interface IPercentageMathHarness {
    function PERCENTAGE_FACTOR() external pure returns (uint256);
    function HALF_PERCENT() external pure returns (uint256);
    function percentMul(uint256 value, uint256 percentage) external pure returns (uint256);
    function percentDiv(uint256 value, uint256 percentage) external pure returns (uint256);
}

contract PercentageMathFuzzTest is Test {
    IPercentageMathHarness h;

    uint256 BPS; // 10000
    uint256 HALF;

    function setUp() public {
        h = IPercentageMathHarness(deployCode("PercentageMathHarness.sol"));
        BPS = h.PERCENTAGE_FACTOR();
        HALF = h.HALF_PERCENT();
    }

    // ============================================================
    //                        percentMul
    // ============================================================

    function testFuzz_percentMul_Identity(uint256 v) public view {
        // percentMul(v, 10000) == v (100%)
        v = bound(v, 0, type(uint256).max / BPS);
        assertEq(h.percentMul(v, BPS), v, "percentMul identity: v * 100% should equal v");
    }

    function testFuzz_percentMul_ZeroValue(uint256 p) public view {
        assertEq(h.percentMul(0, p), 0, "percentMul: 0 * p% should equal 0");
    }

    function testFuzz_percentMul_ZeroPercentage(uint256 v) public view {
        assertEq(h.percentMul(v, 0), 0, "percentMul: v * 0% should equal 0");
    }

    function testFuzz_percentMul_Double(uint256 v) public view {
        // percentMul(v, 20000) == 2 * v (200%)
        v = bound(v, 0, (type(uint256).max - HALF) / 20000);
        assertEq(h.percentMul(v, 20000), 2 * v, "percentMul: v * 200% should equal 2*v");
    }

    function testFuzz_percentMul_Half(uint256 v) public view {
        // percentMul(v, 5000) should be within ±1 of v/2 (50%)
        v = bound(v, 0, (type(uint256).max - HALF) / 5000);
        uint256 result = h.percentMul(v, 5000);
        uint256 expected = v / 2;
        uint256 diff = result > expected ? result - expected : expected - result;
        assertLe(diff, 1, "percentMul: v * 50% should be within +-1 of v/2");
    }

    function testFuzz_percentMul_Monotonic(uint256 v, uint256 p1, uint256 p2) public view {
        // For fixed v: percentMul(v, p1) <= percentMul(v, p2) when p1 <= p2
        v = bound(v, 1, 1e36);
        p1 = bound(p1, 1, 1e6);
        p2 = bound(p2, p1, 1e6);
        assertLe(
            h.percentMul(v, p1),
            h.percentMul(v, p2),
            "percentMul should be monotonic in percentage"
        );
    }

    function testFuzz_percentMul_OverflowReverts(uint256 v, uint256 p) public {
        // Both large enough to overflow
        v = bound(v, 1e70, type(uint256).max);
        p = bound(p, 1e10, type(uint256).max);
        vm.expectRevert();
        h.percentMul(v, p);
    }

    // ============================================================
    //                        percentDiv
    // ============================================================

    function testFuzz_percentDiv_Identity(uint256 v) public view {
        // percentDiv(v, 10000) == v
        v = bound(v, 0, type(uint256).max / BPS);
        assertEq(h.percentDiv(v, BPS), v, "percentDiv identity: v / 100% should equal v");
    }

    function testFuzz_percentDiv_ZeroNumerator(uint256 p) public view {
        p = bound(p, 1, type(uint256).max);
        assertEq(h.percentDiv(0, p), 0, "percentDiv: 0 / p% should equal 0");
    }

    function testFuzz_percentDiv_DivByZeroReverts(uint256 v) public {
        vm.expectRevert();
        h.percentDiv(v, 0);
    }

    function testFuzz_percentDiv_RoundTrip(uint256 v, uint256 p) public view {
        // percentMul truncates to nearest BPS unit, so round-trip error is bounded by ceil(BPS/p).
        // With p >= BPS the error is at most 1; smaller p means proportionally larger error.
        v = bound(v, 1, 1e30);
        p = bound(p, 1, 1e6);

        uint256 product = h.percentMul(v, p);
        uint256 roundTrip = h.percentDiv(product, p);
        uint256 diff = roundTrip > v ? roundTrip - v : v - roundTrip;
        uint256 maxError = (BPS + p - 1) / p; // ceil(BPS / p)
        assertLe(diff, maxError, "percentDiv(percentMul(v,p), p) round-trip error exceeds bound");
    }

    function testFuzz_percentDiv_LargerDivisorSmallerResult(uint256 v, uint256 p1, uint256 p2) public view {
        v = bound(v, 1, 1e30);
        p1 = bound(p1, 1, 1e6);
        p2 = bound(p2, p1, 1e6);
        assertGe(
            h.percentDiv(v, p1),
            h.percentDiv(v, p2),
            "percentDiv with larger percentage should yield smaller result"
        );
    }

    function testFuzz_percentDiv_OverflowReverts(uint256 v) public {
        // v too large for v * PERCENTAGE_FACTOR
        v = bound(v, (type(uint256).max / BPS) + 1, type(uint256).max);
        vm.expectRevert();
        h.percentDiv(v, 1);
    }
}
