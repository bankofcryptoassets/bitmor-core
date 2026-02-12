// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.13 <0.9.0;

import "forge-std/Test.sol";

interface IProtocolFeeHarness {
    function calculateProtocolFee(
        uint256 maxCollateralToLiquidate,
        uint256 liquidationBonusPercent,
        uint256 liquidationFee
    ) external pure returns (uint256 protocolFee, uint256 liquidatorCollateral);
}

contract ProtocolFeeFuzzTest is Test {
    IProtocolFeeHarness h;

    uint256 constant BPS = 10000;

    function setUp() public {
        h = IProtocolFeeHarness(deployCode("ProtocolFeeHarness.sol"));
    }

    // ============================================================
    //              calculateProtocolFee
    // ============================================================

    function testFuzz_protocolFee_ZeroFeeGivesFullToLiquidator(
        uint256 maxCollateral,
        uint256 bonusPercent
    ) public view {
        // When liquidationFee == 0, liquidator gets everything
        maxCollateral = bound(maxCollateral, 0, 1e24);
        bonusPercent = bound(bonusPercent, BPS, 2 * BPS); // 100% - 200%

        (uint256 fee, uint256 liquidatorCol) = h.calculateProtocolFee(
            maxCollateral,
            bonusPercent,
            0
        );

        assertEq(fee, 0, "zero fee should give zero protocol fee");
        assertEq(
            liquidatorCol,
            maxCollateral,
            "zero fee should give full collateral to liquidator"
        );
    }

    function testFuzz_protocolFee_SumEqualsTotal(
        uint256 maxCollateral,
        uint256 bonusPercent,
        uint256 liquidationFee
    ) public view {
        // protocolFee + liquidatorCollateral == maxCollateralToLiquidate
        maxCollateral = bound(maxCollateral, 1, 1e24);
        bonusPercent = bound(bonusPercent, BPS + 1, 2 * BPS); // > 100% to have bonus
        liquidationFee = bound(liquidationFee, 1, BPS);

        (uint256 fee, uint256 liquidatorCol) = h.calculateProtocolFee(
            maxCollateral,
            bonusPercent,
            liquidationFee
        );

        assertEq(
            fee + liquidatorCol,
            maxCollateral,
            "protocol fee + liquidator collateral must equal total"
        );
    }

    function testFuzz_protocolFee_MonotonicInFeePercent(
        uint256 maxCollateral,
        uint256 bonusPercent,
        uint256 fee1,
        uint256 fee2
    ) public view {
        // Higher liquidation fee percentage → higher protocol fee
        maxCollateral = bound(maxCollateral, 1e6, 1e24);
        bonusPercent = bound(bonusPercent, BPS + 100, 2 * BPS);
        fee1 = bound(fee1, 1, BPS);
        fee2 = bound(fee2, fee1, BPS);

        (uint256 protocolFee1, ) = h.calculateProtocolFee(
            maxCollateral,
            bonusPercent,
            fee1
        );
        (uint256 protocolFee2, ) = h.calculateProtocolFee(
            maxCollateral,
            bonusPercent,
            fee2
        );

        assertLe(
            protocolFee1,
            protocolFee2,
            "higher fee percent should give higher protocol fee"
        );
    }

    function testFuzz_protocolFee_MonotonicInBonusPercent(
        uint256 maxCollateral,
        uint256 bonus1,
        uint256 bonus2,
        uint256 liquidationFee
    ) public view {
        // Higher bonus → more bonus collateral → higher protocol fee
        maxCollateral = bound(maxCollateral, 1e6, 1e24);
        bonus1 = bound(bonus1, BPS + 1, 2 * BPS);
        bonus2 = bound(bonus2, bonus1, 2 * BPS);
        liquidationFee = bound(liquidationFee, 1, BPS);

        (uint256 protocolFee1, ) = h.calculateProtocolFee(
            maxCollateral,
            bonus1,
            liquidationFee
        );
        (uint256 protocolFee2, ) = h.calculateProtocolFee(
            maxCollateral,
            bonus2,
            liquidationFee
        );

        assertLe(
            protocolFee1,
            protocolFee2 + 1,
            "higher bonus should give higher protocol fee"
        );
    }

    function testFuzz_protocolFee_NoBonusMeansNoFee(
        uint256 maxCollateral,
        uint256 liquidationFee
    ) public view {
        // When liquidationBonusPercent == 10000 (100%), baseCollateral == maxCollateral,
        // bonusCollateral == 0, so protocolFee == 0
        maxCollateral = bound(maxCollateral, 1, 1e24);
        liquidationFee = bound(liquidationFee, 1, BPS);

        (uint256 fee, uint256 liquidatorCol) = h.calculateProtocolFee(
            maxCollateral,
            BPS,
            liquidationFee
        );

        assertEq(
            fee,
            0,
            "no bonus (100% bonus percent) should give zero protocol fee"
        );
        assertEq(
            liquidatorCol,
            maxCollateral,
            "no bonus should give full collateral to liquidator"
        );
    }

    function testFuzz_protocolFee_FeeLteBonusCollateral(
        uint256 maxCollateral,
        uint256 bonusPercent,
        uint256 liquidationFee
    ) public view {
        // Protocol fee should never exceed the bonus collateral
        maxCollateral = bound(maxCollateral, 1, 1e24);
        bonusPercent = bound(bonusPercent, BPS + 1, 2 * BPS);
        liquidationFee = bound(liquidationFee, 1, BPS);

        (uint256 fee, ) = h.calculateProtocolFee(
            maxCollateral,
            bonusPercent,
            liquidationFee
        );

        // baseCollateral = maxCollateral.percentDiv(bonusPercent)
        // bonusCollateral = maxCollateral - baseCollateral
        // percentDiv rounds: (maxCollateral * 10000 + bonusPercent/2) / bonusPercent
        uint256 baseCollateral = (maxCollateral * BPS + bonusPercent / 2) /
            bonusPercent;
        uint256 bonusCollateral = maxCollateral - baseCollateral;

        assertLe(
            fee,
            bonusCollateral,
            "protocol fee should not exceed bonus collateral"
        );
    }

    function testFuzz_protocolFee_LiquidatorGetsAtLeastBase(
        uint256 maxCollateral,
        uint256 bonusPercent,
        uint256 liquidationFee
    ) public view {
        // Liquidator should always receive at least the base collateral (before bonus)
        maxCollateral = bound(maxCollateral, 1, 1e24);
        bonusPercent = bound(bonusPercent, BPS + 1, 2 * BPS);
        liquidationFee = bound(liquidationFee, 1, BPS);

        (, uint256 liquidatorCol) = h.calculateProtocolFee(
            maxCollateral,
            bonusPercent,
            liquidationFee
        );

        // baseCollateral = maxCollateral.percentDiv(bonusPercent)
        uint256 baseCollateral = (maxCollateral * BPS + bonusPercent / 2) /
            bonusPercent;

        assertGe(
            liquidatorCol,
            baseCollateral,
            "liquidator should get at least base collateral"
        );
    }

    function testFuzz_protocolFee_FullFeeCapsBonusToProtocol(
        uint256 maxCollateral,
        uint256 bonusPercent
    ) public view {
        // 100% liquidation fee → protocol gets all the bonus
        maxCollateral = bound(maxCollateral, 1, 1e24);
        bonusPercent = bound(bonusPercent, BPS + 1, 2 * BPS);

        (uint256 fee, ) = h.calculateProtocolFee(
            maxCollateral,
            bonusPercent,
            BPS
        );

        uint256 baseCollateral = (maxCollateral * BPS + bonusPercent / 2) /
            bonusPercent;
        uint256 bonusCollateral = maxCollateral - baseCollateral;

        assertEq(
            fee,
            bonusCollateral,
            "100% fee should give all bonus to protocol"
        );
    }
}
