// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.13 <0.9.0;

import "forge-std/Test.sol";

interface ILendingPoolCollateralManagerHarness {
    function calculateAvailableCollateralToLiquidate(
        uint256 collateralPrice,
        uint256 debtAssetPrice,
        uint256 debtToCover,
        uint256 userCollateralBalance,
        uint256 collateralDecimals,
        uint256 debtAssetDecimals,
        uint256 liquidationBonus
    ) external pure returns (uint256 collateralAmount, uint256 debtAmountNeeded);
}

contract LendingPoolCollateralManagerFuzzTest is Test {
    ILendingPoolCollateralManagerHarness h;

    uint256 constant BPS = 10000;

    // Realistic BTC/USDC scenario constants
    uint256 constant BTC_PRICE = 60_000e8; // $60,000 in 8-decimal oracle format
    uint256 constant USDC_PRICE = 1e8; // $1 in 8-decimal oracle format
    uint8 constant BTC_DECIMALS = 8;
    uint8 constant USDC_DECIMALS = 6;
    uint256 constant STANDARD_BONUS = 10500; // 105%

    function setUp() public {
        h = ILendingPoolCollateralManagerHarness(
            deployCode("LendingPoolCollateralManagerHarness.sol")
        );
    }

    // ============================================================
    //         calculateAvailableCollateralToLiquidate
    // ============================================================

    function testFuzz_maxCollateral_ZeroDebtReturnsZero(
        uint256 collateralPrice,
        uint256 debtAssetPrice,
        uint256 userCollateralBalance,
        uint256 liquidationBonus
    ) public view {
        collateralPrice = bound(collateralPrice, 1, 1e18);
        debtAssetPrice = bound(debtAssetPrice, 1, 1e18);
        userCollateralBalance = bound(userCollateralBalance, 0, 1e18);
        liquidationBonus = bound(liquidationBonus, BPS, 2 * BPS);

        (uint256 collateralAmount, uint256 debtNeeded) = h
            .calculateAvailableCollateralToLiquidate(
                collateralPrice,
                debtAssetPrice,
                0, // debtToCover = 0
                userCollateralBalance,
                BTC_DECIMALS,
                USDC_DECIMALS,
                liquidationBonus
            );

        assertEq(collateralAmount, 0, "zero debt should give zero collateral");
        assertEq(debtNeeded, 0, "zero debt should give zero debt needed");
    }

    function testFuzz_maxCollateral_MonotonicInDebt(
        uint256 debt1,
        uint256 debt2,
        uint256 userCollateralBalance
    ) public view {
        // More debt → more collateral seized (if user has enough)
        debt1 = bound(debt1, 1e6, 1e12);
        debt2 = bound(debt2, debt1, 1e12);
        userCollateralBalance = bound(userCollateralBalance, 1e8, 100e8); // large balance so no cap

        (uint256 col1, ) = h.calculateAvailableCollateralToLiquidate(
            BTC_PRICE,
            USDC_PRICE,
            debt1,
            userCollateralBalance,
            BTC_DECIMALS,
            USDC_DECIMALS,
            STANDARD_BONUS
        );
        (uint256 col2, ) = h.calculateAvailableCollateralToLiquidate(
            BTC_PRICE,
            USDC_PRICE,
            debt2,
            userCollateralBalance,
            BTC_DECIMALS,
            USDC_DECIMALS,
            STANDARD_BONUS
        );

        assertLe(col1, col2, "more debt should seize more or equal collateral");
    }

    function testFuzz_maxCollateral_MonotonicInBonus(
        uint256 debtToCover,
        uint256 bonus1,
        uint256 bonus2,
        uint256 userCollateralBalance
    ) public view {
        // Higher bonus → more collateral seized
        debtToCover = bound(debtToCover, 1e6, 1e10);
        bonus1 = bound(bonus1, BPS, 2 * BPS);
        bonus2 = bound(bonus2, bonus1, 2 * BPS);
        userCollateralBalance = bound(userCollateralBalance, 1e8, 100e8);

        (uint256 col1, ) = h.calculateAvailableCollateralToLiquidate(
            BTC_PRICE,
            USDC_PRICE,
            debtToCover,
            userCollateralBalance,
            BTC_DECIMALS,
            USDC_DECIMALS,
            bonus1
        );
        (uint256 col2, ) = h.calculateAvailableCollateralToLiquidate(
            BTC_PRICE,
            USDC_PRICE,
            debtToCover,
            userCollateralBalance,
            BTC_DECIMALS,
            USDC_DECIMALS,
            bonus2
        );

        assertLe(col1, col2, "higher bonus should seize more or equal collateral");
    }

    function testFuzz_maxCollateral_InverseInCollateralPrice(
        uint256 debtToCover,
        uint256 price1,
        uint256 price2,
        uint256 userCollateralBalance
    ) public view {
        // Higher collateral price → fewer units seized
        debtToCover = bound(debtToCover, 1e6, 1e10);
        price1 = bound(price1, 1e8, 1e14);
        price2 = bound(price2, price1, 1e14);
        userCollateralBalance = bound(userCollateralBalance, 1e10, 1e18);

        (uint256 col1, ) = h.calculateAvailableCollateralToLiquidate(
            price1,
            USDC_PRICE,
            debtToCover,
            userCollateralBalance,
            BTC_DECIMALS,
            USDC_DECIMALS,
            STANDARD_BONUS
        );
        (uint256 col2, ) = h.calculateAvailableCollateralToLiquidate(
            price2,
            USDC_PRICE,
            debtToCover,
            userCollateralBalance,
            BTC_DECIMALS,
            USDC_DECIMALS,
            STANDARD_BONUS
        );

        assertGe(
            col1,
            col2,
            "higher collateral price should seize fewer or equal units"
        );
    }

    function testFuzz_maxCollateral_MonotonicInDebtPrice(
        uint256 debtToCover,
        uint256 debtPrice1,
        uint256 debtPrice2,
        uint256 userCollateralBalance
    ) public view {
        // Higher debt asset price → more collateral in units
        debtToCover = bound(debtToCover, 1e6, 1e10);
        debtPrice1 = bound(debtPrice1, 1e6, 1e12);
        debtPrice2 = bound(debtPrice2, debtPrice1, 1e12);
        userCollateralBalance = bound(userCollateralBalance, 1e10, 1e18);

        (uint256 col1, ) = h.calculateAvailableCollateralToLiquidate(
            BTC_PRICE,
            debtPrice1,
            debtToCover,
            userCollateralBalance,
            BTC_DECIMALS,
            USDC_DECIMALS,
            STANDARD_BONUS
        );
        (uint256 col2, ) = h.calculateAvailableCollateralToLiquidate(
            BTC_PRICE,
            debtPrice2,
            debtToCover,
            userCollateralBalance,
            BTC_DECIMALS,
            USDC_DECIMALS,
            STANDARD_BONUS
        );

        assertLe(
            col1,
            col2,
            "higher debt price should seize more or equal collateral units"
        );
    }

    function testFuzz_maxCollateral_CappedByUserBalance(
        uint256 debtToCover,
        uint256 userCollateralBalance
    ) public view {
        // Collateral seized should never exceed user's balance
        debtToCover = bound(debtToCover, 1e6, 1e15);
        userCollateralBalance = bound(userCollateralBalance, 1, 1e12);

        (uint256 collateralAmount, ) = h.calculateAvailableCollateralToLiquidate(
            BTC_PRICE,
            USDC_PRICE,
            debtToCover,
            userCollateralBalance,
            BTC_DECIMALS,
            USDC_DECIMALS,
            STANDARD_BONUS
        );

        assertLe(
            collateralAmount,
            userCollateralBalance,
            "collateral seized should never exceed user balance"
        );
    }

    function testFuzz_maxCollateral_DebtNeededLeDebtToCover(
        uint256 debtToCover,
        uint256 userCollateralBalance
    ) public view {
        // debtAmountNeeded should never exceed debtToCover
        debtToCover = bound(debtToCover, 1e6, 1e15);
        userCollateralBalance = bound(userCollateralBalance, 1, 1e12);

        (, uint256 debtNeeded) = h.calculateAvailableCollateralToLiquidate(
            BTC_PRICE,
            USDC_PRICE,
            debtToCover,
            userCollateralBalance,
            BTC_DECIMALS,
            USDC_DECIMALS,
            STANDARD_BONUS
        );

        assertLe(
            debtNeeded,
            debtToCover,
            "debt needed should never exceed debt to cover"
        );
    }

    function testFuzz_maxCollateral_ConsistentDecimals(
        uint256 debtToCover
    ) public view {
        // With equal prices and equal decimals, collateral ≈ debt * bonus / BPS
        // Use large user balance to avoid capping
        uint256 price = 1e8;
        uint8 decimals = 8;
        debtToCover = bound(debtToCover, 1e4, 1e12);
        uint256 userCollateralBalance = type(uint128).max;

        (uint256 collateralAmount, uint256 debtNeeded) = h
            .calculateAvailableCollateralToLiquidate(
                price,
                price,
                debtToCover,
                userCollateralBalance,
                decimals,
                decimals,
                STANDARD_BONUS
            );

        // Expected: collateral = debtToCover.percentMul(STANDARD_BONUS)
        // percentMul(x, y) = (x * y + 5000) / 10000
        uint256 expectedCollateral = (debtToCover * STANDARD_BONUS + BPS / 2) / BPS;

        // Allow small rounding tolerance
        assertApproxEqAbs(
            collateralAmount,
            expectedCollateral,
            2,
            "equal prices/decimals: collateral should be debt * bonus"
        );
        assertEq(debtNeeded, debtToCover, "uncapped case: debt needed should equal debt to cover");
    }

    function testFuzz_maxCollateral_RealisticBtcUsdc(
        uint256 btcPrice,
        uint256 debtToCover,
        uint256 userCollateralBalance
    ) public view {
        // Realistic scenario: BTC collateral, USDC debt
        btcPrice = bound(btcPrice, 10_000e8, 200_000e8); // $10k-$200k BTC
        debtToCover = bound(debtToCover, 100e6, 1_000_000e6); // $100-$1M USDC
        userCollateralBalance = bound(userCollateralBalance, 1e5, 100e8); // 0.001-100 BTC

        (uint256 collateralAmount, uint256 debtNeeded) = h
            .calculateAvailableCollateralToLiquidate(
                btcPrice,
                USDC_PRICE,
                debtToCover,
                userCollateralBalance,
                BTC_DECIMALS,
                USDC_DECIMALS,
                STANDARD_BONUS
            );

        // Basic sanity: amounts should be reasonable
        assertLe(collateralAmount, userCollateralBalance, "collateral capped by user balance");
        assertLe(debtNeeded, debtToCover, "debt needed capped by debt to cover");
        assertGe(collateralAmount, 0, "collateral should be non-negative");
        assertGe(debtNeeded, 0, "debt needed should be non-negative");
    }
}
