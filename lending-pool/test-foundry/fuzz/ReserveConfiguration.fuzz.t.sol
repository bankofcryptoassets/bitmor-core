// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.13 <0.9.0;

import "forge-std/Test.sol";

interface IReserveConfigurationHarness {
    function MAX_VALID_LTV() external pure returns (uint256);
    function MAX_VALID_LIQUIDATION_THRESHOLD() external pure returns (uint256);
    function MAX_VALID_LIQUIDATION_BONUS() external pure returns (uint256);
    function MAX_VALID_DECIMALS() external pure returns (uint256);
    function MAX_VALID_RESERVE_FACTOR() external pure returns (uint256);

    function setData(uint256 data) external;
    function getData() external view returns (uint256);

    function setLtv(uint256 ltv) external;
    function setLiquidationThreshold(uint256 threshold) external;
    function setLiquidationBonus(uint256 bonus) external;
    function setDecimals(uint256 decimals) external;
    function setActive(bool active) external;
    function setFrozen(bool frozen) external;
    function setBorrowingEnabled(bool enabled) external;
    function setStableRateBorrowingEnabled(bool enabled) external;
    function setReserveFactor(uint256 reserveFactor) external;

    function getLtv() external view returns (uint256);
    function getLiquidationThreshold() external view returns (uint256);
    function getLiquidationBonus() external view returns (uint256);
    function getDecimals() external view returns (uint256);
    function getActive() external view returns (bool);
    function getReserveFactor() external view returns (uint256);

    function getFlags() external view returns (bool, bool, bool, bool);
    function getParams() external view returns (uint256, uint256, uint256, uint256, uint256);
    function getParamsMemory() external view returns (uint256, uint256, uint256, uint256, uint256);
    function getFlagsMemory() external view returns (bool, bool, bool, bool);
}

