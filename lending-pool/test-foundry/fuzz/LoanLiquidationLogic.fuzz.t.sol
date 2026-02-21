// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.13 <0.9.0;

import "forge-std/Test.sol";

interface IMockBalanceToken {
    function setBalance(address user, uint256 amount) external;
}

interface IMockOracleForLiquidation {
    function setAssetPrice(address asset, uint256 price) external;
}

interface IMockLoanForLiquidation {
    function setLoanData(
        address borrower,
        uint256 depositAmount,
        uint256 loanAmount,
        uint256 collateralAmount,
        uint256 estimatedMonthlyPayment,
        uint256 duration,
        uint256 createdAt,
        uint256 insuranceID,
        uint256 lastPaymentTimestamp,
        uint8 status
    ) external;
    function setCollateralAsset(address asset) external;
    function setDebtAsset(address asset) external;
    function setGracePeriod(uint256 period) external;
    function setRepaymentInterval(uint256 interval) external;
}

interface ILoanLiquidationLogicHarness {
    function setReserveConfigData(address asset, uint256 configData) external;
    function setReserveVariableDebtToken(address asset, address token) external;
    function setReserveStableDebtToken(address asset, address token) external;
    function setReserveAToken(address asset, address token) external;
    function checkTypeOfLiquidation(
        address user,
        uint256 hf,
        address oracle,
        address bitmorLoan
    ) external view returns (uint256);
}

