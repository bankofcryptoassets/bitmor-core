// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.13 <0.9.0;

import "forge-std/Test.sol";

interface IVariableDebtTokenHarness {
    function RAY() external pure returns (uint256);
    function scaledAmount(uint256 amount, uint256 index) external pure returns (uint256);
    function scaledBalance(uint256 scaledBal, uint256 normalizedDebt) external pure returns (uint256);
    function mintThenBalance(uint256 amount, uint256 mintIndex, uint256 queryIndex) external pure returns (uint256);
    function mintBurnRoundTrip(uint256 amount, uint256 index) external pure returns (uint256 diff);
}

contract VariableDebtTokenFuzzTest is Test {
    IVariableDebtTokenHarness h;

    uint256 constant RAY = 1e27;

    function setUp() public {
        h = IVariableDebtTokenHarness(deployCode("VariableDebtTokenHarness.sol"));
    }

    // ============================================================
    //                       scaledAmount
    // ============================================================

    function testFuzz_scaledAmount_Identity(uint256 amount) public view {
        amount = bound(amount, 0, type(uint256).max / RAY);
        uint256 result = h.scaledAmount(amount, RAY);
        assertEq(result, amount, "scaledAmount at RAY index should return amount");
    }

    function testFuzz_scaledAmount_MonotonicInIndex(
        uint256 amount,
        uint256 index1,
        uint256 index2
    ) public view {
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
        scaledBal = bound(scaledBal, 0, type(uint256).max / RAY);
        uint256 result = h.scaledBalance(scaledBal, RAY);
        assertEq(result, scaledBal, "scaledBalance at RAY normalizedDebt should return scaledBal");
    }

    function testFuzz_scaledBalance_MonotonicInNormalizedDebt(
        uint256 scaledBal,
        uint256 nd1,
        uint256 nd2
    ) public view {
        // Higher normalized debt → larger balance (more interest accrued)
        scaledBal = bound(scaledBal, 1, 1e36);
        nd1 = bound(nd1, RAY, 10 * RAY);
        nd2 = bound(nd2, nd1, 10 * RAY);

        uint256 bal1 = h.scaledBalance(scaledBal, nd1);
        uint256 bal2 = h.scaledBalance(scaledBal, nd2);

        assertLe(bal1, bal2, "higher normalized debt should give larger or equal balance");
    }

    function testFuzz_scaledBalance_ZeroScaledBal(uint256 nd) public view {
        nd = bound(nd, RAY, 10 * RAY);
        uint256 result = h.scaledBalance(0, nd);
        assertEq(result, 0, "zero scaled balance should return zero");
    }

    // ============================================================
    //                       mintThenBalance
    // ============================================================

    function testFuzz_mintThenBalance_SameIndex(uint256 amount, uint256 index) public view {
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
        // Growing normalized debt index → debt balance increases
        amount = bound(amount, 1e18, 1e36);
        mintIndex = bound(mintIndex, RAY, 5 * RAY);
        queryIndex = bound(queryIndex, mintIndex, 10 * RAY);

        uint256 balance = h.mintThenBalance(amount, mintIndex, queryIndex);

        uint256 maxError = queryIndex / RAY + 1;
        assertGe(balance + maxError, amount, "balance at higher index should be >= original amount minus rounding");
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
        amount = bound(amount, type(uint256).max / RAY + 1, type(uint256).max);
        index = bound(index, 1, RAY / 2);

        vm.expectRevert();
        h.scaledAmount(amount, index);
    }
}
