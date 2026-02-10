// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.13 <0.9.0;

import "forge-std/Test.sol";

interface IWadRayMathHarness {
    function RAY() external pure returns (uint256);
    function WAD() external pure returns (uint256);
    function WAD_RAY_RATIO() external pure returns (uint256);
    function rayMul(uint256 a, uint256 b) external pure returns (uint256);
    function rayDiv(uint256 a, uint256 b) external pure returns (uint256);
    function wadDiv(uint256 a, uint256 b) external pure returns (uint256);
    function wadToRay(uint256 a) external pure returns (uint256);
}

contract WadRayMathFuzzTest is Test {
    IWadRayMathHarness h;

    uint256 RAY;
    uint256 WAD;
    uint256 WAD_RAY_RATIO;
    uint256 HALF_RAY;
    uint256 HALF_WAD;

    function setUp() public {
        h = IWadRayMathHarness(deployCode("WadRayMathHarness.sol"));
        RAY = h.RAY();
        WAD = h.WAD();
        WAD_RAY_RATIO = h.WAD_RAY_RATIO();
        HALF_RAY = RAY / 2;
        HALF_WAD = WAD / 2;
    }

    // ============================================================
    //                        rayMul
    // ============================================================

    function testFuzz_rayMul_Identity(uint256 a) public view {
        // rayMul(a, RAY) == a
        a = bound(a, 0, type(uint256).max / RAY);
        assertEq(h.rayMul(a, RAY), a, "rayMul identity: a * 1.0 should equal a");
    }

    function testFuzz_rayMul_ZeroLeft(uint256 b) public view {
        assertEq(h.rayMul(0, b), 0, "rayMul zero left: 0 * b should equal 0");
    }

    function testFuzz_rayMul_ZeroRight(uint256 a) public view {
        assertEq(h.rayMul(a, 0), 0, "rayMul zero right: a * 0 should equal 0");
    }

    function testFuzz_rayMul_Commutativity(uint256 a, uint256 b) public view {
        // Bound so a*b won't overflow: both <= sqrt(uint256.max) ≈ 3.4e38
        a = bound(a, 0, 1e38);
        b = bound(b, 0, 1e38);
        assertEq(h.rayMul(a, b), h.rayMul(b, a), "rayMul should be commutative");
    }

    function testFuzz_rayMul_ScalingDown(uint256 a, uint256 b) public view {
        // When b <= RAY, result should be <= a (scaling down)
        // Bound a so a * RAY doesn't overflow: a <= (uint256.max - halfRAY) / RAY
        a = bound(a, 1, (type(uint256).max - HALF_RAY) / RAY);
        b = bound(b, 1, RAY);
        uint256 result = h.rayMul(a, b);
        // Allow +1 for rounding
        assertLe(result, a + 1, "rayMul with b <= RAY should scale down (within rounding)");
    }

    function testFuzz_rayMul_ScalingUp(uint256 a, uint256 b) public view {
        // When b >= RAY, result should be >= a (scaling up)
        // Bound a so a * b doesn't overflow with b up to 1e36
        a = bound(a, 1, 1e38);
        b = bound(b, RAY, 1e36);
        uint256 result = h.rayMul(a, b);
        // Allow -1 for rounding
        assertGe(result + 1, a, "rayMul with b >= RAY should scale up (within rounding)");
    }

    function testFuzz_rayMul_OverflowReverts(uint256 a, uint256 b) public {
        // Both large enough to overflow
        a = bound(a, 1e60, type(uint256).max);
        b = bound(b, 1e60, type(uint256).max);
        vm.expectRevert();
        h.rayMul(a, b);
    }

    // ============================================================
    //                        rayDiv
    // ============================================================

    function testFuzz_rayDiv_Identity(uint256 a) public view {
        // rayDiv(a, RAY) == a
        a = bound(a, 0, type(uint256).max / RAY);
        assertEq(h.rayDiv(a, RAY), a, "rayDiv identity: a / 1.0 should equal a");
    }

    function testFuzz_rayDiv_ZeroNumerator(uint256 b) public view {
        b = bound(b, 1, type(uint256).max);
        assertEq(h.rayDiv(0, b), 0, "rayDiv zero numerator: 0 / b should equal 0");
    }

    function testFuzz_rayDiv_DivByZeroReverts(uint256 a) public {
        vm.expectRevert();
        h.rayDiv(a, 0);
    }

    function testFuzz_rayDiv_RoundTrip(uint256 a, uint256 b) public view {
        // rayMul truncates to nearest ray unit, so round-trip error is bounded by ceil(RAY/b).
        // With b >= RAY the error is at most 1; smaller b means proportionally larger error.
        a = bound(a, 1, 1e36);
        b = bound(b, 1e18, 1e36);
        uint256 product = h.rayMul(a, b);
        uint256 roundTrip = h.rayDiv(product, b);
        uint256 diff = roundTrip > a ? roundTrip - a : a - roundTrip;
        uint256 maxError = (RAY + b - 1) / b; // ceil(RAY / b)
        assertLe(diff, maxError, "rayDiv(rayMul(a,b), b) round-trip error exceeds bound");
    }

    function testFuzz_rayDiv_OverflowReverts(uint256 a) public {
        // a too large for a * RAY
        a = bound(a, (type(uint256).max / RAY) + 1, type(uint256).max);
        vm.expectRevert();
        h.rayDiv(a, 1);
    }

    // ============================================================
    //                        wadDiv
    // ============================================================

    function testFuzz_wadDiv_Identity(uint256 a) public view {
        // wadDiv(a, WAD) == a
        a = bound(a, 0, type(uint256).max / WAD);
        assertEq(h.wadDiv(a, WAD), a, "wadDiv identity: a / 1.0 should equal a");
    }

    function testFuzz_wadDiv_ZeroNumerator(uint256 b) public view {
        b = bound(b, 1, type(uint256).max);
        assertEq(h.wadDiv(0, b), 0, "wadDiv zero numerator: 0 / b should equal 0");
    }

    function testFuzz_wadDiv_DivByZeroReverts(uint256 a) public {
        vm.expectRevert();
        h.wadDiv(a, 0);
    }

    function testFuzz_wadDiv_OverflowReverts(uint256 a) public {
        a = bound(a, (type(uint256).max / WAD) + 1, type(uint256).max);
        vm.expectRevert();
        h.wadDiv(a, 1);
    }

    function testFuzz_wadDiv_LargerDivisorSmallerResult(uint256 a, uint256 b1, uint256 b2) public view {
        // Larger divisor should yield smaller or equal result
        a = bound(a, 1, 1e36);
        b1 = bound(b1, 1, 1e36);
        b2 = bound(b2, b1, 1e36);
        uint256 r1 = h.wadDiv(a, b1);
        uint256 r2 = h.wadDiv(a, b2);
        assertGe(r1, r2, "wadDiv with larger divisor should yield smaller result");
    }

    // ============================================================
    //                        wadToRay
    // ============================================================

    function testFuzz_wadToRay_CorrectScaling(uint256 a) public view {
        a = bound(a, 0, type(uint256).max / WAD_RAY_RATIO);
        uint256 result = h.wadToRay(a);
        assertEq(result, a * WAD_RAY_RATIO, "wadToRay should multiply by 1e9");
    }

    function testFuzz_wadToRay_OverflowReverts(uint256 a) public {
        a = bound(a, (type(uint256).max / WAD_RAY_RATIO) + 1, type(uint256).max);
        vm.expectRevert();
        h.wadToRay(a);
    }
}
