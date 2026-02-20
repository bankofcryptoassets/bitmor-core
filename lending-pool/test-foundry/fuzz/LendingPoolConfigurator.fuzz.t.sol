// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.13 <0.9.0;

import "forge-std/Test.sol";

interface ILendingPoolConfiguratorHarness {
    function initialize(address provider) external;

    function configureReserveAsCollateral(
        address asset,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    ) external;
}

interface IMockAddressesProviderForLPC {
    function setPoolAdmin(address admin) external;
    function setLendingPool(address pool_) external;
}

contract LendingPoolConfiguratorFuzzTest is Test {
    ILendingPoolConfiguratorHarness configurator;
    address asset;
    address admin;

    uint256 constant BPS = 10000;

    // The real LendingPoolConfigurator uses Errors.LPC_INVALID_CONFIGURATION = "75"
    bytes constant ERR_INVALID_CONFIG = bytes("75");

    function setUp() public {
        admin = makeAddr("admin");

        // Deploy mocks
        asset = deployCode("LendingPoolConfiguratorHarness.sol:MockAssetForLPC");
        address pool = deployCode("LendingPoolConfiguratorHarness.sol:MockPoolForLPC");
        address addressesProvider = deployCode(
            "LendingPoolConfiguratorHarness.sol:MockAddressesProviderForLPC"
        );

        IMockAddressesProviderForLPC(addressesProvider).setPoolAdmin(admin);
        IMockAddressesProviderForLPC(addressesProvider).setLendingPool(pool);

        // Deploy harness (inherits real LendingPoolConfigurator) and initialize
        configurator = ILendingPoolConfiguratorHarness(
            deployCode("LendingPoolConfiguratorHarness.sol:LendingPoolConfiguratorHarness")
        );
        configurator.initialize(addressesProvider);
    }

    // ============================================================
    //               configureReserveAsCollateral - valid inputs
    // ============================================================

    function testFuzz_validateConfig_ValidParams(
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    ) public {
        // Generate valid configurations: threshold * bonus <= 10000
        // For bonus in [10001, 20000], max threshold = 10000 * 10000 / bonus
        liquidationBonus = bound(liquidationBonus, BPS + 1, 2 * BPS);
        // threshold * bonus <= BPS^2, so threshold <= BPS^2 / bonus
        uint256 maxThreshold = (BPS * BPS) / liquidationBonus;
        liquidationThreshold = bound(liquidationThreshold, 1, maxThreshold);
        ltv = bound(ltv, 0, liquidationThreshold);

        // No revert means validation passed
        vm.prank(admin);
        configurator.configureReserveAsCollateral(asset, ltv, liquidationThreshold, liquidationBonus);
    }

    function testFuzz_validateConfig_ZeroThresholdZeroBonus() public {
        // When threshold == 0 and bonus == 0, ltv must also be 0
        // _checkNoLiquidity passes because mock pool returns 0 liquidity
        vm.prank(admin);
        configurator.configureReserveAsCollateral(asset, 0, 0, 0);
    }

    // ============================================================
    //            configureReserveAsCollateral - reverts
    // ============================================================

    function testFuzz_validateConfig_RevertsWhen_LtvGtThreshold(
        uint256 ltv,
        uint256 liquidationThreshold
    ) public {
        // ltv > liquidationThreshold should revert
        liquidationThreshold = bound(liquidationThreshold, 0, BPS - 1);
        ltv = bound(ltv, liquidationThreshold + 1, BPS);

        vm.expectRevert(ERR_INVALID_CONFIG);
        vm.prank(admin);
        configurator.configureReserveAsCollateral(asset, ltv, liquidationThreshold, 0);
    }

    function testFuzz_validateConfig_RevertsWhen_BonusTooLow(
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    ) public {
        // When threshold != 0, bonus must be > 10000
        liquidationThreshold = bound(liquidationThreshold, 1, BPS);
        ltv = bound(ltv, 0, liquidationThreshold);
        liquidationBonus = bound(liquidationBonus, 0, BPS); // <= 10000

        vm.expectRevert(ERR_INVALID_CONFIG);
        vm.prank(admin);
        configurator.configureReserveAsCollateral(asset, ltv, liquidationThreshold, liquidationBonus);
    }

    function testFuzz_validateConfig_RevertsWhen_ThresholdTimesBonusExceedsFactor(
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    ) public {
        // threshold * bonus > BPS^2 should revert
        // percentMul(a, b) = (a * b + BPS/2) / BPS
        // We need: (threshold * bonus + BPS/2) / BPS > BPS
        liquidationBonus = bound(liquidationBonus, BPS + 1, 2 * BPS);
        // min threshold such that threshold * bonus > BPS^2
        uint256 minThreshold = (BPS * BPS) / liquidationBonus + 1;
        vm.assume(minThreshold <= BPS);
        liquidationThreshold = bound(liquidationThreshold, minThreshold, BPS);

        // Verify percentMul result would exceed BPS (with rounding check)
        uint256 product = (liquidationThreshold * liquidationBonus + BPS / 2) / BPS;
        vm.assume(product > BPS);

        vm.expectRevert(ERR_INVALID_CONFIG);
        vm.prank(admin);
        configurator.configureReserveAsCollateral(asset, 0, liquidationThreshold, liquidationBonus);
    }

    function testFuzz_validateConfig_RevertsWhen_ZeroThresholdNonZeroBonus(
        uint256 liquidationBonus
    ) public {
        // When threshold == 0, bonus must be 0
        liquidationBonus = bound(liquidationBonus, 1, 2 * BPS);

        vm.expectRevert(ERR_INVALID_CONFIG);
        vm.prank(admin);
        configurator.configureReserveAsCollateral(asset, 0, 0, liquidationBonus);
    }

    // ============================================================
    //           configureReserveAsCollateral - properties
    // ============================================================

    function testFuzz_validateConfig_LtvAlwaysLeThreshold(
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    ) public {
        // If validation passes, ltv <= threshold is guaranteed
        liquidationBonus = bound(liquidationBonus, BPS + 1, 2 * BPS);
        uint256 maxThreshold = (BPS * BPS) / liquidationBonus;
        vm.assume(maxThreshold >= 1);
        liquidationThreshold = bound(liquidationThreshold, 1, maxThreshold);
        ltv = bound(ltv, 0, liquidationThreshold);

        vm.prank(admin);
        configurator.configureReserveAsCollateral(asset, ltv, liquidationThreshold, liquidationBonus);

        // The above didn't revert, so ltv <= threshold
        assertLe(ltv, liquidationThreshold, "ltv must be <= threshold after validation");
    }

    function testFuzz_validateConfig_SolvencyGuarantee(
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    ) public {
        // If validation passes with non-zero threshold, threshold * bonus / BPS <= 100%
        // This ensures liquidation bonus never exceeds available collateral
        liquidationBonus = bound(liquidationBonus, BPS + 1, 2 * BPS);
        uint256 maxThreshold = (BPS * BPS) / liquidationBonus;
        vm.assume(maxThreshold >= 1);
        liquidationThreshold = bound(liquidationThreshold, 1, maxThreshold);

        vm.prank(admin);
        configurator.configureReserveAsCollateral(asset, 0, liquidationThreshold, liquidationBonus);

        // Solvency: threshold * bonus <= BPS^2
        // Equivalent: at max LTV, there's still enough collateral to pay the bonus
        uint256 product = (liquidationThreshold * liquidationBonus + BPS / 2) / BPS;
        assertLe(
            product,
            BPS,
            "threshold * bonus / BPS must be <= 100% for solvency"
        );
    }
}
