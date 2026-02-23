// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.13 <0.9.0;

import "forge-std/Test.sol";

interface IMockRateOracle {
    function setRate(uint256 rate) external;
}

interface IMockUSDCVault {
    function setTotalAssets(uint256 totalAssets_) external;
    function setAsset(address asset_) external;
}

interface IUSDCInterestRateStrategyHarness {
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

contract USDCReserveInterestRateStrategyFuzzTest is Test {
    IUSDCInterestRateStrategyHarness h;
    IMockRateOracle rateOracle;
    IMockUSDCVault mockVault;
    address reserve;

    uint256 constant RAY = 1e27;
    uint256 constant BPS = 10000;

    // Standard parameters (same structure as Default strategy)
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
            "USDCInterestRateStrategyHarness.sol:MockRateOracleForUSDCStrategy"
        );
        rateOracle = IMockRateOracle(oracleAddr);
        rateOracle.setRate(MARKET_BORROW_RATE);

        // Deploy mock USDC vault
        address vaultAddr = deployCode(
            "USDCInterestRateStrategyHarness.sol:MockUSDCVaultForStrategy"
        );
        mockVault = IMockUSDCVault(vaultAddr);
        mockVault.setTotalAssets(1_000_000e6); // 1M USDC
        mockVault.setAsset(makeAddr("usdc")); // Not the reserve address

        // Deploy mock provider pointing to the oracle and vault
        address providerAddr = deployCode(
            "USDCInterestRateStrategyHarness.sol:MockProviderForUSDCStrategy",
            abi.encode(oracleAddr, vaultAddr)
        );

        // Deploy strategy harness
        address harnessAddr = deployCode(
            "USDCInterestRateStrategyHarness.sol:USDCInterestRateStrategyHarness",
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
        h = IUSDCInterestRateStrategyHarness(harnessAddr);
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
        variableDebt = bound(variableDebt, 1e18, 1e30);
        varRate = bound(varRate, 1e22, RAY);
        uint256 rate = h.exposed_getOverallBorrowRate(0, variableDebt, varRate, 0);
        assertApproxEqAbs(rate, varRate, 1, "only variable debt should return variable rate");
    }

    function testFuzz_overallBorrowRate_OnlyStableDebt(
        uint256 stableDebt,
        uint256 stableRate
    ) public view {
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
        stableDebt = bound(stableDebt, 1e18, 1e30);
        variableDebt = bound(variableDebt, 1e18, 1e30);
        varRate = bound(varRate, 1e22, RAY / 2);
        stableRate = bound(stableRate, 1e22, RAY / 2);

        uint256 rate = h.exposed_getOverallBorrowRate(
            stableDebt, variableDebt, varRate, stableRate
        );
        uint256 minRate = varRate < stableRate ? varRate : stableRate;
        uint256 maxRate = varRate > stableRate ? varRate : stableRate;

        assertGe(rate + 1, minRate, "overall rate should be >= min component rate");
        assertLe(rate, maxRate + 1, "overall rate should be <= max component rate");
    }

    // ============================================================
    //                   calculateInterestRates
    // ============================================================

    function testFuzz_interestRates_ZeroDebtGivesBaseVariableRate(
        uint256 availableLiquidity
    ) public view {
        availableLiquidity = bound(availableLiquidity, 1, 1e24);

        (uint256 liquidityRate, , uint256 variableRate) = h
            .calculateInterestRates(reserve, availableLiquidity, 0, 0, 0, 0);

        assertEq(variableRate, BASE_VAR_RATE, "zero debt should give base variable rate");
        assertEq(liquidityRate, 0, "zero debt should give zero liquidity rate");
    }

    function testFuzz_interestRates_MonotonicVariableRateInDebt(
        uint256 availableLiquidity,
        uint256 debt1,
        uint256 debt2
    ) public view {
        availableLiquidity = bound(availableLiquidity, 1e6, 1e24);
        debt1 = bound(debt1, 0, 1e24);
        debt2 = bound(debt2, debt1, 1e24);

        (, , uint256 varRate1) = h.calculateInterestRates(
            reserve, availableLiquidity, 0, debt1, 0, 0
        );
        (, , uint256 varRate2) = h.calculateInterestRates(
            reserve, availableLiquidity, 0, debt2, 0, 0
        );

        assertLe(varRate1, varRate2, "variable rate should increase with more debt");
    }

    function testFuzz_interestRates_VariableRateAlwaysGteBase(
        uint256 availableLiquidity,
        uint256 totalVariableDebt
    ) public view {
        availableLiquidity = bound(availableLiquidity, 1, 1e24);
        totalVariableDebt = bound(totalVariableDebt, 0, 1e24);

        (, , uint256 variableRate) = h.calculateInterestRates(
            reserve, availableLiquidity, 0, totalVariableDebt, 0, 0
        );

        assertGe(variableRate, BASE_VAR_RATE, "variable rate should always be >= base rate");
    }

