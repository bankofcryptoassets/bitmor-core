// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.13 <0.9.0;

import "forge-std/Test.sol";

interface IUserConfigurationHarness {
    function BORROWING_MASK() external pure returns (uint256);
    function setData(uint256 data) external;
    function getData() external view returns (uint256);
    function setBorrowing(uint256 reserveIndex, bool borrowing) external;
    function setUsingAsCollateral(uint256 reserveIndex, bool usingAsCollateral) external;
    function isUsingAsCollateralOrBorrowing(uint256 reserveIndex) external view returns (bool);
    function isBorrowing(uint256 reserveIndex) external view returns (bool);
    function isUsingAsCollateral(uint256 reserveIndex) external view returns (bool);
    function isBorrowingAny() external view returns (bool);
    function isEmpty() external view returns (bool);
}

contract UserConfigurationFuzzTest is Test {
    IUserConfigurationHarness h;

    uint256 BORROWING_MASK_VAL;
    uint256 constant MAX_RESERVE_INDEX = 127;

    function setUp() public {
        h = IUserConfigurationHarness(deployCode("UserConfigurationHarness.sol"));
        BORROWING_MASK_VAL = h.BORROWING_MASK();
    }

    // ============================================================
    //              setBorrowing / isBorrowing round-trip
    // ============================================================

    function testFuzz_setBorrowing_RoundTrip(uint256 reserveIndex) public {
        reserveIndex = bound(reserveIndex, 0, MAX_RESERVE_INDEX);
        h.setData(0);

        h.setBorrowing(reserveIndex, true);
        assertTrue(h.isBorrowing(reserveIndex), "isBorrowing should return true after setting");

        h.setBorrowing(reserveIndex, false);
        assertFalse(h.isBorrowing(reserveIndex), "isBorrowing should return false after clearing");
    }

    function testFuzz_setBorrowing_RevertsAbove127(uint256 reserveIndex) public {
        reserveIndex = bound(reserveIndex, 128, type(uint256).max);
        vm.expectRevert();
        h.setBorrowing(reserveIndex, true);
    }

    // ============================================================
    //          setUsingAsCollateral / isUsingAsCollateral
    // ============================================================

    function testFuzz_setUsingAsCollateral_RoundTrip(uint256 reserveIndex) public {
        reserveIndex = bound(reserveIndex, 0, MAX_RESERVE_INDEX);
        h.setData(0);

        h.setUsingAsCollateral(reserveIndex, true);
        assertTrue(
            h.isUsingAsCollateral(reserveIndex),
            "isUsingAsCollateral should return true after setting"
        );

        h.setUsingAsCollateral(reserveIndex, false);
        assertFalse(
            h.isUsingAsCollateral(reserveIndex),
            "isUsingAsCollateral should return false after clearing"
        );
    }

    function testFuzz_setUsingAsCollateral_RevertsAbove127(uint256 reserveIndex) public {
        reserveIndex = bound(reserveIndex, 128, type(uint256).max);
        vm.expectRevert();
        h.setUsingAsCollateral(reserveIndex, true);
    }

    // ============================================================
    //            isUsingAsCollateralOrBorrowing
    // ============================================================

    function testFuzz_isUsingAsCollateralOrBorrowing_WhenBothSet(uint256 reserveIndex) public {
        reserveIndex = bound(reserveIndex, 0, MAX_RESERVE_INDEX);
        h.setData(0);

        h.setBorrowing(reserveIndex, true);
        h.setUsingAsCollateral(reserveIndex, true);
        assertTrue(
            h.isUsingAsCollateralOrBorrowing(reserveIndex),
            "should return true when both borrowing and collateral set"
        );
    }

    function testFuzz_isUsingAsCollateralOrBorrowing_WhenOnlyBorrowing(uint256 reserveIndex) public {
        reserveIndex = bound(reserveIndex, 0, MAX_RESERVE_INDEX);
        h.setData(0);

        h.setBorrowing(reserveIndex, true);
        assertTrue(
            h.isUsingAsCollateralOrBorrowing(reserveIndex),
            "should return true when only borrowing set"
        );
    }

    function testFuzz_isUsingAsCollateralOrBorrowing_WhenOnlyCollateral(uint256 reserveIndex)
        public
    {
        reserveIndex = bound(reserveIndex, 0, MAX_RESERVE_INDEX);
        h.setData(0);

        h.setUsingAsCollateral(reserveIndex, true);
        assertTrue(
            h.isUsingAsCollateralOrBorrowing(reserveIndex),
            "should return true when only collateral set"
        );
    }

    function testFuzz_isUsingAsCollateralOrBorrowing_WhenNeitherSet(uint256 reserveIndex) public {
        reserveIndex = bound(reserveIndex, 0, MAX_RESERVE_INDEX);
        h.setData(0);

        assertFalse(
            h.isUsingAsCollateralOrBorrowing(reserveIndex),
            "should return false when neither borrowing nor collateral set"
        );
    }

    // ============================================================
    //        Non-interference: borrowing does not affect collateral
    // ============================================================

    function testFuzz_nonInterference_BorrowingDoesntAffectCollateral(
        uint256 reserveIndex
    ) public {
        reserveIndex = bound(reserveIndex, 0, MAX_RESERVE_INDEX);
        h.setData(0);

        h.setUsingAsCollateral(reserveIndex, true);
        h.setBorrowing(reserveIndex, true);

        assertTrue(
            h.isUsingAsCollateral(reserveIndex),
            "setting borrowing should not clear collateral"
        );

        h.setBorrowing(reserveIndex, false);
        assertTrue(
            h.isUsingAsCollateral(reserveIndex),
            "clearing borrowing should not clear collateral"
        );
    }

    function testFuzz_nonInterference_CollateralDoesntAffectBorrowing(
        uint256 reserveIndex
    ) public {
        reserveIndex = bound(reserveIndex, 0, MAX_RESERVE_INDEX);
        h.setData(0);

        h.setBorrowing(reserveIndex, true);
        h.setUsingAsCollateral(reserveIndex, true);

        assertTrue(
            h.isBorrowing(reserveIndex),
            "setting collateral should not clear borrowing"
        );

        h.setUsingAsCollateral(reserveIndex, false);
        assertTrue(
            h.isBorrowing(reserveIndex),
            "clearing collateral should not clear borrowing"
        );
    }

    // ============================================================
    //        Non-interference: different reserves
    // ============================================================

    function testFuzz_nonInterference_DifferentReserves(
        uint256 indexA,
        uint256 indexB
    ) public {
        indexA = bound(indexA, 0, MAX_RESERVE_INDEX);
        indexB = bound(indexB, 0, MAX_RESERVE_INDEX);
        vm.assume(indexA != indexB);

        h.setData(0);
        h.setBorrowing(indexA, true);
        h.setUsingAsCollateral(indexB, true);

        assertTrue(h.isBorrowing(indexA), "borrowing at indexA should be set");
        assertFalse(h.isBorrowing(indexB), "borrowing at indexB should not be set");
        assertFalse(h.isUsingAsCollateral(indexA), "collateral at indexA should not be set");
        assertTrue(h.isUsingAsCollateral(indexB), "collateral at indexB should be set");
    }

    // ============================================================
    //                    isBorrowingAny
    // ============================================================

    function testFuzz_isBorrowingAny_TrueWhenBorrowingSet(uint256 reserveIndex) public {
        reserveIndex = bound(reserveIndex, 0, MAX_RESERVE_INDEX);
        h.setData(0);

        h.setBorrowing(reserveIndex, true);
        assertTrue(h.isBorrowingAny(), "isBorrowingAny should return true when any borrowing set");
    }

    function testFuzz_isBorrowingAny_FalseWhenOnlyCollateral(uint256 reserveIndex) public {
        reserveIndex = bound(reserveIndex, 0, MAX_RESERVE_INDEX);
        h.setData(0);

        h.setUsingAsCollateral(reserveIndex, true);
        assertFalse(
            h.isBorrowingAny(),
            "isBorrowingAny should return false when only collateral set"
        );
    }

    // ============================================================
    //                       isEmpty
    // ============================================================

    function testFuzz_isEmpty_TrueWhenCleared(uint256 reserveIndex) public {
        reserveIndex = bound(reserveIndex, 0, MAX_RESERVE_INDEX);
        h.setData(0);

        assertTrue(h.isEmpty(), "isEmpty should return true for fresh state");

        h.setBorrowing(reserveIndex, true);
        assertFalse(h.isEmpty(), "isEmpty should return false after setting borrowing");

        h.setBorrowing(reserveIndex, false);
        assertTrue(h.isEmpty(), "isEmpty should return true after clearing all");
    }

    function testFuzz_isEmpty_FalseWhenAnyBitSet(uint256 reserveIndex, bool borrowing) public {
        reserveIndex = bound(reserveIndex, 0, MAX_RESERVE_INDEX);
        h.setData(0);

        if (borrowing) {
            h.setBorrowing(reserveIndex, true);
        } else {
            h.setUsingAsCollateral(reserveIndex, true);
        }

        assertFalse(h.isEmpty(), "isEmpty should return false when any bit is set");
    }

    // ============================================================
    //            Bit position verification
    // ============================================================

    function testFuzz_borrowingBitPosition(uint256 reserveIndex) public {
        // Borrowing bit for reserveIndex is at position (reserveIndex * 2)
        reserveIndex = bound(reserveIndex, 0, MAX_RESERVE_INDEX);
        h.setData(0);

        h.setBorrowing(reserveIndex, true);
        uint256 expected = uint256(1) << (reserveIndex * 2);
        assertEq(h.getData(), expected, "borrowing bit should be at position reserveIndex*2");
    }

    function testFuzz_collateralBitPosition(uint256 reserveIndex) public {
        // Collateral bit for reserveIndex is at position (reserveIndex * 2 + 1)
        reserveIndex = bound(reserveIndex, 0, MAX_RESERVE_INDEX);
        h.setData(0);

        h.setUsingAsCollateral(reserveIndex, true);
        uint256 expected = uint256(1) << (reserveIndex * 2 + 1);
        assertEq(
            h.getData(),
            expected,
            "collateral bit should be at position reserveIndex*2+1"
        );
    }

    // ============================================================
    //            Idempotency
    // ============================================================

    function testFuzz_setBorrowing_Idempotent(uint256 reserveIndex) public {
        reserveIndex = bound(reserveIndex, 0, MAX_RESERVE_INDEX);
        h.setData(0);

        h.setBorrowing(reserveIndex, true);
        uint256 dataBefore = h.getData();
        h.setBorrowing(reserveIndex, true);
        assertEq(h.getData(), dataBefore, "setting borrowing true twice should be idempotent");
    }
}
