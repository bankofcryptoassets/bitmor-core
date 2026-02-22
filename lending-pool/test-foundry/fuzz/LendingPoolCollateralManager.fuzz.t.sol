// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.13 <0.9.0;

import "forge-std/Test.sol";

interface ILendingPoolCollateralManagerHarness {
    function setupState(
        address addressesProvider,
        address collateralAsset,
        address debtAsset,
        uint256 collateralDecimals,
        uint256 debtAssetDecimals,
        uint256 liquidationBonus
    ) external;

    function exposed_calculateAvailableCollateralToLiquidate(
        address collateralAsset,
        address debtAsset,
        uint256 debtToCover,
        uint256 userCollateralBalance
    ) external view returns (uint256 collateralAmount, uint256 debtAmountNeeded, uint256 liquidationBonus);

    function exposed_calculateProtocolFee(
        uint256 maxCollateralToLiquidate,
        uint256 liquidationBonusPercent,
        uint256 liquidationFee
    ) external pure returns (uint256 protocolFee, uint256 liquidatorCollateral);
}

interface IMockPriceOracleForLPCM {
    function setAssetPrice(address asset, uint256 price) external;
}

interface IMockAddressesProviderForLPCM {
    function setOracle(address oracle_) external;
}

contract LendingPoolCollateralManagerFuzzTest is Test {
    ILendingPoolCollateralManagerHarness h;
    IMockPriceOracleForLPCM oracle;
    address addressesProvider;

    address constant COLLATERAL_ASSET = address(0xC01);
    address constant DEBT_ASSET = address(0xDE87);

    uint256 constant BPS = 10000;

    // Realistic BTC/USDC scenario constants
    uint256 constant BTC_PRICE = 60_000e8; // $60,000 in 8-decimal oracle format
    uint256 constant USDC_PRICE = 1e8; // $1 in 8-decimal oracle format
    uint8 constant BTC_DECIMALS = 8;
    uint8 constant USDC_DECIMALS = 6;
    uint256 constant STANDARD_BONUS = 10500; // 105%

    function setUp() public {
        // Deploy mocks
        oracle = IMockPriceOracleForLPCM(
            deployCode("LendingPoolCollateralManagerHarness.sol:MockPriceOracleForLPCM")
        );

        addressesProvider = deployCode(
            "LendingPoolCollateralManagerHarness.sol:MockAddressesProviderForLPCM"
        );
        IMockAddressesProviderForLPCM(addressesProvider).setOracle(address(oracle));

        // Deploy harness (inherits real LendingPoolCollateralManager)
        h = ILendingPoolCollateralManagerHarness(
            deployCode("LendingPoolCollateralManagerHarness.sol:LendingPoolCollateralManagerHarness")
        );

        // Default reserve configuration: BTC collateral, USDC debt, 105% bonus
        h.setupState(
            addressesProvider,
            COLLATERAL_ASSET,
            DEBT_ASSET,
            BTC_DECIMALS,
            USDC_DECIMALS,
            STANDARD_BONUS
        );
    }

    /// @dev Set oracle prices for both assets
    function _setOraclePrices(uint256 collateralPrice, uint256 debtPrice) internal {
        oracle.setAssetPrice(COLLATERAL_ASSET, collateralPrice);
        oracle.setAssetPrice(DEBT_ASSET, debtPrice);
    }

    // ============================================================
    //         calculateAvailableCollateralToLiquidate
    // ============================================================

    function testFuzz_maxCollateral_ZeroDebtReturnsZero(
        uint256 collateralPrice,
        uint256 debtAssetPrice,
        uint256 userCollateralBalance,
        uint256 liquidationBonus
    ) public {
        collateralPrice = bound(collateralPrice, 1, 1e18);
        debtAssetPrice = bound(debtAssetPrice, 1, 1e18);
        userCollateralBalance = bound(userCollateralBalance, 0, 1e18);
        liquidationBonus = bound(liquidationBonus, BPS, 2 * BPS);

        _setOraclePrices(collateralPrice, debtAssetPrice);
        h.setupState(addressesProvider, COLLATERAL_ASSET, DEBT_ASSET, BTC_DECIMALS, USDC_DECIMALS, liquidationBonus);

        (uint256 collateralAmount, uint256 debtNeeded,) = h
            .exposed_calculateAvailableCollateralToLiquidate(
                COLLATERAL_ASSET,
                DEBT_ASSET,
                0, // debtToCover = 0
                userCollateralBalance
            );

        assertEq(collateralAmount, 0, "zero debt should give zero collateral");
        assertEq(debtNeeded, 0, "zero debt should give zero debt needed");
    }

    function testFuzz_maxCollateral_MonotonicInDebt(
        uint256 debt1,
        uint256 debt2,
        uint256 userCollateralBalance
    ) public {
        // More debt → more collateral seized (if user has enough)
        debt1 = bound(debt1, 1e6, 1e12);
        debt2 = bound(debt2, debt1, 1e12);
        userCollateralBalance = bound(userCollateralBalance, 1e8, 100e8); // large balance so no cap

        _setOraclePrices(BTC_PRICE, USDC_PRICE);

        (uint256 col1,,) = h.exposed_calculateAvailableCollateralToLiquidate(
            COLLATERAL_ASSET, DEBT_ASSET, debt1, userCollateralBalance
        );
        (uint256 col2,,) = h.exposed_calculateAvailableCollateralToLiquidate(
            COLLATERAL_ASSET, DEBT_ASSET, debt2, userCollateralBalance
        );

        assertLe(col1, col2, "more debt should seize more or equal collateral");
    }

    function testFuzz_maxCollateral_MonotonicInBonus(
        uint256 debtToCover,
        uint256 bonus1,
        uint256 bonus2,
        uint256 userCollateralBalance
    ) public {
        // Higher bonus → more collateral seized
        debtToCover = bound(debtToCover, 1e6, 1e10);
        bonus1 = bound(bonus1, BPS, 2 * BPS);
        bonus2 = bound(bonus2, bonus1, 2 * BPS);
        userCollateralBalance = bound(userCollateralBalance, 1e8, 100e8);

        _setOraclePrices(BTC_PRICE, USDC_PRICE);

        h.setupState(addressesProvider, COLLATERAL_ASSET, DEBT_ASSET, BTC_DECIMALS, USDC_DECIMALS, bonus1);
        (uint256 col1,,) = h.exposed_calculateAvailableCollateralToLiquidate(
            COLLATERAL_ASSET, DEBT_ASSET, debtToCover, userCollateralBalance
        );

        h.setupState(addressesProvider, COLLATERAL_ASSET, DEBT_ASSET, BTC_DECIMALS, USDC_DECIMALS, bonus2);
        (uint256 col2,,) = h.exposed_calculateAvailableCollateralToLiquidate(
            COLLATERAL_ASSET, DEBT_ASSET, debtToCover, userCollateralBalance
        );

        assertLe(col1, col2, "higher bonus should seize more or equal collateral");
    }

    function testFuzz_maxCollateral_InverseInCollateralPrice(
        uint256 debtToCover,
        uint256 price1,
        uint256 price2,
        uint256 userCollateralBalance
    ) public {
        // Higher collateral price → fewer units seized
        debtToCover = bound(debtToCover, 1e6, 1e10);
        price1 = bound(price1, 1e8, 1e14);
        price2 = bound(price2, price1, 1e14);
        userCollateralBalance = bound(userCollateralBalance, 1e10, 1e18);

        _setOraclePrices(price1, USDC_PRICE);
        (uint256 col1,,) = h.exposed_calculateAvailableCollateralToLiquidate(
            COLLATERAL_ASSET, DEBT_ASSET, debtToCover, userCollateralBalance
        );

        _setOraclePrices(price2, USDC_PRICE);
        (uint256 col2,,) = h.exposed_calculateAvailableCollateralToLiquidate(
            COLLATERAL_ASSET, DEBT_ASSET, debtToCover, userCollateralBalance
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
    ) public {
        // Higher debt asset price → more collateral in units
        debtToCover = bound(debtToCover, 1e6, 1e10);
        debtPrice1 = bound(debtPrice1, 1e6, 1e12);
        debtPrice2 = bound(debtPrice2, debtPrice1, 1e12);
        userCollateralBalance = bound(userCollateralBalance, 1e10, 1e18);

        _setOraclePrices(BTC_PRICE, debtPrice1);
        (uint256 col1,,) = h.exposed_calculateAvailableCollateralToLiquidate(
            COLLATERAL_ASSET, DEBT_ASSET, debtToCover, userCollateralBalance
        );

        _setOraclePrices(BTC_PRICE, debtPrice2);
        (uint256 col2,,) = h.exposed_calculateAvailableCollateralToLiquidate(
            COLLATERAL_ASSET, DEBT_ASSET, debtToCover, userCollateralBalance
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
    ) public {
        // Collateral seized should never exceed user's balance
        debtToCover = bound(debtToCover, 1e6, 1e15);
        userCollateralBalance = bound(userCollateralBalance, 1, 1e12);

        _setOraclePrices(BTC_PRICE, USDC_PRICE);

        (uint256 collateralAmount,,) = h.exposed_calculateAvailableCollateralToLiquidate(
            COLLATERAL_ASSET, DEBT_ASSET, debtToCover, userCollateralBalance
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
    ) public {
        // debtAmountNeeded should never exceed debtToCover
        debtToCover = bound(debtToCover, 1e6, 1e15);
        userCollateralBalance = bound(userCollateralBalance, 1, 1e12);

        _setOraclePrices(BTC_PRICE, USDC_PRICE);

        (, uint256 debtNeeded,) = h.exposed_calculateAvailableCollateralToLiquidate(
            COLLATERAL_ASSET, DEBT_ASSET, debtToCover, userCollateralBalance
        );

        assertLe(
            debtNeeded,
            debtToCover,
            "debt needed should never exceed debt to cover"
        );
    }

    function testFuzz_maxCollateral_ConsistentDecimals(
        uint256 debtToCover
    ) public {
        // With equal prices and equal decimals, collateral ≈ debt * bonus / BPS
        // Use large user balance to avoid capping
        uint256 price = 1e8;
        uint8 decimals = 8;
        debtToCover = bound(debtToCover, 1e4, 1e12);
        uint256 userCollateralBalance = type(uint128).max;

        _setOraclePrices(price, price);
        h.setupState(addressesProvider, COLLATERAL_ASSET, DEBT_ASSET, decimals, decimals, STANDARD_BONUS);

        (uint256 collateralAmount, uint256 debtNeeded,) = h
            .exposed_calculateAvailableCollateralToLiquidate(
                COLLATERAL_ASSET, DEBT_ASSET, debtToCover, userCollateralBalance
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
    ) public {
        // Realistic scenario: BTC collateral, USDC debt
        btcPrice = bound(btcPrice, 10_000e8, 200_000e8); // $10k-$200k BTC
        debtToCover = bound(debtToCover, 100e6, 1_000_000e6); // $100-$1M USDC
        userCollateralBalance = bound(userCollateralBalance, 1e5, 100e8); // 0.001-100 BTC

        _setOraclePrices(btcPrice, USDC_PRICE);

        (uint256 collateralAmount, uint256 debtNeeded,) = h
            .exposed_calculateAvailableCollateralToLiquidate(
                COLLATERAL_ASSET, DEBT_ASSET, debtToCover, userCollateralBalance
            );

        // Basic sanity: amounts should be reasonable
        assertLe(collateralAmount, userCollateralBalance, "collateral capped by user balance");
        assertLe(debtNeeded, debtToCover, "debt needed capped by debt to cover");
        assertGe(collateralAmount, 0, "collateral should be non-negative");
        assertGe(debtNeeded, 0, "debt needed should be non-negative");
    }

    // ============================================================
    //                   calculateProtocolFee
    // ============================================================

    function testFuzz_protocolFee_ZeroFeeGivesFullToLiquidator(
        uint256 maxCollateral,
        uint256 bonusPercent
    ) public view {
        // When liquidationFee == 0, liquidator gets everything
        maxCollateral = bound(maxCollateral, 0, 1e24);
        bonusPercent = bound(bonusPercent, BPS, 2 * BPS);

        (uint256 fee, uint256 liquidatorCol) = h.exposed_calculateProtocolFee(
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
        bonusPercent = bound(bonusPercent, BPS + 1, 2 * BPS);
        liquidationFee = bound(liquidationFee, 1, BPS);

        (uint256 fee, uint256 liquidatorCol) = h.exposed_calculateProtocolFee(
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

        (uint256 protocolFee1, ) = h.exposed_calculateProtocolFee(
            maxCollateral,
            bonusPercent,
            fee1
        );
        (uint256 protocolFee2, ) = h.exposed_calculateProtocolFee(
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

        (uint256 protocolFee1, ) = h.exposed_calculateProtocolFee(
            maxCollateral,
            bonus1,
            liquidationFee
        );
        (uint256 protocolFee2, ) = h.exposed_calculateProtocolFee(
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

        (uint256 fee, uint256 liquidatorCol) = h.exposed_calculateProtocolFee(
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

        (uint256 fee, ) = h.exposed_calculateProtocolFee(
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

        (, uint256 liquidatorCol) = h.exposed_calculateProtocolFee(
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

        (uint256 fee, ) = h.exposed_calculateProtocolFee(
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
