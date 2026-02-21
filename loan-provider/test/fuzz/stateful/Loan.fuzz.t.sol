// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {LoanUnitTestBase} from "../../base/LoanUnitTestBase.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";

/**
 * @title LoanFuzzTest
 * @author Bitmor Protocol
 * @notice Fuzz tests for Loan contract
 * @dev Tests loan initialization, repayment, and closure with fuzzed parameters
 *
 * ## Test Coverage
 * - Loan initialization with valid inputs creates correct state
 * - Input validation reverts appropriately for invalid parameters
 * - Repayment correctly reduces debt
 * - Multiple repayments accumulate correctly
 * - Loan closure returns collateral to borrower
 *
 * @custom:audit-category Core Functionality, Input Validation
 */
contract LoanFuzzTest is LoanUnitTestBase {
    // ============ Setup ============

    function setUp() public override {
        super.setUp();
    }

    // ============ Initialization Tests ============

    /**
     * @notice Verifies that loan initialization creates a valid LSA with correct state
     * @dev Fuzz inputs: collateral amount, deposit amount, duration
     * @param collateralSeed Seed for bounded collateral amount
     * @param depositSeed Seed for bounded deposit amount
     * @param durationSeed Seed for bounded duration
     * @custom:audit-property LOAN-01: Loan initialization creates valid LSA with correct state
     * @custom:audit-category Core Functionality
     * @custom:audit-severity Critical
     */
    function testFuzz_InitializeLoan_CreatesValidLSA(uint256 collateralSeed, uint256 depositSeed, uint256 durationSeed)
        public
    {
        // Bound inputs to valid ranges
        uint256 collateral = _boundCollateral(collateralSeed);
        uint256 duration = _boundDuration(durationSeed);
        uint256 btcPrice = mockOracle.getAssetPrice(address(mockCbBTC));
        uint256 collateralValueUsd = _getCollateralValueUsd(collateral, btcPrice);
        uint256 deposit = _boundDeposit(collateralValueUsd, depositSeed);

        // Fund user with sufficient USDC
        _fundUSDCAndApprove(user, address(loan), deposit + FC.MAX_USDC_AMOUNT);

        // Initialize loan
        vm.prank(user);
        address lsa = loan.initializeLoan(deposit, 0, collateral, duration, "");

        // Assertions
        assertTrue(lsa != address(0), "LSA should be created and non-zero");

        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(loanData.borrower, user, "borrower should be user");
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Active), "status should be Active");
        assertEq(loanData.duration, duration, "duration should match input");
        assertGt(loanData.loanAmount, 0, "loan amount should be positive");
        assertGt(loanData.estimatedMonthlyPayment, 0, "monthly payment should be positive");
    }

    /**
     * @notice Verifies that insufficient deposit reverts with correct error
     * @dev Tests deposits below the 30% minimum requirement
     * @param collateralSeed Seed for bounded collateral amount
     * @param depositSeed Seed for insufficient deposit (below 30%)
     * @param durationSeed Seed for bounded duration
     * @custom:audit-property LOAN-02: Insufficient deposit reverts with correct error
     * @custom:audit-category Input Validation
     * @custom:audit-severity High
     */
    function testFuzz_InitializeLoan_RevertsOnInsufficientDeposit(
        uint256 collateralSeed,
        uint256 depositSeed,
        uint256 durationSeed
    ) public {
        // Bound inputs
        uint256 collateral = _boundCollateral(collateralSeed);
        uint256 duration = _boundDuration(durationSeed);
        uint256 btcPrice = mockOracle.getAssetPrice(address(mockCbBTC));
        uint256 collateralValueUsd = _getCollateralValueUsd(collateral, btcPrice);

        // Get insufficient deposit (below minimum)
        uint256 deposit = _boundInsufficientDeposit(collateralValueUsd, depositSeed);

        // Skip if deposit would be 0 (edge case handled by ZeroAmount check)
        vm.assume(deposit > 0);

        // Fund user
        _fundUSDCAndApprove(user, address(loan), deposit);

        // Expect revert with InsufficientDeposit error
        vm.expectRevert(Errors.InsufficientDeposit.selector);
        vm.prank(user);
        loan.initializeLoan(deposit, 0, collateral, duration, "");
    }

    /**
     * @notice Verifies that zero collateral reverts
     * @dev Tests the validation that prevents zero collateral loans
     * @param depositSeed Seed for bounded deposit amount
     * @param durationSeed Seed for bounded duration
     * @custom:audit-property LOAN-03: Zero collateral reverts
     * @custom:audit-category Input Validation
     * @custom:audit-severity High
     */
    function testFuzz_InitializeLoan_RevertsOnZeroCollateral(uint256 depositSeed, uint256 durationSeed) public {
        uint256 duration = _boundDuration(durationSeed);
        uint256 deposit = _boundUsdcAmount(depositSeed);

        _fundUSDCAndApprove(user, address(loan), deposit);

        // Zero collateral triggers ZeroAmount before the min collateral check
        vm.expectRevert(Errors.ZeroAmount.selector);
        vm.prank(user);
        loan.initializeLoan(deposit, 0, 0, duration, "");
    }

    // ============ Repayment Tests ============

    /**
     * @notice Verifies that repayment reduces debt
     * @dev Creates a loan and verifies debt decreases after repayment
     * @param collateralSeed Seed for bounded collateral amount
     * @param repaymentSeed Seed for repayment amount
     * @custom:audit-property LOAN-04: Repayment reduces debt
     * @custom:audit-category Core Functionality
     * @custom:audit-severity Critical
     */
    function testFuzz_Repay_ReducesDebt(uint256 collateralSeed, uint256 repaymentSeed) public {
        // Create loan with fuzzed collateral
        uint256 collateral = _boundCollateral(collateralSeed);
        address lsa = _createLoanWithCollateral(collateral);

        // Get debt before repayment
        uint256 debtBefore = _getDebtBalance(lsa);
        vm.assume(debtBefore > FC.MIN_USDC_AMOUNT);

        // Bound repayment to valid range
        uint256 repayment = bound(repaymentSeed, FC.MIN_USDC_AMOUNT, debtBefore);

        // Fund user and advance time to allow repayment
        _fundUSDCAndApprove(user, address(loan), repayment);
        vm.warp(block.timestamp + 30 days);

        // Execute repayment
        vm.prank(user);
        loan.repay(lsa, repayment);

        // Assert debt decreased
        uint256 debtAfter = _getDebtBalance(lsa);
        assertLt(debtAfter, debtBefore, "debt should decrease after repayment");
    }

    /**
     * @notice Verifies that multiple repayments accumulate correctly
     * @dev Tests that consecutive repayments each reduce debt
     * @param collateralSeed Seed for bounded collateral amount
     * @param repayment1Seed Seed for first repayment amount
     * @param repayment2Seed Seed for second repayment amount
     * @custom:audit-property LOAN-05: Multiple repayments accumulate correctly
     * @custom:audit-category Core Functionality
     * @custom:audit-severity High
     */
    function testFuzz_Repay_MultipleRepayments(uint256 collateralSeed, uint256 repayment1Seed, uint256 repayment2Seed)
        public
    {
        // Create loan
        uint256 collateral = _boundCollateral(collateralSeed);
        address lsa = _createLoanWithCollateral(collateral);

        uint256 debtBefore = _getDebtBalance(lsa);
        vm.assume(debtBefore > FC.MIN_USDC_AMOUNT * 3);

        // First repayment (up to 1/3 of debt)
        uint256 repayment1 = bound(repayment1Seed, FC.MIN_USDC_AMOUNT, debtBefore / 3);
        _fundUSDCAndApprove(user, address(loan), repayment1);
        vm.warp(block.timestamp + 30 days);
        vm.prank(user);
        loan.repay(lsa, repayment1);

        uint256 debtAfter1 = _getDebtBalance(lsa);
        assertLt(debtAfter1, debtBefore, "debt should decrease after first repayment");

        // Second repayment
        vm.assume(debtAfter1 > FC.MIN_USDC_AMOUNT);
        uint256 repayment2 = bound(repayment2Seed, FC.MIN_USDC_AMOUNT, debtAfter1 / 2);
        _fundUSDCAndApprove(user, address(loan), repayment2);
        vm.warp(block.timestamp + 30 days);
        vm.prank(user);
        loan.repay(lsa, repayment2);

        uint256 debtAfter2 = _getDebtBalance(lsa);

        // Assert cumulative reduction
        assertLt(debtAfter2, debtAfter1, "debt should decrease after second repayment");
        assertLt(debtAfter2, debtBefore, "final debt should be less than original");
    }

    // ============ Closure Tests ============

    /**
     * @notice Verifies that loan closure returns collateral to borrower
     * @dev Tests that closing a loan transfers BTC back to the user
     * @param collateralSeed Seed for bounded collateral amount
     * @custom:audit-property LOAN-06: Loan closure returns collateral
     * @custom:audit-category Core Functionality
     * @custom:audit-severity Critical
     */
    function testFuzz_CloseLoan_ReturnsCollateral(uint256 collateralSeed) public {
        // Create loan
        uint256 collateral = _boundCollateral(collateralSeed);
        address lsa = _createLoanWithCollateral(collateral);

        // Get user BTC balance before closure
        uint256 btcBefore = mockCbBTC.balanceOf(user);

        // Fund user for closure (need to cover debt + fees)
        uint256 debt = _getDebtBalance(lsa);
        _fundUSDCAndApprove(user, address(loan), debt + FC.MAX_USDC_AMOUNT);

        // Close loan with BTC withdrawal
        vm.prank(user);
        loan.closeLoan(lsa, true);

        // Assert collateral returned
        uint256 btcAfter = mockCbBTC.balanceOf(user);
        assertGt(btcAfter, btcBefore, "user should receive BTC collateral after closure");

        // Assert loan status is Completed
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Completed), "loan should be completed");
    }

    // ============ Internal Helpers ============

    /**
     * @notice Bounds collateral to valid range using Loan contract parameters
     * @param raw The raw fuzzed input
     * @return The bounded collateral amount
     */
    function _boundCollateral(uint256 raw) internal view returns (uint256) {
        uint256 maxBTC = loan.getMaxBTCAmount();
        uint256 minBTC = loan.getMinBTCAmount();
        return bound(raw, minBTC, maxBTC);
    }

    /**
     * @notice Creates a loan with specified collateral amount
     * @dev Uses `loan.getLoanDetails()` to get exact minimum deposit from the contract,
     *      which internally uses `s_minDeposit` (the min deposit BPS variable)
     * @param collateral The collateral amount in cbBTC (8 decimals)
     * @return lsa The created Loan Specific Address
     */
    function _createLoanWithCollateral(uint256 collateral) internal returns (address) {
        (,, uint256 minDeposit) = loan.getLoanDetails(collateral, FC.MIN_DURATION);

        _fundUSDCAndApprove(user, address(loan), minDeposit);

        vm.prank(user);
        return loan.initializeLoan(minDeposit, 0, collateral, FC.MIN_DURATION, "");
    }

    /**
     * @notice Calculates collateral value in USD
     * @param collateralAmount BTC amount (8 decimals)
     * @param btcPrice BTC price in USD (8 decimals)
     * @return Collateral value in USD (8 decimals)
     */
    function _getCollateralValueUsd(uint256 collateralAmount, uint256 btcPrice) internal pure returns (uint256) {
        return (collateralAmount * btcPrice) / 1e8;
    }

    /**
     * @notice Bounds raw input to valid deposit range based on collateral value
     * @param collateralValueUsd The collateral value in USD (8 decimals)
     * @param raw The raw fuzzed input
     * @return The bounded deposit amount in USDC (6 decimals)
     */
    function _boundDeposit(uint256 collateralValueUsd, uint256 raw) internal pure returns (uint256) {
        uint256 minDepositUsd = (collateralValueUsd * FC.MIN_DEPOSIT_BPS) / FC.BPS_DENOMINATOR;
        // Cap at 90% of collateral to ensure non-zero loan amount
        uint256 maxDepositUsd = (collateralValueUsd * 90) / 100;

        // Convert to USDC (6 decimals) from USD (8 decimals)
        uint256 minDepositUsdc = (minDepositUsd * 1e6) / 1e8;
        uint256 maxDepositUsdc = (maxDepositUsd * 1e6) / 1e8;

        // Ensure min <= max
        if (minDepositUsdc >= maxDepositUsdc) {
            return maxDepositUsdc;
        }

        return bound(raw, minDepositUsdc, maxDepositUsdc);
    }

    /**
     * @notice Bounds deposit to be below minimum (for revert tests)
     * @param collateralValueUsd The collateral value in USD (8 decimals)
     * @param raw The raw fuzzed input
     * @return The bounded insufficient deposit amount
     */
    function _boundInsufficientDeposit(uint256 collateralValueUsd, uint256 raw) internal pure returns (uint256) {
        uint256 minDepositUsd = (collateralValueUsd * FC.MIN_DEPOSIT_BPS) / FC.BPS_DENOMINATOR;
        uint256 minDepositUsdc = (minDepositUsd * 1e6) / 1e8;

        if (minDepositUsdc <= 1) {
            return 0;
        }

        return bound(raw, 1, minDepositUsdc - 1);
    }

    /**
     * @notice Bounds raw input to valid loan duration range
     * @param raw The raw fuzzed input
     * @return The bounded duration (1 - 60 months)
     */
    function _boundDuration(uint256 raw) internal pure returns (uint256) {
        return bound(raw, FC.MIN_DURATION, FC.MAX_DURATION);
    }

    /**
     * @notice Bounds raw input to valid USDC amount range
     * @param raw The raw fuzzed input
     * @return The bounded USDC amount (1 - 10M USDC)
     */
    function _boundUsdcAmount(uint256 raw) internal pure returns (uint256) {
        return bound(raw, FC.MIN_USDC_AMOUNT, FC.MAX_USDC_AMOUNT);
    }
}
