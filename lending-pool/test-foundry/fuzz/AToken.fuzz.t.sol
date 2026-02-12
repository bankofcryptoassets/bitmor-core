// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.13 <0.9.0;

import "forge-std/Test.sol";

interface IATokenHarness {
    function RAY() external pure returns (uint256);
    function scaledAmount(uint256 amount, uint256 index) external pure returns (uint256);
    function scaledBalance(uint256 scaledBal, uint256 index) external pure returns (uint256);
    function mintThenBalance(uint256 amount, uint256 mintIndex, uint256 queryIndex) external pure returns (uint256);
    function mintBurnRoundTrip(uint256 amount, uint256 index) external pure returns (uint256 diff);
}

contract ATokenFuzzTest is Test {
    IATokenHarness h;

    uint256 constant RAY = 1e27;

    function setUp() public {
        h = IATokenHarness(deployCode("ATokenHarness.sol"));
    }

    // ============================================================
    //                       scaledAmount
    // ============================================================

    function testFuzz_scaledAmount_Identity(uint256 amount) public view {
        // rayDiv(amount, RAY) == amount for non-overflowing values
        amount = bound(amount, 0, type(uint256).max / RAY);
        uint256 result = h.scaledAmount(amount, RAY);
        assertEq(result, amount, "scaledAmount at RAY index should return amount");
    }

    function testFuzz_scaledAmount_MonotonicInIndex(
        uint256 amount,
        uint256 index1,
        uint256 index2
    ) public view {
        // Higher index → smaller scaled amount (more growth already happened)
        amount = bound(amount, 1, 1e36);
        index1 = bound(index1, RAY, 10 * RAY);
        index2 = bound(index2, index1, 10 * RAY);

        uint256 scaled1 = h.scaledAmount(amount, index1);
        uint256 scaled2 = h.scaledAmount(amount, index2);

        assertGe(scaled1, scaled2, "higher index should give smaller or equal scaled amount");
    }

    function testFuzz_scaledAmount_ZeroAmount(uint256 index) public view {
        index = bound(index, RAY, 10 * RAY);
        uint256 result = h.scaledAmount(0, index);
        assertEq(result, 0, "scaling zero amount should return zero");
    }

    // ============================================================
    //                       scaledBalance
    // ============================================================

    function testFuzz_scaledBalance_Identity(uint256 scaledBal) public view {
        // rayMul(scaledBal, RAY) == scaledBal
        scaledBal = bound(scaledBal, 0, type(uint256).max / RAY);
        uint256 result = h.scaledBalance(scaledBal, RAY);
        assertEq(result, scaledBal, "scaledBalance at RAY index should return scaledBal");
    }

    function testFuzz_scaledBalance_MonotonicInIndex(
        uint256 scaledBal,
        uint256 index1,
        uint256 index2
    ) public view {
        // Higher index → larger balance (more interest accrued)
        scaledBal = bound(scaledBal, 1, 1e36);
        index1 = bound(index1, RAY, 10 * RAY);
        index2 = bound(index2, index1, 10 * RAY);

        uint256 bal1 = h.scaledBalance(scaledBal, index1);
        uint256 bal2 = h.scaledBalance(scaledBal, index2);

        assertLe(bal1, bal2, "higher index should give larger or equal balance");
    }

    function testFuzz_scaledBalance_ZeroScaledBal(uint256 index) public view {
        index = bound(index, RAY, 10 * RAY);
        uint256 result = h.scaledBalance(0, index);
        assertEq(result, 0, "zero scaled balance should return zero");
    }

    // ============================================================
    //                       mintThenBalance
    // ============================================================

    function testFuzz_mintThenBalance_SameIndex(uint256 amount, uint256 index) public view {
        // Mint at index, query at same index → should recover amount (± rounding)
        // Rounding error from rayDiv then rayMul is bounded by ceil(index / RAY) + 1
        amount = bound(amount, 0, 1e36);
        index = bound(index, RAY, 10 * RAY);

        uint256 recovered = h.mintThenBalance(amount, index, index);
        uint256 diff = amount > recovered ? amount - recovered : recovered - amount;
        uint256 maxError = index / RAY + 1;

        assertLe(diff, maxError, "mint+query at same index should recover amount within rounding tolerance");
    }

    function testFuzz_mintThenBalance_GrowingIndex(
        uint256 amount,
        uint256 mintIndex,
        uint256 queryIndex
    ) public view {
        // Query at higher index → balance >= original amount (interest accrued)
        // Use minimum amount large enough to survive rayDiv rounding
        amount = bound(amount, 1e18, 1e36);
        mintIndex = bound(mintIndex, RAY, 5 * RAY);
        queryIndex = bound(queryIndex, mintIndex, 10 * RAY);

        uint256 balance = h.mintThenBalance(amount, mintIndex, queryIndex);

        // Allow rounding tolerance: ceil(queryIndex / RAY) + 1
        uint256 maxError = queryIndex / RAY + 1;
        assertGe(balance + maxError, amount, "balance at higher index should be >= original amount minus rounding");
    }

    function testFuzz_mintThenBalance_DecreasingIndex(
        uint256 amount,
        uint256 mintIndex,
        uint256 queryIndex
    ) public view {
        // Query at lower index → balance <= original amount (+ rounding tolerance)
        // Rounding from rayDiv then rayMul can yield result slightly above original
        amount = bound(amount, 1e18, 1e36);
        queryIndex = bound(queryIndex, RAY, 5 * RAY);
        mintIndex = bound(mintIndex, queryIndex, 10 * RAY);

        uint256 balance = h.mintThenBalance(amount, mintIndex, queryIndex);

        uint256 maxError = mintIndex / RAY + 1;
        assertLe(balance, amount + maxError, "balance at lower index should be <= original amount + rounding tolerance");
    }

    // ============================================================
    //                    mintBurnRoundTrip
    // ============================================================

    function testFuzz_mintBurnRoundTrip_BoundedError(uint256 amount, uint256 index) public view {
        // Precision loss from rayDiv then rayMul is bounded by ceil(index / RAY) + 1
        amount = bound(amount, 0, 1e36);
        index = bound(index, RAY, 10 * RAY);

        uint256 diff = h.mintBurnRoundTrip(amount, index);
        uint256 maxError = index / RAY + 1;

        assertLe(diff, maxError, "mint-burn round trip precision loss should be within rounding tolerance");
    }

    function testFuzz_mintBurnRoundTrip_ZeroAmountNoDiff(uint256 index) public view {
        index = bound(index, RAY, 10 * RAY);
        uint256 diff = h.mintBurnRoundTrip(0, index);
        assertEq(diff, 0, "zero amount should have zero round-trip diff");
    }

    // ============================================================
    //                      overflow
    // ============================================================

    function testFuzz_scaledAmount_OverflowReverts(uint256 amount, uint256 index) public {
        // Large amount with small index should overflow in rayDiv
        amount = bound(amount, type(uint256).max / RAY + 1, type(uint256).max);
        index = bound(index, 1, RAY / 2);

        vm.expectRevert();
        h.scaledAmount(amount, index);
    }
}