contract LoanLiquidationLogicFuzzTest is Test {
    ILoanLiquidationLogicHarness h;
    IMockOracleForLiquidation oracle;
    IMockLoanForLiquidation mockLoan;
    IMockBalanceToken stableDebtToken;
    IMockBalanceToken variableDebtToken;
    IMockBalanceToken collateralAToken;

    address constant USER = address(0xBEEF);
    address collateralAsset;
    address debtAsset;

    uint256 constant RAY = 1e27;
    uint256 constant HF_THRESHOLD = 1e18; // GenericLogic.HEALTH_FACTOR_LIQUIDATION_THRESHOLD
    uint256 constant ONE_DAY = 1 days;
    uint256 constant ONE_MONTH = 30 days;

    // Reserve config bitmap constants
    uint256 constant DECIMALS_SHIFT = 48;
    uint256 constant LIQ_BONUS_SHIFT = 32;

    // Status enum values matching DataTypes.LoanStatus
    uint8 constant STATUS_ACTIVE = 0;
    uint8 constant STATUS_COMPLETED = 1;
    uint8 constant STATUS_LIQUIDATED = 2;

    function setUp() public {
        // Warp to a realistic timestamp to avoid underflow in block.timestamp arithmetic
        vm.warp(365 days);

        collateralAsset = makeAddr("collateral");
        debtAsset = makeAddr("debt");

        // Deploy mocks
        address oracleAddr = deployCode(
            "LoanLiquidationLogicHarness.sol:MockOracleForLiquidation"
        );
        oracle = IMockOracleForLiquidation(oracleAddr);

        address loanAddr = deployCode(
            "LoanLiquidationLogicHarness.sol:MockLoanForLiquidation"
        );
        mockLoan = IMockLoanForLiquidation(loanAddr);

        address stableAddr = deployCode(
            "LoanLiquidationLogicHarness.sol:MockBalanceToken"
        );
        stableDebtToken = IMockBalanceToken(stableAddr);

        address variableAddr = deployCode(
            "LoanLiquidationLogicHarness.sol:MockBalanceToken"
        );
        variableDebtToken = IMockBalanceToken(variableAddr);

        address collateralATokenAddr = deployCode(
            "LoanLiquidationLogicHarness.sol:MockBalanceToken"
        );
        collateralAToken = IMockBalanceToken(collateralATokenAddr);

        // Deploy harness
        address harnessAddr = deployCode(
            "LoanLiquidationLogicHarness.sol:LoanLiquidationLogicHarness"
        );
        h = ILoanLiquidationLogicHarness(harnessAddr);

        // Configure collateral asset and debt asset in mock loan
        mockLoan.setCollateralAsset(collateralAsset);
        mockLoan.setDebtAsset(debtAsset);
        mockLoan.setGracePeriod(7 days);
        mockLoan.setRepaymentInterval(ONE_MONTH);

        // Configure reserve: collateral = 8 decimals, liq bonus 10500 (105%)
        uint256 collateralConfig = (uint256(8) << DECIMALS_SHIFT) |
            (uint256(10500) << LIQ_BONUS_SHIFT);
        h.setReserveConfigData(collateralAsset, collateralConfig);

        // Configure reserve: debt = 6 decimals
        uint256 debtConfig = (uint256(6) << DECIMALS_SHIFT);
        h.setReserveConfigData(debtAsset, debtConfig);

        // Set debt token addresses
        h.setReserveStableDebtToken(debtAsset, address(stableDebtToken));
        h.setReserveVariableDebtToken(debtAsset, address(variableDebtToken));

        // Set collateral aToken address (required by Helpers.getUserCurrentCollateral)
        h.setReserveAToken(collateralAsset, address(collateralAToken));

        // Default oracle prices: BTC = $60,000 (8 decimals), USDC = $1 (8 decimals)
        oracle.setAssetPrice(collateralAsset, 60_000e8);
        oracle.setAssetPrice(debtAsset, 1e8);
    }

    /// @dev Helper to build an active loan with standard parameters
    function _setActiveLoan(
        uint256 collateralAmount,
        uint256 estimatedMonthlyPayment,
        uint256 duration,
        uint256 insuranceID,
        uint256 lastPaymentTimestamp
    ) internal {
        mockLoan.setLoanData(
            USER,
            1000e6, // depositAmount
            10000e6, // loanAmount
            collateralAmount,
            estimatedMonthlyPayment,
            duration,
            block.timestamp - 60 days, // createdAt
            insuranceID,
            lastPaymentTimestamp,
            STATUS_ACTIVE
        );

        // Mirror collateral in the aToken so Helpers.getUserCurrentCollateral reads the correct value
        collateralAToken.setBalance(USER, collateralAmount);
    }

    // ============================================================
    //      Inactive loan → 0
    // ============================================================

    function testFuzz_completedLoanReturnsZero(uint256 hf) public {
        hf = bound(hf, 0, type(uint128).max);

        mockLoan.setLoanData(
            USER, 0, 0, 1e8, 500e6, 12, block.timestamp, 0, 0, STATUS_COMPLETED
        );

        uint256 result = h.checkTypeOfLiquidation(
            USER,
            hf,
            address(oracle),
            address(mockLoan)
        );
        assertEq(result, 0, "completed loan should return 0");
    }

    function testFuzz_liquidatedLoanReturnsZero(uint256 hf) public {
        hf = bound(hf, 0, type(uint128).max);

        mockLoan.setLoanData(
            USER, 0, 0, 1e8, 500e6, 12, block.timestamp, 0, 0, STATUS_LIQUIDATED
        );

        uint256 result = h.checkTypeOfLiquidation(
            USER,
            hf,
            address(oracle),
            address(mockLoan)
        );
        assertEq(result, 0, "liquidated loan should return 0");
    }

    // ============================================================
    //      Uninsured + HF < threshold → 1 (full liquidation)
    // ============================================================

    function testFuzz_uninsuredLowHfReturnsOne(uint256 hf) public {
        // insuranceID == 0 AND hf < 1e18 → return 1
        hf = bound(hf, 0, HF_THRESHOLD - 1);

        _setActiveLoan(
            1e8, // 1 BTC collateral
            500e6, // $500 monthly payment
            12, // 12 months
            0, // uninsured
            block.timestamp // just paid
        );

        uint256 result = h.checkTypeOfLiquidation(
            USER,
            hf,
            address(oracle),
            address(mockLoan)
        );
        assertEq(
            result,
            1,
            "uninsured loan with HF < threshold should return 1 (full liquidation)"
        );
    }

    function testFuzz_insuredLowHfDoesNotReturnOne(uint256 hf, uint256 insuranceID) public {
        // When insured (insuranceID > 0) and HF < threshold,
        // the uninsured+low HF check does NOT trigger → falls through to overdue check
        hf = bound(hf, 0, HF_THRESHOLD - 1);
        insuranceID = bound(insuranceID, 1, 1e18);

        _setActiveLoan(
            1e8,
            500e6,
            12,
            insuranceID, // insured
            block.timestamp // just paid → not overdue
        );

        uint256 result = h.checkTypeOfLiquidation(
            USER,
            hf,
            address(oracle),
            address(mockLoan)
        );
        // Insured + not overdue → return 0 (not 1)
        assertEq(
            result,
            0,
            "insured loan with HF < threshold but not overdue should return 0"
        );
    }

    // ============================================================
    //      Not overdue → 0
    // ============================================================

    function testFuzz_notOverdueReturnsZero(uint256 hf, uint256 insuranceID) public {
        // Loan just paid, not overdue → return 0
        hf = bound(hf, HF_THRESHOLD, type(uint128).max); // healthy HF
        insuranceID = bound(insuranceID, 1, 1e18); // insured (to skip uninsured check)

        _setActiveLoan(
            1e8,
            500e6,
            12,
            insuranceID,
            block.timestamp // lastPayment = now → not overdue
        );

        uint256 result = h.checkTypeOfLiquidation(
            USER,
            hf,
            address(oracle),
            address(mockLoan)
        );
        assertEq(result, 0, "not overdue loan should return 0");
    }

    // ============================================================
    //      Overdue: micro vs full liquidation
    // ============================================================

    function testFuzz_sufficientCollateralReturnsMicro(
        uint256 collateralAmount,
        uint256 monthlyPayment
    ) public {
        // Large collateral relative to debt → micro liquidation (2)
        // Guard check requires: remainingCollateral >= (debt - monthly) * bonus
        // So we need enough collateral to cover total debt * bonus after micro-liq
        collateralAmount = bound(collateralAmount, 1e8, 10e8); // 1 to 10 BTC ($60k-$600k)
        monthlyPayment = bound(monthlyPayment, 100e6, 500e6); // $100 - $500

        // Make loan overdue: lastPayment far in the past
        uint256 lastPayment = block.timestamp - 60 days;

        _setActiveLoan(
            collateralAmount,
            monthlyPayment,
            6, // 6 months duration → debt = monthly * 6
            1, // insured (skip uninsured+HF check)
            lastPayment
        );

        // Set debt balance = monthlyPayment * 6 (moderate total debt)
        variableDebtToken.setBalance(USER, monthlyPayment * 6);
        stableDebtToken.setBalance(USER, 0);

        // With BTC at $60,000 and collateral >= 1 BTC ($60,000),
        // and total debt <= $3,000, collateral easily covers guard amount
        uint256 result = h.checkTypeOfLiquidation(
            USER,
            HF_THRESHOLD, // healthy HF
            address(oracle),
            address(mockLoan)
        );
        assertEq(
            result,
            2,
            "sufficient collateral should allow micro liquidation"
        );
    }

    function testFuzz_insufficientCollateralReturnsFull(
        uint256 monthlyPayment
    ) public {
        // Tiny collateral, large monthly payment → full liquidation (1)
        monthlyPayment = bound(monthlyPayment, 50_000e6, 100_000e6); // $50k - $100k

        // Very small collateral: 0.001 BTC = $60 at $60,000/BTC
        uint256 collateralAmount = 0.001e8;
        uint256 lastPayment = block.timestamp - 60 days;

        _setActiveLoan(
            collateralAmount,
            monthlyPayment,
            12,
            1, // insured
            lastPayment
        );

        variableDebtToken.setBalance(USER, monthlyPayment * 12);
        stableDebtToken.setBalance(USER, 0);

        // $60 collateral vs $50,000+ monthly payment → collateral insufficient
        uint256 result = h.checkTypeOfLiquidation(
            USER,
            HF_THRESHOLD,
            address(oracle),
            address(mockLoan)
        );
        assertEq(
            result,
            1,
            "insufficient collateral should trigger full liquidation"
        );
    }

    function testFuzz_lowDebtAllowsMicro(uint256 currentDebt) public {
        // When current debt is low, amountToBeDeducted = min(monthly, currentDebt) is small
        // → micro liquidation should be possible with sufficient collateral
        currentDebt = bound(currentDebt, 100e6, 500e6); // $100 - $500

        uint256 lastPayment = block.timestamp - 60 days;

        _setActiveLoan(
            1e8, // 1 BTC = $60,000
            10_000e6, // $10,000 monthly payment (larger than debt)
            12,
            1, // insured
            lastPayment
        );

        variableDebtToken.setBalance(USER, currentDebt);
        stableDebtToken.setBalance(USER, 0);

        // min(10000, currentDebt) = currentDebt (small)
        // totalDeducted = currentDebt * 10500 / 10000 (with bonus)
        // This should be well within $60,000 collateral
        uint256 result = h.checkTypeOfLiquidation(
            USER,
            HF_THRESHOLD,
            address(oracle),
            address(mockLoan)
        );
        assertEq(result, 2, "low debt should allow micro liquidation");
    }

    function testFuzz_resultIsAlwaysZeroOneOrTwo(
        uint256 hf,
        uint256 insuranceID,
        uint256 collateralAmount,
        uint256 monthlyPayment,
        uint256 currentDebt,
        uint256 elapsedDays
    ) public {
        // checkTypeOfLiquidation can only return 0, 1, or 2
        hf = bound(hf, 0, type(uint128).max);
        insuranceID = bound(insuranceID, 0, 10);
        collateralAmount = bound(collateralAmount, 1e5, 10e8); // 0.001 to 10 BTC
        monthlyPayment = bound(monthlyPayment, 100e6, 10_000e6);
        currentDebt = bound(currentDebt, 100e6, 100_000e6);
        elapsedDays = bound(elapsedDays, 0, 300);

        uint256 lastPayment = block.timestamp - elapsedDays * ONE_DAY;

        _setActiveLoan(
            collateralAmount,
            monthlyPayment,
            12,
            insuranceID,
            lastPayment
        );

        variableDebtToken.setBalance(USER, currentDebt);
        stableDebtToken.setBalance(USER, 0);

        uint256 result = h.checkTypeOfLiquidation(
            USER,
            hf,
            address(oracle),
            address(mockLoan)
        );
        assertTrue(
            result <= 2,
            "checkTypeOfLiquidation should only return 0, 1, or 2"
        );
    }

    function testFuzz_higherCollateralPriceDoesNotDowngrade(
        uint256 price1,
        uint256 price2
    ) public {
        // Higher collateral price should never downgrade from micro(2) to full(1)
        // (it can only make micro more likely)
        price1 = bound(price1, 30_000e8, 100_000e8);
        price2 = bound(price2, price1, 200_000e8);

        uint256 lastPayment = block.timestamp - 60 days;
        _setActiveLoan(1e8, 500e6, 12, 1, lastPayment);
        variableDebtToken.setBalance(USER, 6000e6);
        stableDebtToken.setBalance(USER, 0);

        oracle.setAssetPrice(collateralAsset, price1);
        uint256 result1 = h.checkTypeOfLiquidation(
            USER,
            HF_THRESHOLD,
            address(oracle),
            address(mockLoan)
        );

        oracle.setAssetPrice(collateralAsset, price2);
        uint256 result2 = h.checkTypeOfLiquidation(
            USER,
            HF_THRESHOLD,
            address(oracle),
            address(mockLoan)
        );

        // If result1 is micro(2), result2 should also be micro(2) or stay same
        // Higher price can only help, never make things worse
        if (result1 == 2) {
            assertEq(
                result2,
                2,
                "higher collateral price should not downgrade micro to full"
            );
        }
    }
}