contract ReserveConfigurationFuzzTest is Test {
    IReserveConfigurationHarness h;

    uint256 MAX_LTV;
    uint256 MAX_LIQ_THRESHOLD;
    uint256 MAX_LIQ_BONUS;
    uint256 MAX_DECIMALS;
    uint256 MAX_RESERVE_FACTOR;

    function setUp() public {
        h = IReserveConfigurationHarness(deployCode("ReserveConfigurationHarness.sol"));
        MAX_LTV = h.MAX_VALID_LTV();
        MAX_LIQ_THRESHOLD = h.MAX_VALID_LIQUIDATION_THRESHOLD();
        MAX_LIQ_BONUS = h.MAX_VALID_LIQUIDATION_BONUS();
        MAX_DECIMALS = h.MAX_VALID_DECIMALS();
        MAX_RESERVE_FACTOR = h.MAX_VALID_RESERVE_FACTOR();
    }

    // ============================================================
    //                    LTV round-trip
    // ============================================================

    function testFuzz_setGetLtv_RoundTrip(uint256 ltv) public {
        ltv = bound(ltv, 0, MAX_LTV);
        h.setData(0);
        h.setLtv(ltv);
        assertEq(h.getLtv(), ltv, "LTV round-trip failed");
    }

    function testFuzz_setLtv_RevertsAboveMax(uint256 ltv) public {
        ltv = bound(ltv, MAX_LTV + 1, type(uint256).max);
        vm.expectRevert();
        h.setLtv(ltv);
    }

    // ============================================================
    //               Liquidation Threshold round-trip
    // ============================================================

    function testFuzz_setGetLiquidationThreshold_RoundTrip(uint256 threshold) public {
        threshold = bound(threshold, 0, MAX_LIQ_THRESHOLD);
        h.setData(0);
        h.setLiquidationThreshold(threshold);
        assertEq(h.getLiquidationThreshold(), threshold, "LiquidationThreshold round-trip failed");
    }

    function testFuzz_setLiquidationThreshold_RevertsAboveMax(uint256 threshold) public {
        threshold = bound(threshold, MAX_LIQ_THRESHOLD + 1, type(uint256).max);
        vm.expectRevert();
        h.setLiquidationThreshold(threshold);
    }

    // ============================================================
    //               Liquidation Bonus round-trip
    // ============================================================

    function testFuzz_setGetLiquidationBonus_RoundTrip(uint256 bonus) public {
        bonus = bound(bonus, 0, MAX_LIQ_BONUS);
        h.setData(0);
        h.setLiquidationBonus(bonus);
        assertEq(h.getLiquidationBonus(), bonus, "LiquidationBonus round-trip failed");
    }

    function testFuzz_setLiquidationBonus_RevertsAboveMax(uint256 bonus) public {
        bonus = bound(bonus, MAX_LIQ_BONUS + 1, type(uint256).max);
        vm.expectRevert();
        h.setLiquidationBonus(bonus);
    }

    // ============================================================
    //                    Decimals round-trip
    // ============================================================

    function testFuzz_setGetDecimals_RoundTrip(uint256 decimals) public {
        decimals = bound(decimals, 0, MAX_DECIMALS);
        h.setData(0);
        h.setDecimals(decimals);
        assertEq(h.getDecimals(), decimals, "Decimals round-trip failed");
    }

    function testFuzz_setDecimals_RevertsAboveMax(uint256 decimals) public {
        decimals = bound(decimals, MAX_DECIMALS + 1, type(uint256).max);
        vm.expectRevert();
        h.setDecimals(decimals);
    }

    // ============================================================
    //                    Active round-trip
    // ============================================================

    function testFuzz_setGetActive_RoundTrip(bool active) public {
        h.setData(0);
        h.setActive(active);
        assertEq(h.getActive(), active, "Active round-trip failed");
    }

    // ============================================================
    //                  Reserve Factor round-trip
    // ============================================================

    function testFuzz_setGetReserveFactor_RoundTrip(uint256 rf) public {
        rf = bound(rf, 0, MAX_RESERVE_FACTOR);
        h.setData(0);
        h.setReserveFactor(rf);
        assertEq(h.getReserveFactor(), rf, "ReserveFactor round-trip failed");
    }

    function testFuzz_setReserveFactor_RevertsAboveMax(uint256 rf) public {
        rf = bound(rf, MAX_RESERVE_FACTOR + 1, type(uint256).max);
        vm.expectRevert();
        h.setReserveFactor(rf);
    }

    // ============================================================
    //               Field non-interference
    // ============================================================

    function testFuzz_fieldNonInterference(
        uint256 ltv,
        uint256 liqThreshold,
        uint256 liqBonus,
        uint256 decimals,
        uint256 reserveFactor,
        bool active,
        bool frozen,
        bool borrowing,
        bool stableBorrowing
    ) public {
        ltv = bound(ltv, 0, MAX_LTV);
        liqThreshold = bound(liqThreshold, 0, MAX_LIQ_THRESHOLD);
        liqBonus = bound(liqBonus, 0, MAX_LIQ_BONUS);
        decimals = bound(decimals, 0, MAX_DECIMALS);
        reserveFactor = bound(reserveFactor, 0, MAX_RESERVE_FACTOR);

        h.setData(0);
        h.setLtv(ltv);
        h.setLiquidationThreshold(liqThreshold);
        h.setLiquidationBonus(liqBonus);
        h.setDecimals(decimals);
        h.setActive(active);
        h.setFrozen(frozen);
        h.setBorrowingEnabled(borrowing);
        h.setStableRateBorrowingEnabled(stableBorrowing);
        h.setReserveFactor(reserveFactor);

        assertEq(h.getLtv(), ltv, "LTV corrupted by other fields");
        assertEq(h.getLiquidationThreshold(), liqThreshold, "LiqThreshold corrupted by other fields");
        assertEq(h.getLiquidationBonus(), liqBonus, "LiqBonus corrupted by other fields");
        assertEq(h.getDecimals(), decimals, "Decimals corrupted by other fields");
        assertEq(h.getActive(), active, "Active corrupted by other fields");
        assertEq(h.getReserveFactor(), reserveFactor, "ReserveFactor corrupted by other fields");
    }

    // ============================================================
    //               getParams consistency
    // ============================================================

    function testFuzz_getParams_ConsistentWithIndividualGetters(
        uint256 ltv,
        uint256 liqThreshold,
        uint256 liqBonus,
        uint256 decimals,
        uint256 reserveFactor
    ) public {
        ltv = bound(ltv, 0, MAX_LTV);
        liqThreshold = bound(liqThreshold, 0, MAX_LIQ_THRESHOLD);
        liqBonus = bound(liqBonus, 0, MAX_LIQ_BONUS);
        decimals = bound(decimals, 0, MAX_DECIMALS);
        reserveFactor = bound(reserveFactor, 0, MAX_RESERVE_FACTOR);

        h.setData(0);
        h.setLtv(ltv);
        h.setLiquidationThreshold(liqThreshold);
        h.setLiquidationBonus(liqBonus);
        h.setDecimals(decimals);
        h.setReserveFactor(reserveFactor);

        (uint256 pLtv, uint256 pLiqT, uint256 pLiqB, uint256 pDec, uint256 pRf) = h.getParams();

        assertEq(pLtv, h.getLtv(), "getParams LTV mismatch");
        assertEq(pLiqT, h.getLiquidationThreshold(), "getParams LiqThreshold mismatch");
        assertEq(pLiqB, h.getLiquidationBonus(), "getParams LiqBonus mismatch");
        assertEq(pDec, h.getDecimals(), "getParams Decimals mismatch");
        assertEq(pRf, h.getReserveFactor(), "getParams ReserveFactor mismatch");
    }

    // ============================================================
    //               getParamsMemory == getParams
    // ============================================================

    function testFuzz_getParamsMemory_EqualsGetParams(
        uint256 ltv,
        uint256 liqThreshold,
        uint256 liqBonus,
        uint256 decimals,
        uint256 reserveFactor
    ) public {
        ltv = bound(ltv, 0, MAX_LTV);
        liqThreshold = bound(liqThreshold, 0, MAX_LIQ_THRESHOLD);
        liqBonus = bound(liqBonus, 0, MAX_LIQ_BONUS);
        decimals = bound(decimals, 0, MAX_DECIMALS);
        reserveFactor = bound(reserveFactor, 0, MAX_RESERVE_FACTOR);

        h.setData(0);
        h.setLtv(ltv);
        h.setLiquidationThreshold(liqThreshold);
        h.setLiquidationBonus(liqBonus);
        h.setDecimals(decimals);
        h.setReserveFactor(reserveFactor);

        (uint256 pLtv, uint256 pLiqT, uint256 pLiqB, uint256 pDec, uint256 pRf) = h.getParams();
        (uint256 mLtv, uint256 mLiqT, uint256 mLiqB, uint256 mDec, uint256 mRf) = h.getParamsMemory();

        assertEq(mLtv, pLtv, "getParamsMemory LTV != getParams LTV");
        assertEq(mLiqT, pLiqT, "getParamsMemory LiqThreshold != getParams LiqThreshold");
        assertEq(mLiqB, pLiqB, "getParamsMemory LiqBonus != getParams LiqBonus");
        assertEq(mDec, pDec, "getParamsMemory Decimals != getParams Decimals");
        assertEq(mRf, pRf, "getParamsMemory ReserveFactor != getParams ReserveFactor");
    }

    // ============================================================
    //               getFlags consistency
    // ============================================================

    function testFuzz_getFlags_ConsistentWithSetters(
        bool active,
        bool frozen,
        bool borrowing,
        bool stableBorrowing
    ) public {
        h.setData(0);
        h.setActive(active);
        h.setFrozen(frozen);
        h.setBorrowingEnabled(borrowing);
        h.setStableRateBorrowingEnabled(stableBorrowing);

        (bool fActive, bool fFrozen, bool fBorrowing, bool fStable) = h.getFlags();

        assertEq(fActive, active, "getFlags active mismatch");
        assertEq(fFrozen, frozen, "getFlags frozen mismatch");
        assertEq(fBorrowing, borrowing, "getFlags borrowing mismatch");
        assertEq(fStable, stableBorrowing, "getFlags stableBorrowing mismatch");
    }

    // ============================================================
    //               getFlagsMemory == getFlags
    // ============================================================

    function testFuzz_getFlagsMemory_EqualsGetFlags(
        bool active,
        bool frozen,
        bool borrowing,
        bool stableBorrowing
    ) public {
        h.setData(0);
        h.setActive(active);
        h.setFrozen(frozen);
        h.setBorrowingEnabled(borrowing);
        h.setStableRateBorrowingEnabled(stableBorrowing);

        (bool fA, bool fF, bool fB, bool fS) = h.getFlags();
        (bool mA, bool mF, bool mB, bool mS) = h.getFlagsMemory();

        assertEq(mA, fA, "getFlagsMemory active != getFlags active");
        assertEq(mF, fF, "getFlagsMemory frozen != getFlags frozen");
        assertEq(mB, fB, "getFlagsMemory borrowing != getFlags borrowing");
        assertEq(mS, fS, "getFlagsMemory stableBorrowing != getFlags stableBorrowing");
    }

    // ============================================================
    //           Idempotency: setting same value twice
    // ============================================================

    function testFuzz_setLtv_Idempotent(uint256 ltv) public {
        ltv = bound(ltv, 0, MAX_LTV);
        h.setData(0);
        h.setLtv(ltv);
        uint256 dataBefore = h.getData();
        h.setLtv(ltv);
        assertEq(h.getData(), dataBefore, "setting same LTV should be idempotent");
    }

    // ============================================================
    //        Setting one field preserves another (pairwise)
    // ============================================================

    function testFuzz_setLtv_PreservesLiqThreshold(uint256 ltv, uint256 threshold) public {
        ltv = bound(ltv, 0, MAX_LTV);
        threshold = bound(threshold, 0, MAX_LIQ_THRESHOLD);
        h.setData(0);
        h.setLiquidationThreshold(threshold);
        h.setLtv(ltv);
        assertEq(
            h.getLiquidationThreshold(),
            threshold,
            "setting LTV should not corrupt LiqThreshold"
        );
    }

    function testFuzz_setReserveFactor_PreservesDecimals(uint256 rf, uint256 decimals) public {
        rf = bound(rf, 0, MAX_RESERVE_FACTOR);
        decimals = bound(decimals, 0, MAX_DECIMALS);
        h.setData(0);
        h.setDecimals(decimals);
        h.setReserveFactor(rf);
        assertEq(h.getDecimals(), decimals, "setting ReserveFactor should not corrupt Decimals");
    }

    // ============================================================
    //        Raw bitmap: verify bit positions
    // ============================================================

    function testFuzz_ltvBitsPosition(uint256 ltv) public {
        // LTV occupies bits 0-15 → raw data should equal ltv when only LTV is set
        ltv = bound(ltv, 0, MAX_LTV);
        h.setData(0);
        h.setLtv(ltv);
        assertEq(h.getData(), ltv, "LTV should occupy bits 0-15 of raw data");
    }

    function testFuzz_liqThresholdBitsPosition(uint256 threshold) public {
        // LiqThreshold occupies bits 16-31 → raw data should equal (threshold << 16)
        threshold = bound(threshold, 0, MAX_LIQ_THRESHOLD);
        h.setData(0);
        h.setLiquidationThreshold(threshold);
        assertEq(
            h.getData(),
            threshold << 16,
            "LiqThreshold should occupy bits 16-31 of raw data"
        );
    }

    function testFuzz_activeBitPosition(bool active) public {
        // Active is bit 56
        h.setData(0);
        h.setActive(active);
        if (active) {
            assertEq(h.getData(), 1 << 56, "Active true should set bit 56");
        } else {
            assertEq(h.getData(), 0, "Active false should leave data as 0");
        }
    }
}
