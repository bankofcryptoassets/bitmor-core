// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {LoanFuzzTestBase} from "../base/LoanFuzzTestBase.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";
import {TestConstants as TC} from "../../helpers/TestConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";

/**
 * @title InitializeLoanFuzzTest
 * @author Bitmor Protocol
 * @notice Stateless fuzz tests for `Loan.initializeLoan()` via `LoanLogic.executeInitializeLoan()`
 * @dev Tests 8 properties covering premium routing, user cost, storage integrity,
 *      multi-loan indexing, price monotonicity, view-execution consistency,
 *      data parameter robustness, and loan amount bounds.
 *
 * @custom:audit-category Core Functionality, Financial Safety, Storage Integrity
 */
contract InitializeLoanFuzzTest is LoanFuzzTestBase {
    // ============ Bound Helpers ============

    /**
     * @notice Bounds premium to [0, FC.MAX_PREMIUM]
     * @param raw Raw fuzz input to bound
     */
    function _boundPremium(uint256 raw) internal pure returns (uint256) {
        return bound(raw, 0, FC.MAX_PREMIUM);
    }

    /**
     * @notice Funds user with USDC and approves the loan contract
     * @param amount Amount of USDC to fund
     */
    function _fundAndApprove(uint256 amount) internal {
        _fundUSDC(user, amount);
        vm.prank(user);
        mockUSDC.approve(address(loan), type(uint256).max);
    }

    /**
     * @notice Creates a loan with explicit parameters, funding user as needed
     * @param deposit Deposit amount in USDC
     * @param premium Premium amount in USDC
     * @param collateral Collateral amount in cbBTC
     * @param duration Loan duration in months
     */
    function _createLoanFull(uint256 deposit, uint256 premium, uint256 collateral, uint256 duration)
        internal
        returns (address lsa)
    {
        _fundAndApprove(deposit + premium + TC.USER_USDC_BALANCE);
        vm.prank(user);
        lsa = loan.initializeLoan(deposit, premium, collateral, duration, "");
    }

    /**
     * @notice For any premium in [0, 100k USDC], the premium collector's balance must
     *         increase by exactly that amount during loan initialization.
     * @dev Catches token routing errors where premium is misdirected or leaked.
     *      Existing unit tests only cover zero-premium case.
     * @param collateralSeed Seed for bounded collateral amount
     * @param durationSeed Seed for bounded duration
     * @param premiumSeed Seed for bounded premium amount
     * @custom:audit-property Premium routing correctness
     * @custom:audit-category Financial Safety
     * @custom:audit-severity Critical
     */
    function testFuzz_InitializeLoan_PremiumTransfersToCollector(
        uint256 collateralSeed,
        uint256 durationSeed,
        uint256 premiumSeed
    ) public {
        uint256 collateral = _boundCollateral(collateralSeed);
        uint256 duration = _boundDuration(durationSeed);
        uint256 premium = _boundPremium(premiumSeed);

        (,, uint256 minDeposit) = loan.getLoanDetails(collateral, duration);

        address collector = loan.getPremiumCollector();
        uint256 collectorBefore = mockUSDC.balanceOf(collector);

        _fundAndApprove(minDeposit + premium + TC.USER_USDC_BALANCE);

        vm.prank(user);
        loan.initializeLoan(minDeposit, premium, collateral, duration, "");

        uint256 collectorAfter = mockUSDC.balanceOf(collector);

        assertEq(
            collectorAfter - collectorBefore,
            premium,
            "premium collector balance should increase by exactly the premium amount"
        );
    }

    /**
     * @notice User's USDC balance must decrease by exactly `deposit + premium`.
     *         The LSA must hold aTokens in the Bitmor lending pool, confirming the
     *         full flash loan -> swap -> vault deposit -> pool deposit pipeline.
     * @dev The flash loan fee routes through the LSA (Bitmor pool borrow), not the user.
     * @param collateralSeed Seed for bounded collateral amount
     * @param durationSeed Seed for bounded duration
     * @param depositSeed Seed for bounded deposit amount
     * @param premiumSeed Seed for bounded premium amount
     * @custom:audit-property User cost accuracy and collateral pipeline integrity
     * @custom:audit-category Financial Safety
     * @custom:audit-severity Critical
     */
    function testFuzz_InitializeLoan_UserCostAndCollateralPipeline(
        uint256 collateralSeed,
        uint256 durationSeed,
        uint256 depositSeed,
        uint256 premiumSeed
    ) public {
        uint256 collateral = _boundCollateral(collateralSeed);
        uint256 duration = _boundDuration(durationSeed);
        uint256 premium = _boundPremium(premiumSeed);

        (uint256 deposit,) = _boundValidDeposit(collateral, duration, depositSeed);

        _fundAndApprove(deposit + premium + TC.USER_USDC_BALANCE);
        uint256 userBefore = mockUSDC.balanceOf(user);

        vm.prank(user);
        address lsa = loan.initializeLoan(deposit, premium, collateral, duration, "");

        uint256 userAfter = mockUSDC.balanceOf(user);

        // User should only pay deposit + premium
        assertEq(userBefore - userAfter, deposit + premium, "user USDC decrease should equal deposit + premium exactly");

        // LSA should hold aTokens (collateral deposited into Bitmor lending pool)
        uint256 aTokenBalance = mockATokenBvBTC.balanceOf(lsa);
        assertGt(aTokenBalance, 0, "LSA should hold aTokens after initialization");
    }

    /**
     * @notice `depositAmount` and `btcAmount` stored in LoanData must exactly
     *         match the input parameters across all valid combinations.
     * @dev Catches storage truncation or precision loss at large values.
     * @param collateralSeed Seed for bounded collateral amount
     * @param durationSeed Seed for bounded duration
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property Storage integrity of loan parameters
     * @custom:audit-category Storage Integrity
     * @custom:audit-severity High
     */
    function testFuzz_InitializeLoan_StorageIntegrity(uint256 collateralSeed, uint256 durationSeed, uint256 depositSeed)
        public
    {
        uint256 collateral = _boundCollateral(collateralSeed);
        uint256 duration = _boundDuration(durationSeed);

        (uint256 deposit,) = _boundValidDeposit(collateral, duration, depositSeed);

        address lsa = _createLoanFull(deposit, 0, collateral, duration);

        DataTypes.LoanData memory data = loan.getLoanByLSA(lsa);

        assertEq(data.depositAmount, deposit, "stored depositAmount must match input");
        assertEq(data.btcAmount, collateral, "stored btcAmount must match input");
        assertEq(data.duration, duration, "stored duration must match input");
        assertEq(data.borrower, user, "stored borrower must match caller");
        assertEq(uint256(data.status), uint256(DataTypes.LoanStatus.Active), "status must be Active");
        assertGt(data.loanAmount, 0, "loanAmount must be positive");
        assertGt(data.estimatedMonthlyPayment, 0, "estimatedMonthlyPayment must be positive");
        assertEq(data.createdAt, block.timestamp, "createdAt must match current timestamp");
    }

    /**
     * @notice After creating N loans (fuzzed 2-5) for the same user, `userLoanCount`
     *         must equal N and each index (0..N-1) must map to the correct LSA in order.
     * @dev Tests the indexing loop at LoanLogic.sol:118-120 for off-by-one bugs.
     * @param loanCountSeed Seed for bounded loan count (2-5)
     * @custom:audit-property Multi-loan index correctness
     * @custom:audit-category Storage Integrity
     * @custom:audit-severity High
     */
    function testFuzz_InitializeLoan_MultiLoanIndexing(uint256 loanCountSeed) public {
        uint256 loanCount = bound(loanCountSeed, 2, 5);

        // Pre-fund user with enough USDC for all loans upfront
        _fundAndApprove(TC.USER_USDC_BALANCE);

        uint256 collateral = loan.getMinBTCAmount();
        uint256 duration = FC.MIN_DURATION;
        (,, uint256 minDeposit) = loan.getLoanDetails(collateral, duration);

        address[] memory lsas = new address[](loanCount);

        // Use a large base timestamp to avoid any collision with setUp state
        uint256 baseTimestamp = 1_000_000;

        for (uint256 i = 0; i < loanCount; i++) {
            // Each loan gets a unique timestamp with large gaps
            vm.warp(baseTimestamp + (i * 1000));

            vm.prank(user);
            lsas[i] = loan.initializeLoan(minDeposit, 0, collateral, duration, "");
        }

        // Verify loan count
        uint256 count = loan.getUserLoanCount(user);
        assertEq(count, loanCount, "userLoanCount must equal number of loans created");

        // Verify each index maps to the correct LSA in creation order
        for (uint256 i = 0; i < loanCount; i++) {
            address indexedLsa = loan.getUserLoanAtIndex(user, i);
            assertEq(indexedLsa, lsas[i], "LSA at index must match creation order");
        }

        // Verify getUserAllLoans returns the correct count
        DataTypes.LoanData[] memory allLoans = loan.getUserAllLoans(user);
        assertEq(allLoans.length, loanCount, "getUserAllLoans length must match loan count");
    }

    /**
     * @notice For the same collateral amount and deposit percentage, a higher BTC price
     *         must produce a higher loan amount. Tests oracle -> LoanMath monotonicity.
     * @dev Uses vm.snapshot to compare two price scenarios on identical state.
     * @param collateralSeed Seed for bounded collateral amount
     * @param durationSeed Seed for bounded duration
     * @param priceLowSeed Seed for bounded lower BTC price
     * @param priceHighSeed Seed for bounded higher BTC price
     * @custom:audit-property Price-to-loan monotonicity
     * @custom:audit-category Monotonicity
     * @custom:audit-severity High
     */
    function testFuzz_InitializeLoan_HigherPriceHigherLoan(
        uint256 collateralSeed,
        uint256 durationSeed,
        uint256 priceLowSeed,
        uint256 priceHighSeed
    ) public {
        uint256 collateral = _boundCollateral(collateralSeed);
        uint256 duration = _boundDuration(durationSeed);

        // Bound two distinct prices (at least $1k apart to avoid rounding edge cases)
        uint256 priceLow = bound(priceLowSeed, FC.MIN_BTC_PRICE, FC.MAX_BTC_PRICE - 1000e8);
        uint256 priceHigh = bound(priceHighSeed, priceLow + 1000e8, FC.MAX_BTC_PRICE);

        // Snapshot current state
        uint256 snapId = vm.snapshotState();

        // --- Scenario A: Low price ---
        mockOracle.setAssetPrice(address(mockCbBTC), priceLow);
        mockOracle.setAssetPrice(address(mockBTCVault), priceLow);

        // Use minimum deposit percentage for fair comparison
        (uint256 loanAmountLow,,) = loan.getLoanDetails(collateral, duration);

        // Revert to snapshot
        vm.revertToState(snapId);

        // --- Scenario B: High price ---
        mockOracle.setAssetPrice(address(mockCbBTC), priceHigh);
        mockOracle.setAssetPrice(address(mockBTCVault), priceHigh);

        (uint256 loanAmountHigh,,) = loan.getLoanDetails(collateral, duration);

        assertGt(
            loanAmountHigh,
            loanAmountLow,
            "higher BTC price must produce higher loan amount for same collateral and deposit percentage"
        );
    }

    /**
     * @notice A deposit at exactly the minimum returned by `getLoanDetails()` must always
     *         succeed for any valid collateral and duration. Tests view-execution consistency.
     * @dev `getLoanDetails` uses `currentVariableBorrowRate`; `executeInitializeLoan` uses
     *      `getMaxVariableBorrowRate`. The min deposit calculation is rate-independent, so
     *      both paths must agree. Rounding mismatch between `fullMulDivUp` paths is the target.
     * @param collateralSeed Seed for bounded collateral amount
     * @param durationSeed Seed for bounded duration
     * @custom:audit-property View-execution min deposit consistency
     * @custom:audit-category Core Functionality
     * @custom:audit-severity Critical
     */
    function testFuzz_InitializeLoan_ExactMinDepositSucceeds(uint256 collateralSeed, uint256 durationSeed) public {
        uint256 collateral = _boundCollateral(collateralSeed);
        uint256 duration = _boundDuration(durationSeed);

        (,, uint256 minDeposit) = loan.getLoanDetails(collateral, duration);

        _fundAndApprove(minDeposit + TC.USER_USDC_BALANCE);

        // This must NOT revert — if it does, getLoanDetails and executeInitializeLoan disagree
        vm.prank(user);
        address lsa = loan.initializeLoan(minDeposit, 0, collateral, duration, "");

        assertTrue(lsa != address(0), "loan should succeed at exact min deposit from getLoanDetails");

        DataTypes.LoanData memory data = loan.getLoanByLSA(lsa);
        assertEq(data.depositAmount, minDeposit, "stored deposit must match the exact min deposit");
    }

    /**
     * @notice Random byte sequences of varying length (0-512 bytes) in the `data` parameter
     *         must not break initialization. The parameter is pass-through (emitted only).
     * @dev Ensures no accidental abi.decode is added on this field.
     * @param collateralSeed Seed for bounded collateral amount
     * @param data Arbitrary bytes to pass through
     * @custom:audit-property Data parameter robustness
     * @custom:audit-category Core Functionality
     * @custom:audit-severity Medium
     */
    function testFuzz_InitializeLoan_ArbitraryDataRobustness(uint256 collateralSeed, bytes calldata data) public {
        // Limit data length to avoid excessive gas in test runner
        vm.assume(data.length <= 512);

        uint256 collateral = _boundCollateral(collateralSeed);
        uint256 duration = FC.MIN_DURATION;

        (,, uint256 minDeposit) = loan.getLoanDetails(collateral, duration);

        _fundAndApprove(minDeposit + TC.USER_USDC_BALANCE);

        // Must not revert regardless of data contents
        vm.prank(user);
        address lsa = loan.initializeLoan(minDeposit, 0, collateral, duration, data);

        assertTrue(lsa != address(0), "loan should succeed with arbitrary data bytes");

        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Active), "loan must be active");
    }

    /**
     * @notice Two independent financial constraints must hold for any valid loan:
     *         (1) loanAmount < collateralValueUsdc - user always puts down equity
     *         (2) loanAmount <= (100% - TC.MIN_DEPOSIT) of collateralValue
     *         Neither check mirrors the production formula; they are independent invariants.
     * @dev TC.MIN_DEPOSIT (30_00 bps = 30%) is configured via _configureLoanParameters in setUp.
     *      Max loan = (BPS_DENOMINATOR - MIN_DEPOSIT) / BPS_DENOMINATOR of collateral value.
     *      +1 tolerance accounts for fullMulDivUp rounding in the loan amount calculation.
     * @param collateralSeed Seed for bounded collateral amount
     * @param durationSeed Seed for bounded duration
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property Over-lending safety invariants
     * @custom:audit-category Financial Safety
     * @custom:audit-severity Critical
     */
    function testFuzz_InitializeLoan_LoanAmountBounds(uint256 collateralSeed, uint256 durationSeed, uint256 depositSeed)
        public
    {
        uint256 collateral = _boundCollateral(collateralSeed);
        uint256 duration = _boundDuration(durationSeed);

        (uint256 deposit,) = _boundValidDeposit(collateral, duration, depositSeed);

        address lsa = _createLoanFull(deposit, 0, collateral, duration);

        DataTypes.LoanData memory data = loan.getLoanByLSA(lsa);

        // Calculate collateral value in USDC independently
        uint256 btcPrice = mockOracle.getAssetPrice(address(mockBTCVault));
        uint256 usdcPrice = mockOracle.getAssetPrice(address(mockUSDC));
        // collateralValueUsdc = collateral * btcPrice / usdcPrice (both 8 dec prices)
        uint256 collateralValueUsdc = (collateral * btcPrice) / usdcPrice;
        // Convert from 8 dec (BTC) to 6 dec (USDC)
        collateralValueUsdc = (collateralValueUsdc * 1e6) / 1e8;

        // Invariant 1: loanAmount < collateralValueUsdc (user puts down equity)
        assertLt(
            data.loanAmount,
            collateralValueUsdc,
            "loan amount must be strictly less than collateral value (user equity)"
        );

        // Invariant 2: loanAmount <= (100% - minDeposit%) of collateralValue
        uint256 maxLoanBps = FC.BPS_DENOMINATOR - TC.MIN_DEPOSIT;
        uint256 maxLoanAmount = (collateralValueUsdc * maxLoanBps) / FC.BPS_DENOMINATOR;
        assertLe(
            data.loanAmount,
            maxLoanAmount + 2, // +2: production chains two fullMulDivUp ops (collateral→USD, USD→USDC) and the test rounds DOWN in 3 intermediate divisions, so cumulative rounding can exceed +1
            "loan amount must not exceed max loan ratio derived from TC.MIN_DEPOSIT"
        );
    }
}
