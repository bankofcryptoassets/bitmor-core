// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.13 <0.9.0;

import "forge-std/Test.sol";

interface IMockRateOracle {
    function setRate(uint256 rate) external;
}

interface IInterestRateStrategyHarness {
    function OPTIMAL_UTILIZATION_RATE() external view returns (uint256);
    function EXCESS_UTILIZATION_RATE() external view returns (uint256);
    function baseVariableBorrowRate() external view returns (uint256);
    function getMaxVariableBorrowRate() external view returns (uint256);
    function variableRateSlope1() external view returns (uint256);
    function variableRateSlope2() external view returns (uint256);
    function stableRateSlope1() external view returns (uint256);
    function stableRateSlope2() external view returns (uint256);

    function calculateInterestRates(
        address reserve,
        uint256 availableLiquidity,
        uint256 totalStableDebt,
        uint256 totalVariableDebt,
        uint256 averageStableBorrowRate,
        uint256 reserveFactor
    ) external view returns (uint256, uint256, uint256);

    function exposed_getOverallBorrowRate(
        uint256 totalStableDebt,
        uint256 totalVariableDebt,
        uint256 currentVariableBorrowRate,
        uint256 currentAverageStableBorrowRate
    ) external pure returns (uint256);
}

contract DefaultReserveInterestRateStrategyFuzzTest is Test {
    IInterestRateStrategyHarness h;
    IMockRateOracle rateOracle;
    address reserve;

    uint256 constant RAY = 1e27;
    uint256 constant BPS = 10000;

    // Standard Aave-like parameters
    uint256 constant OPTIMAL_RATE = 0.8e27; // 80%
    uint256 constant BASE_VAR_RATE = 0;
    uint256 constant VAR_SLOPE1 = 0.04e27; // 4%
    uint256 constant VAR_SLOPE2 = 0.75e27; // 75%
    uint256 constant STABLE_SLOPE1 = 0.02e27; // 2%
    uint256 constant STABLE_SLOPE2 = 0.6e27; // 60%
    uint256 constant MARKET_BORROW_RATE = 0.03e27; // 3%

    function setUp() public {
        reserve = makeAddr("reserve");

        // Deploy mock rate oracle
        address oracleAddr = deployCode(
            "InterestRateStrategyHarness.sol:MockRateOracleForStrategy"
        );
        rateOracle = IMockRateOracle(oracleAddr);
        rateOracle.setRate(MARKET_BORROW_RATE);

        // Deploy mock provider pointing to the oracle
        address providerAddr = deployCode(
            "InterestRateStrategyHarness.sol:MockProviderForStrategy",
            abi.encode(oracleAddr)
        );

        // Deploy strategy harness
        address harnessAddr = deployCode(
            "InterestRateStrategyHarness.sol:InterestRateStrategyHarness",
            abi.encode(
                providerAddr,
                OPTIMAL_RATE,
                BASE_VAR_RATE,
                VAR_SLOPE1,
                VAR_SLOPE2,
                STABLE_SLOPE1,
                STABLE_SLOPE2
            )
        );
        h = IInterestRateStrategyHarness(harnessAddr);
    }

    // ============================================================
    //                   _getOverallBorrowRate
    // ============================================================

    function testFuzz_overallBorrowRate_ZeroDebtReturnsZero(
        uint256 varRate,
        uint256 stableRate
    ) public view {
        varRate = bound(varRate, 0, RAY);
        stableRate = bound(stableRate, 0, RAY);
        uint256 rate = h.exposed_getOverallBorrowRate(0, 0, varRate, stableRate);
        assertEq(rate, 0, "zero total debt should return zero overall rate");
    }

    function testFuzz_overallBorrowRate_OnlyVariableDebt(
        uint256 variableDebt,
        uint256 varRate
    ) public view {
        // When stable debt == 0, overall rate == variable borrow rate
        // Use WAD-scale debts to avoid rounding: wadToRay(debt) * rate / RAY needs precision
        variableDebt = bound(variableDebt, 1e18, 1e30);
        varRate = bound(varRate, 1e22, RAY);
        uint256 rate = h.exposed_getOverallBorrowRate(0, variableDebt, varRate, 0);
        // Allow ±1 rounding tolerance from rayMul/rayDiv
        assertApproxEqAbs(rate, varRate, 1, "only variable debt should return variable rate");
    }

    function testFuzz_overallBorrowRate_OnlyStableDebt(
        uint256 stableDebt,
        uint256 stableRate
    ) public view {
        // When variable debt == 0, overall rate == stable borrow rate
        stableDebt = bound(stableDebt, 1e18, 1e30);
        stableRate = bound(stableRate, 1e22, RAY);
        uint256 rate = h.exposed_getOverallBorrowRate(stableDebt, 0, 0, stableRate);
        assertApproxEqAbs(rate, stableRate, 1, "only stable debt should return stable rate");
    }

    function testFuzz_overallBorrowRate_BoundedByComponentRates(
        uint256 stableDebt,
        uint256 variableDebt,
        uint256 varRate,
        uint256 stableRate
    ) public view {
        // Weighted average should be between min and max component rates
        stableDebt = bound(stableDebt, 1e18, 1e30);
        variableDebt = bound(variableDebt, 1e18, 1e30);
        varRate = bound(varRate, 1e22, RAY / 2);
        stableRate = bound(stableRate, 1e22, RAY / 2);

        uint256 rate = h.exposed_getOverallBorrowRate(
            stableDebt,
            variableDebt,
            varRate,
            stableRate
        );
        uint256 minRate = varRate < stableRate ? varRate : stableRate;
        uint256 maxRate = varRate > stableRate ? varRate : stableRate;

        assertGe(rate + 1, minRate, "overall rate should be >= min component rate");
        assertLe(rate, maxRate + 1, "overall rate should be <= max component rate");
    }

    function testFuzz_overallBorrowRate_MonotonicInVariableRate(
        uint256 stableDebt,
        uint256 variableDebt,
        uint256 varRate1,
        uint256 varRate2,
        uint256 stableRate
    ) public view {
        stableDebt = bound(stableDebt, 1, 1e18);
        variableDebt = bound(variableDebt, 1, 1e18);
        varRate1 = bound(varRate1, 0, RAY / 2);
        varRate2 = bound(varRate2, varRate1, RAY / 2);
        stableRate = bound(stableRate, 0, RAY / 2);

        uint256 rate1 = h.exposed_getOverallBorrowRate(
            stableDebt,
            variableDebt,
            varRate1,
            stableRate
        );
        uint256 rate2 = h.exposed_getOverallBorrowRate(
            stableDebt,
            variableDebt,
            varRate2,
            stableRate
        );
        assertLe(
            rate1,
            rate2 + 1,
            "overall rate should increase with higher variable rate"
        );
    }

    // ============================================================
    //                   calculateInterestRates
    // ============================================================

    function testFuzz_interestRates_ZeroDebtGivesBaseVariableRate(
        uint256 availableLiquidity
    ) public view {
        // With no debt, variable rate = base rate, liquidity rate = 0
        availableLiquidity = bound(availableLiquidity, 1, 1e24);

        (uint256 liquidityRate, , uint256 variableRate) = h
            .calculateInterestRates(reserve, availableLiquidity, 0, 0, 0, 0);

        assertEq(
            variableRate,
            BASE_VAR_RATE,
            "zero debt should give base variable rate"
        );
        assertEq(liquidityRate, 0, "zero debt should give zero liquidity rate");
    }

    function testFuzz_interestRates_MonotonicVariableRateInDebt(
        uint256 availableLiquidity,
        uint256 debt1,
        uint256 debt2
    ) public view {
        // More debt (higher utilization) → higher variable rate
        availableLiquidity = bound(availableLiquidity, 1e6, 1e24);
        debt1 = bound(debt1, 0, 1e24);
        debt2 = bound(debt2, debt1, 1e24);

        (, , uint256 varRate1) = h.calculateInterestRates(
            reserve,
            availableLiquidity,
            0,
            debt1,
            0,
            0
        );
        (, , uint256 varRate2) = h.calculateInterestRates(
            reserve,
            availableLiquidity,
            0,
            debt2,
            0,
            0
        );

        assertLe(
            varRate1,
            varRate2,
            "variable rate should increase with more debt"
        );
    }

    function testFuzz_interestRates_VariableRateAlwaysGteBase(
        uint256 availableLiquidity,
        uint256 totalVariableDebt
    ) public view {
        availableLiquidity = bound(availableLiquidity, 1, 1e24);
        totalVariableDebt = bound(totalVariableDebt, 0, 1e24);

        (, , uint256 variableRate) = h.calculateInterestRates(
            reserve,
            availableLiquidity,
            0,
            totalVariableDebt,
            0,
            0
        );

        assertGe(
            variableRate,
            BASE_VAR_RATE,
            "variable rate should always be >= base rate"
        );
    }

    function testFuzz_interestRates_VariableRateBelowMax(
        uint256 availableLiquidity,
        uint256 totalVariableDebt
    ) public view {
        // Variable rate should never exceed base + slope1 + slope2
        availableLiquidity = bound(availableLiquidity, 1, 1e24);
        totalVariableDebt = bound(totalVariableDebt, 0, 1e24);

        (, , uint256 variableRate) = h.calculateInterestRates(
            reserve,
            availableLiquidity,
            0,
            totalVariableDebt,
            0,
            0
        );

        uint256 maxRate = h.getMaxVariableBorrowRate();
        assertLe(
            variableRate,
            maxRate,
            "variable rate should never exceed max rate"
        );
    }

    function testFuzz_interestRates_FullReserveFactorZerosLiquidityRate(
        uint256 availableLiquidity,
        uint256 totalVariableDebt
    ) public view {
        // 100% reserve factor → all interest goes to treasury, 0 to suppliers
        availableLiquidity = bound(availableLiquidity, 1, 1e24);
        totalVariableDebt = bound(totalVariableDebt, 1, 1e24);

        (uint256 liquidityRate, , ) = h.calculateInterestRates(
            reserve,
            availableLiquidity,
            0,
            totalVariableDebt,
            0,
            BPS
        );

        assertEq(
            liquidityRate,
            0,
            "100% reserve factor should zero out liquidity rate"
        );
    }

    function testFuzz_interestRates_ReserveFactorReducesLiquidityRate(
        uint256 availableLiquidity,
        uint256 totalVariableDebt,
        uint256 rf1,
        uint256 rf2
    ) public view {
        // Higher reserve factor → lower liquidity rate
        availableLiquidity = bound(availableLiquidity, 1e6, 1e24);
        totalVariableDebt = bound(totalVariableDebt, 1e6, 1e24);
        rf1 = bound(rf1, 0, BPS);
        rf2 = bound(rf2, rf1, BPS);

        (uint256 liqRate1, , ) = h.calculateInterestRates(
            reserve,
            availableLiquidity,
            0,
            totalVariableDebt,
            0,
            rf1
        );
        (uint256 liqRate2, , ) = h.calculateInterestRates(
            reserve,
            availableLiquidity,
            0,
            totalVariableDebt,
            0,
            rf2
        );

        assertGe(
            liqRate1,
            liqRate2,
            "higher reserve factor should reduce liquidity rate"
        );
    }

    function testFuzz_interestRates_ReserveFactorDoesNotAffectBorrowRates(
        uint256 availableLiquidity,
        uint256 totalVariableDebt,
        uint256 rf1,
        uint256 rf2
    ) public view {
        // Reserve factor only affects liquidity rate, not borrow rates
        availableLiquidity = bound(availableLiquidity, 1e6, 1e24);
        totalVariableDebt = bound(totalVariableDebt, 1e6, 1e24);
        rf1 = bound(rf1, 0, BPS);
        rf2 = bound(rf2, 0, BPS);

        (, uint256 stableRate1, uint256 varRate1) = h.calculateInterestRates(
            reserve,
            availableLiquidity,
            0,
            totalVariableDebt,
            0,
            rf1
        );
        (, uint256 stableRate2, uint256 varRate2) = h.calculateInterestRates(
            reserve,
            availableLiquidity,
            0,
            totalVariableDebt,
            0,
            rf2
        );

        assertEq(
            varRate1,
            varRate2,
            "reserve factor should not affect variable borrow rate"
        );
        assertEq(
            stableRate1,
            stableRate2,
            "reserve factor should not affect stable borrow rate"
        );
    }

    function testFuzz_interestRates_AboveOptimalHigherThanBelowOptimal(
        uint256 availableLiquidity
    ) public view {
        // Rates above optimal utilization should be higher than below
        availableLiquidity = bound(availableLiquidity, 1e8, 1e24);

        // Debt for ~70% utilization: debt/(avail+debt) = 0.70 → debt = 0.70/0.30 * avail
        uint256 debtBelow = (availableLiquidity * 70) / 30;
        // Debt for ~90% utilization: debt/(avail+debt) = 0.90 → debt = 0.90/0.10 * avail
        uint256 debtAbove = (availableLiquidity * 90) / 10;

        (, , uint256 varRateBelow) = h.calculateInterestRates(
            reserve,
            availableLiquidity,
            0,
            debtBelow,
            0,
            0
        );
        (, , uint256 varRateAbove) = h.calculateInterestRates(
            reserve,
            availableLiquidity,
            0,
            debtAbove,
            0,
            0
        );

        assertLt(
            varRateBelow,
            varRateAbove,
            "rate above optimal utilization should be higher than below"
        );
    }
}
