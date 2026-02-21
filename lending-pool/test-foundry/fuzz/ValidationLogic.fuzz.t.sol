// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.13 <0.9.0;

import "forge-std/Test.sol";

interface IValidationLogicHarness {
    function setCollateralReserveActive(bool active) external;
    function setPrincipalReserveActive(bool active) external;
    function setCollateralLiquidationThreshold(uint256 threshold) external;
    function setCollateralReserveId(uint8 id) external;
    function setUserUsingAsCollateral(uint256 reserveIndex, bool usingAsCollateral) external;

    function validateLiquidationCall(
        uint256 typeOfLiquidation,
        uint256 userHealthFactor,
        uint256 userStableDebt,
        uint256 userVariableDebt
    ) external view returns (uint256, string memory);

    function validateMicroLiquidationCall(
        uint256 typeOfLiquidation,
        uint256 userStableDebt,
        uint256 userVariableDebt
    ) external view returns (uint256, string memory);
}

contract ValidationLogicFuzzTest is Test {
    IValidationLogicHarness h;

    // Error codes from Errors.CollateralManagerErrors enum
    uint256 constant NO_ERROR = 0;
    uint256 constant COLLATERAL_CANNOT_BE_LIQUIDATED = 2;
    uint256 constant CURRRENCY_NOT_BORROWED = 3;
    uint256 constant NO_ACTIVE_RESERVE = 6;
    uint256 constant CANNOT_MICRO_LIQUIDATE = 10;
    uint256 constant CANNOT_FULL_LIQUIDATE = 11;

    uint8 constant RESERVE_ID = 5;

    function setUp() public {
        h = IValidationLogicHarness(deployCode("ValidationLogicHarness.sol"));
    }

    /// @dev Configure harness for a valid liquidation scenario
    function _setupValidState() internal {
        h.setCollateralReserveActive(true);
        h.setPrincipalReserveActive(true);
        h.setCollateralLiquidationThreshold(8000); // 80%
        h.setCollateralReserveId(RESERVE_ID);
        h.setUserUsingAsCollateral(RESERVE_ID, true);
    }

    // ============================================================
    //              validateLiquidationCall
    // ============================================================

    function testFuzz_liquidationCall_SucceedsWhenValid(
        uint256 hf,
        uint256 stableDebt,
        uint256 variableDebt
    ) public {
        // Valid full liquidation: type=1, active reserves, enabled collateral, has debt
        hf = bound(hf, 0, type(uint256).max);
        stableDebt = bound(stableDebt, 0, 1e24);
        variableDebt = bound(variableDebt, 0, 1e24);
        vm.assume(stableDebt > 0 || variableDebt > 0);

        _setupValidState();

        (uint256 errCode, ) = h.validateLiquidationCall(
            1,
            hf,
            stableDebt,
            variableDebt
        );
        assertEq(errCode, NO_ERROR, "valid full liquidation should return NO_ERROR");
    }

    function testFuzz_liquidationCall_FailsWhenCollateralInactive(
        uint256 hf,
        uint256 variableDebt
    ) public {
        hf = bound(hf, 0, type(uint256).max);
        variableDebt = bound(variableDebt, 1, 1e24);

        _setupValidState();
        h.setCollateralReserveActive(false);

        (uint256 errCode, ) = h.validateLiquidationCall(1, hf, 0, variableDebt);
        assertEq(
            errCode,
            NO_ACTIVE_RESERVE,
            "inactive collateral reserve should return NO_ACTIVE_RESERVE"
        );
    }

    function testFuzz_liquidationCall_FailsWhenPrincipalInactive(
        uint256 hf,
        uint256 variableDebt
    ) public {
        hf = bound(hf, 0, type(uint256).max);
        variableDebt = bound(variableDebt, 1, 1e24);

        _setupValidState();
        h.setPrincipalReserveActive(false);

        (uint256 errCode, ) = h.validateLiquidationCall(1, hf, 0, variableDebt);
        assertEq(
            errCode,
            NO_ACTIVE_RESERVE,
            "inactive principal reserve should return NO_ACTIVE_RESERVE"
        );
    }

    function testFuzz_liquidationCall_FailsWhenTypeNotOne(
        uint256 liquidationType,
        uint256 hf,
        uint256 variableDebt
    ) public {
        // Any type != 1 should fail
        liquidationType = bound(liquidationType, 0, 100);
        vm.assume(liquidationType != 1);
        hf = bound(hf, 0, type(uint256).max);
        variableDebt = bound(variableDebt, 1, 1e24);

        _setupValidState();

        (uint256 errCode, ) = h.validateLiquidationCall(
            liquidationType,
            hf,
            0,
            variableDebt
        );
        assertEq(
            errCode,
            CANNOT_FULL_LIQUIDATE,
            "type != 1 should return CANNOT_FULL_LIQUIDATE"
        );
    }

    function testFuzz_liquidationCall_FailsWhenCollateralNotEnabled(
        uint256 hf,
        uint256 variableDebt
    ) public {
        hf = bound(hf, 0, type(uint256).max);
        variableDebt = bound(variableDebt, 1, 1e24);

        _setupValidState();
        // Disable collateral by setting threshold to 0
        h.setCollateralLiquidationThreshold(0);

        (uint256 errCode, ) = h.validateLiquidationCall(1, hf, 0, variableDebt);
        assertEq(
            errCode,
            COLLATERAL_CANNOT_BE_LIQUIDATED,
            "zero threshold should return COLLATERAL_CANNOT_BE_LIQUIDATED"
        );
    }

    function testFuzz_liquidationCall_FailsWhenCollateralFlagOff(
        uint256 hf,
        uint256 variableDebt
    ) public {
        hf = bound(hf, 0, type(uint256).max);
        variableDebt = bound(variableDebt, 1, 1e24);

        _setupValidState();
        // Disable the user's collateral flag
        h.setUserUsingAsCollateral(RESERVE_ID, false);

        (uint256 errCode, ) = h.validateLiquidationCall(1, hf, 0, variableDebt);
        assertEq(
            errCode,
            COLLATERAL_CANNOT_BE_LIQUIDATED,
            "collateral flag off should return COLLATERAL_CANNOT_BE_LIQUIDATED"
        );
    }

    function testFuzz_liquidationCall_FailsWhenNoDebt(uint256 hf) public {
        hf = bound(hf, 0, type(uint256).max);

        _setupValidState();

        (uint256 errCode, ) = h.validateLiquidationCall(1, hf, 0, 0);
        assertEq(
            errCode,
            CURRRENCY_NOT_BORROWED,
            "zero debt should return CURRRENCY_NOT_BORROWED"
        );
    }

    // ============================================================
    //              validateMicroLiquidationCall
    // ============================================================

    function testFuzz_microLiquidationCall_SucceedsWhenValid(
        uint256 stableDebt,
        uint256 variableDebt
    ) public {
        // Valid micro liquidation: type=2, active reserves, enabled collateral, has debt
        stableDebt = bound(stableDebt, 0, 1e24);
        variableDebt = bound(variableDebt, 0, 1e24);
        vm.assume(stableDebt > 0 || variableDebt > 0);

        _setupValidState();

        (uint256 errCode, ) = h.validateMicroLiquidationCall(
            2,
            stableDebt,
            variableDebt
        );
        assertEq(
            errCode,
            NO_ERROR,
            "valid micro liquidation should return NO_ERROR"
        );
    }

    function testFuzz_microLiquidationCall_FailsWhenTypeNotTwo(
        uint256 liquidationType,
        uint256 variableDebt
    ) public {
        liquidationType = bound(liquidationType, 0, 100);
        vm.assume(liquidationType != 2);
        variableDebt = bound(variableDebt, 1, 1e24);

        _setupValidState();

        (uint256 errCode, ) = h.validateMicroLiquidationCall(
            liquidationType,
            0,
            variableDebt
        );
        assertEq(
            errCode,
            CANNOT_MICRO_LIQUIDATE,
            "type != 2 should return CANNOT_MICRO_LIQUIDATE"
        );
    }

    function testFuzz_microLiquidationCall_FailsWhenReserveInactive(
        uint256 variableDebt
    ) public {
        variableDebt = bound(variableDebt, 1, 1e24);

        _setupValidState();
        h.setCollateralReserveActive(false);

        (uint256 errCode, ) = h.validateMicroLiquidationCall(
            2,
            0,
            variableDebt
        );
        assertEq(
            errCode,
            NO_ACTIVE_RESERVE,
            "inactive reserve should return NO_ACTIVE_RESERVE"
        );
    }

    function testFuzz_microLiquidationCall_FailsWhenNoDebt() public {
        _setupValidState();

        (uint256 errCode, ) = h.validateMicroLiquidationCall(2, 0, 0);
        assertEq(
            errCode,
            CURRRENCY_NOT_BORROWED,
            "zero debt should return CURRRENCY_NOT_BORROWED"
        );
    }

    function testFuzz_microLiquidationCall_FailsWhenCollateralNotEnabled(
        uint256 variableDebt
    ) public {
        variableDebt = bound(variableDebt, 1, 1e24);

        _setupValidState();
        h.setCollateralLiquidationThreshold(0);

        (uint256 errCode, ) = h.validateMicroLiquidationCall(
            2,
            0,
            variableDebt
        );
        assertEq(
            errCode,
            COLLATERAL_CANNOT_BE_LIQUIDATED,
            "disabled collateral should return COLLATERAL_CANNOT_BE_LIQUIDATED"
        );
    }
}
