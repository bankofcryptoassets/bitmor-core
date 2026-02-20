// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.13 <0.9.0;

import "forge-std/Test.sol";

interface IGenericLogicHarness {
    function HEALTH_FACTOR_LIQUIDATION_THRESHOLD() external pure returns (uint256);
    function calculateHealthFactorFromBalances(
        uint256 totalCollateralInETH,
        uint256 totalDebtInETH,
        uint256 liquidationThreshold
    ) external pure returns (uint256);
    function calculateAvailableBorrowsETH(
        uint256 totalCollateralInETH,
        uint256 totalDebtInETH,
        uint256 ltv
    ) external pure returns (uint256);
}

contract GenericLogicFuzzTest is Test {
    IGenericLogicHarness h;

    uint256 HF_THRESHOLD; // 1e18
    uint256 BPS; // 10000
    uint256 WAD; // 1e18

    function setUp() public {
        h = IGenericLogicHarness(deployCode("GenericLogicHarness.sol"));
        HF_THRESHOLD = h.HEALTH_FACTOR_LIQUIDATION_THRESHOLD();
        BPS = 10000;
        WAD = 1e18;
    }

    // ============================================================
    //           calculateHealthFactorFromBalances
    // ============================================================

    function testFuzz_healthFactor_ZeroDebtReturnsMax(
        uint256 collateral,
        uint256 threshold
    ) public view {
        // When debt == 0, health factor should be max uint256
        collateral = bound(collateral, 0, 1e30);
        threshold = bound(threshold, 0, BPS);
        uint256 hf = h.calculateHealthFactorFromBalances(collateral, 0, threshold);
        assertEq(hf, type(uint256).max, "zero debt should return max health factor");
    }

    function testFuzz_healthFactor_MonotonicInCollateral(
        uint256 c1,
        uint256 c2,
        uint256 debt,
        uint256 threshold
    ) public view {
        // More collateral → higher health factor (for same debt & threshold)
        c1 = bound(c1, 0, 1e24);
        c2 = bound(c2, c1, 1e24);
        debt = bound(debt, 1, 1e24);
        threshold = bound(threshold, 1, BPS);

        uint256 hf1 = h.calculateHealthFactorFromBalances(c1, debt, threshold);
        uint256 hf2 = h.calculateHealthFactorFromBalances(c2, debt, threshold);
        assertLe(hf1, hf2, "health factor should be monotonically increasing in collateral");
    }

    function testFuzz_healthFactor_InverselyMonotonicInDebt(
        uint256 collateral,
        uint256 d1,
        uint256 d2,
        uint256 threshold
    ) public view {
        // More debt → lower health factor
        collateral = bound(collateral, 1, 1e24);
        d1 = bound(d1, 1, 1e24);
        d2 = bound(d2, d1, 1e24);
        threshold = bound(threshold, 1, BPS);

        uint256 hf1 = h.calculateHealthFactorFromBalances(collateral, d1, threshold);
        uint256 hf2 = h.calculateHealthFactorFromBalances(collateral, d2, threshold);
        assertGe(hf1, hf2, "health factor should decrease with more debt");
    }

    function testFuzz_healthFactor_MonotonicInThreshold(
        uint256 collateral,
        uint256 debt,
        uint256 t1,
        uint256 t2
    ) public view {
        // Higher liquidation threshold → higher health factor
        collateral = bound(collateral, 1, 1e24);
        debt = bound(debt, 1, 1e24);
        t1 = bound(t1, 0, BPS);
        t2 = bound(t2, t1, BPS);

        uint256 hf1 = h.calculateHealthFactorFromBalances(collateral, debt, t1);
        uint256 hf2 = h.calculateHealthFactorFromBalances(collateral, debt, t2);
        assertLe(hf1, hf2, "health factor should increase with higher threshold");
    }

    function testFuzz_healthFactor_ZeroThreshold(uint256 collateral, uint256 debt) public view {
        // With zero threshold, health factor should be 0 (collateral * 0 / debt = 0)
        collateral = bound(collateral, 1, 1e24);
        debt = bound(debt, 1, 1e24);
        uint256 hf = h.calculateHealthFactorFromBalances(collateral, debt, 0);
        assertEq(hf, 0, "zero threshold should yield zero health factor");
    }

    function testFuzz_healthFactor_EqualCollateralAndDebt(uint256 amount) public view {
        // When collateral == debt and threshold == 100%, HF should be ~1e18 (1.0)
        amount = bound(amount, 1, 1e24);
        uint256 hf = h.calculateHealthFactorFromBalances(amount, amount, BPS);
        // percentMul(amount, 10000) == amount, wadDiv(amount, amount) == WAD
        assertEq(hf, WAD, "equal collateral and debt with 100% threshold should give HF = 1.0");
    }

    function testFuzz_healthFactor_ZeroCollateral(uint256 debt, uint256 threshold) public view {
        // Zero collateral with positive debt → HF should be 0
        debt = bound(debt, 1, 1e24);
        threshold = bound(threshold, 1, BPS);
        uint256 hf = h.calculateHealthFactorFromBalances(0, debt, threshold);
        assertEq(hf, 0, "zero collateral with debt should yield zero health factor");
    }

    // ============================================================
    //           calculateAvailableBorrowsETH
    // ============================================================

    function testFuzz_availableBorrows_ZeroLtv(uint256 collateral, uint256 debt) public view {
        // With 0 LTV, available borrows should be 0 (unless debt is also 0)
        collateral = bound(collateral, 0, 1e24);
        debt = bound(debt, 0, 1e24);
        uint256 avail = h.calculateAvailableBorrowsETH(collateral, debt, 0);
        assertEq(avail, 0, "zero LTV should yield zero available borrows");
    }

    function testFuzz_availableBorrows_ZeroWhenDebtExceedsCapacity(
        uint256 collateral,
        uint256 debt,
        uint256 ltv
    ) public view {
        // When debt >= collateral.percentMul(ltv), available should be 0
        collateral = bound(collateral, 0, 1e24);
        ltv = bound(ltv, 1, BPS);
        // Calculate capacity and make debt exceed it
        // collateral.percentMul(ltv) = (collateral * ltv + 5000) / 10000
        uint256 capacity = (collateral * ltv + 5000) / 10000;
        debt = bound(debt, capacity, capacity + 1e24);

        uint256 avail = h.calculateAvailableBorrowsETH(collateral, debt, ltv);
        assertEq(avail, 0, "available borrows should be 0 when debt exceeds capacity");
    }

    function testFuzz_availableBorrows_MonotonicInCollateral(
        uint256 c1,
        uint256 c2,
        uint256 debt,
        uint256 ltv
    ) public view {
        // More collateral → more available borrows
        c1 = bound(c1, 0, 1e24);
        c2 = bound(c2, c1, 1e24);
        debt = bound(debt, 0, 1e24);
        ltv = bound(ltv, 1, BPS);

        uint256 a1 = h.calculateAvailableBorrowsETH(c1, debt, ltv);
        uint256 a2 = h.calculateAvailableBorrowsETH(c2, debt, ltv);
        assertLe(a1, a2, "available borrows should increase with more collateral");
    }

    function testFuzz_availableBorrows_InverselyMonotonicInDebt(
        uint256 collateral,
        uint256 d1,
        uint256 d2,
        uint256 ltv
    ) public view {
        // More debt → less available borrows
        collateral = bound(collateral, 1, 1e24);
        d1 = bound(d1, 0, 1e24);
        d2 = bound(d2, d1, 1e24);
        ltv = bound(ltv, 1, BPS);

        uint256 a1 = h.calculateAvailableBorrowsETH(collateral, d1, ltv);
        uint256 a2 = h.calculateAvailableBorrowsETH(collateral, d2, ltv);
        assertGe(a1, a2, "available borrows should decrease with more debt");
    }

    function testFuzz_availableBorrows_MonotonicInLtv(
        uint256 collateral,
        uint256 debt,
        uint256 ltv1,
        uint256 ltv2
    ) public view {
        // Higher LTV → more available borrows
        collateral = bound(collateral, 1, 1e24);
        debt = bound(debt, 0, 1e24);
        ltv1 = bound(ltv1, 0, BPS);
        ltv2 = bound(ltv2, ltv1, BPS);

        uint256 a1 = h.calculateAvailableBorrowsETH(collateral, debt, ltv1);
        uint256 a2 = h.calculateAvailableBorrowsETH(collateral, debt, ltv2);
        assertLe(a1, a2, "available borrows should increase with higher LTV");
    }

    function testFuzz_availableBorrows_FullLtv_NoBorrows(uint256 collateral) public view {
        // With 100% LTV and no existing debt, available == collateral
        collateral = bound(collateral, 1, 1e24);
        uint256 avail = h.calculateAvailableBorrowsETH(collateral, 0, BPS);
        assertEq(avail, collateral, "100% LTV with no debt should give available == collateral");
    }

    function testFuzz_availableBorrows_ZeroCollateral(uint256 debt, uint256 ltv) public view {
        // Zero collateral should always give 0 available borrows
        debt = bound(debt, 0, 1e24);
        ltv = bound(ltv, 0, BPS);
        uint256 avail = h.calculateAvailableBorrowsETH(0, debt, ltv);
        assertEq(avail, 0, "zero collateral should always give zero available borrows");
    }

    function testFuzz_availableBorrows_EqualsCapacityMinusDebt(
        uint256 collateral,
        uint256 debt,
        uint256 ltv
    ) public view {
        // When debt < capacity, result should equal capacity - debt
        collateral = bound(collateral, 1, 1e24);
        ltv = bound(ltv, 1, BPS);
        uint256 capacity = (collateral * ltv + 5000) / 10000;
        debt = bound(debt, 0, capacity > 0 ? capacity - 1 : 0);

        uint256 avail = h.calculateAvailableBorrowsETH(collateral, debt, ltv);
        assertEq(avail, capacity - debt, "available borrows should equal capacity minus debt");
    }
}