    function testFuzz_interestRates_VariableRateBelowMax(
        uint256 availableLiquidity,
        uint256 totalVariableDebt
    ) public view {
        availableLiquidity = bound(availableLiquidity, 1, 1e24);
        totalVariableDebt = bound(totalVariableDebt, 0, 1e24);

        (, , uint256 variableRate) = h.calculateInterestRates(
            reserve, availableLiquidity, 0, totalVariableDebt, 0, 0
        );

        uint256 maxRate = h.getMaxVariableBorrowRate();
        assertLe(variableRate, maxRate, "variable rate should never exceed max rate");
    }

    function testFuzz_interestRates_FullReserveFactorZerosLiquidityRate(
        uint256 availableLiquidity,
        uint256 totalVariableDebt
    ) public view {
        availableLiquidity = bound(availableLiquidity, 1, 1e24);
        totalVariableDebt = bound(totalVariableDebt, 1, 1e24);

        (uint256 liquidityRate, , ) = h.calculateInterestRates(
            reserve, availableLiquidity, 0, totalVariableDebt, 0, BPS
        );

        assertEq(liquidityRate, 0, "100% reserve factor should zero out liquidity rate");
    }

    function testFuzz_interestRates_ReserveFactorReducesLiquidityRate(
        uint256 availableLiquidity,
        uint256 totalVariableDebt,
        uint256 rf1,
        uint256 rf2
    ) public view {
        availableLiquidity = bound(availableLiquidity, 1e6, 1e24);
        totalVariableDebt = bound(totalVariableDebt, 1e6, 1e24);
        rf1 = bound(rf1, 0, BPS);
        rf2 = bound(rf2, rf1, BPS);

        (uint256 liqRate1, , ) = h.calculateInterestRates(
            reserve, availableLiquidity, 0, totalVariableDebt, 0, rf1
        );
        (uint256 liqRate2, , ) = h.calculateInterestRates(
            reserve, availableLiquidity, 0, totalVariableDebt, 0, rf2
        );

        assertGe(liqRate1, liqRate2, "higher reserve factor should reduce liquidity rate");
    }

    function testFuzz_interestRates_ReserveFactorDoesNotAffectBorrowRates(
        uint256 availableLiquidity,
        uint256 totalVariableDebt,
        uint256 rf1,
        uint256 rf2
    ) public view {
        availableLiquidity = bound(availableLiquidity, 1e6, 1e24);
        totalVariableDebt = bound(totalVariableDebt, 1e6, 1e24);
        rf1 = bound(rf1, 0, BPS);
        rf2 = bound(rf2, 0, BPS);

        (, uint256 stableRate1, uint256 varRate1) = h.calculateInterestRates(
            reserve, availableLiquidity, 0, totalVariableDebt, 0, rf1
        );
        (, uint256 stableRate2, uint256 varRate2) = h.calculateInterestRates(
            reserve, availableLiquidity, 0, totalVariableDebt, 0, rf2
        );

        assertEq(varRate1, varRate2, "reserve factor should not affect variable borrow rate");
        assertEq(stableRate1, stableRate2, "reserve factor should not affect stable borrow rate");
    }

    function testFuzz_interestRates_AboveOptimalHigherThanBelowOptimal(
        uint256 availableLiquidity
    ) public view {
        availableLiquidity = bound(availableLiquidity, 1e8, 1e24);

        // ~70% utilization (below optimal 80%)
        uint256 debtBelow = (availableLiquidity * 70) / 30;
        // ~90% utilization (above optimal 80%)
        uint256 debtAbove = (availableLiquidity * 90) / 10;

        (, , uint256 varRateBelow) = h.calculateInterestRates(
            reserve, availableLiquidity, 0, debtBelow, 0, 0
        );
        (, , uint256 varRateAbove) = h.calculateInterestRates(
            reserve, availableLiquidity, 0, debtAbove, 0, 0
        );

        assertLt(varRateBelow, varRateAbove, "rate above optimal utilization should be higher");
    }

    function testFuzz_interestRates_MonotonicInStableRate(
        uint256 availableLiquidity,
        uint256 stableDebt1,
        uint256 stableDebt2
    ) public view {
        availableLiquidity = bound(availableLiquidity, 1e6, 1e24);
        stableDebt1 = bound(stableDebt1, 0, 1e24);
        stableDebt2 = bound(stableDebt2, stableDebt1, 1e24);

        (, uint256 stableRate1, ) = h.calculateInterestRates(
            reserve, availableLiquidity, stableDebt1, 0, 0, 0
        );
        (, uint256 stableRate2, ) = h.calculateInterestRates(
            reserve, availableLiquidity, stableDebt2, 0, 0, 0
        );

        assertLe(stableRate1, stableRate2, "stable rate should increase with more stable debt");
    }
}
