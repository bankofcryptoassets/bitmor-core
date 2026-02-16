# Fuzz Testing Infrastructure Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:dispatching-parallel-agents to implement this plan with git worktrees.

**Goal:** Create comprehensive fuzz testing infrastructure for loan-provider covering LoanMath, Loan, BTCVault, and USDCVault contracts.

**Architecture:** Layered fuzz testing with FuzzTestBase providing bound helpers, FuzzConstants defining valid ranges, pure function tests for LoanMath, and stateful tests with handlers for Loan/Vault contracts. Uses git worktrees for parallel agent execution.

**Tech Stack:** Foundry, Solidity 0.8.30, forge-std bound(), vm.assume()

---

## Pre-Implementation Setup

### Step 1: Create git worktrees for parallel agents

```bash
cd /Users/megabyte0x/Developer/bitmor/bitmor-core

# Create worktrees from feat/fuzzTests branch
git worktree add ../bitmor-fuzz-base fuzz/base-infrastructure -b fuzz/base-infrastructure
git worktree add ../bitmor-fuzz-loan fuzz/loan-tests -b fuzz/loan-tests
git worktree add ../bitmor-fuzz-btcvault fuzz/btcvault-tests -b fuzz/btcvault-tests
git worktree add ../bitmor-fuzz-usdcvault fuzz/usdcvault-tests -b fuzz/usdcvault-tests
git worktree add ../bitmor-fuzz-loanmath fuzz/loanmath-tests -b fuzz/loanmath-tests
```

---

## Phase 1: Base Infrastructure (Agent 1 - Sequential)

> **Worktree:** `../bitmor-fuzz-base`
> **Branch:** `fuzz/base-infrastructure`

### Task 1.1: Create FuzzConstants.sol

**Files:**
- Create: `test/fuzz/helpers/FuzzConstants.sol`

**Step 1: Create the constants library**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title FuzzConstants
 * @author Bitmor Protocol
 * @notice Constants and bounds for fuzz testing
 * @dev Import as FC: `import {FuzzConstants as FC} from "./FuzzConstants.sol";`
 */
library FuzzConstants {
    // ============ Price Bounds (8 decimals) ============

    /// @dev Minimum BTC price: $1,000
    uint256 constant MIN_BTC_PRICE = 1000e8;

    /// @dev Maximum BTC price: $1,000,000
    uint256 constant MAX_BTC_PRICE = 1_000_000e8;

    /// @dev USDC price (stable): $1
    uint256 constant USDC_PRICE = 1e8;

    // ============ Interest Rate Bounds (RAY - 27 decimals) ============

    /// @dev Minimum interest rate: 0%
    uint256 constant MIN_INTEREST_RATE = 0;

    /// @dev Maximum interest rate: 12% APR
    uint256 constant MAX_INTEREST_RATE = 0.12e27;

    // ============ Duration Bounds ============

    /// @dev Minimum loan duration: 1 month
    uint256 constant MIN_DURATION = 1;

    /// @dev Maximum loan duration: 60 months
    uint256 constant MAX_DURATION = 60;

    // ============ BTC Amount Bounds (8 decimals) ============

    /// @dev Minimum BTC amount: 0.01 BTC
    uint256 constant MIN_BTC_AMOUNT = 0.01e8;

    /// @dev Maximum BTC amount: 100 BTC
    uint256 constant MAX_BTC_AMOUNT = 100e8;

    // ============ USDC Amount Bounds (6 decimals) ============

    /// @dev Minimum USDC amount: 1 USDC
    uint256 constant MIN_USDC_AMOUNT = 1e6;

    /// @dev Maximum USDC amount: 10M USDC
    uint256 constant MAX_USDC_AMOUNT = 10_000_000e6;

    // ============ Deposit Bounds ============

    /// @dev Minimum deposit: 30% (in basis points)
    uint256 constant MIN_DEPOSIT_BPS = 30_00;

    /// @dev Maximum deposit: 100% (in basis points)
    uint256 constant MAX_DEPOSIT_BPS = 100_00;

    /// @dev Basis points denominator
    uint256 constant BPS_DENOMINATOR = 100_00;

    // ============ Precision Constants ============

    /// @dev RAY precision (27 decimals)
    uint256 constant RAY = 1e27;

    /// @dev Maximum roundtrip slippage: 1% (in WAD for assertApproxEqRel)
    uint256 constant MAX_ROUNDTRIP_SLIPPAGE = 0.01e18;

    /// @dev Maximum yield buffer for invariant checks
    uint256 constant MAX_YIELD_BUFFER = 1000e6;

    // ============ Exponent Bounds ============

    /// @dev Maximum exponent for rayPow (prevents overflow)
    uint256 constant MAX_EXPONENT = 120;

    /// @dev Maximum base for rayPow (prevents overflow)
    uint256 constant MAX_RAY_BASE = type(uint128).max;
}
```

**Step 2: Verify compilation**

Run: `cd loan-provider && forge build --match-path "test/fuzz/helpers/FuzzConstants.sol"`
Expected: Compilation successful

**Step 3: Commit**

```bash
git add test/fuzz/helpers/FuzzConstants.sol
git commit -m "feat(fuzz): add FuzzConstants library with bounds for fuzz testing"
```

---

### Task 1.2: Create FuzzTestBase.sol

**Files:**
- Create: `test/fuzz/base/FuzzTestBase.sol`
- Reference: `test/base/UnitTestBase.sol`

**Step 1: Create the base test contract**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {UnitTestBase} from "../../base/UnitTestBase.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";
import {TestConstants as TC} from "../../helpers/TestConstants.sol";

/**
 * @title FuzzTestBase
 * @author Bitmor Protocol
 * @notice Base contract for fuzz tests with bound helpers
 * @dev Extends UnitTestBase with fuzz-specific utilities for constraining inputs
 *
 * ## Usage
 * ```solidity
 * contract MyFuzzTest is FuzzTestBase {
 *     function testFuzz_Example(uint256 rawAmount) public {
 *         uint256 amount = _boundBtcAmount(rawAmount);
 *         // amount is now within valid BTC range
 *     }
 * }
 * ```
 */
abstract contract FuzzTestBase is UnitTestBase {

    // ============ BTC Amount Bounds ============

    /**
     * @notice Bounds raw input to valid BTC amount range
     * @param raw The raw fuzzed input
     * @return The bounded BTC amount (0.01 - 100 BTC)
     */
    function _boundBtcAmount(uint256 raw) internal pure returns (uint256) {
        return bound(raw, FC.MIN_BTC_AMOUNT, FC.MAX_BTC_AMOUNT);
    }

    /**
     * @notice Bounds raw input to valid collateral range from Loan contract
     * @dev Reads min/max from Loan contract parameters
     * @param raw The raw fuzzed input
     * @return The bounded collateral amount
     */
    function _boundCollateral(uint256 raw) internal view returns (uint256) {
        (uint256 maxBTC, uint256 minBTC,,) = loan.getLoanParameters();
        return bound(raw, minBTC, maxBTC);
    }

    // ============ USDC Amount Bounds ============

    /**
     * @notice Bounds raw input to valid USDC amount range
     * @param raw The raw fuzzed input
     * @return The bounded USDC amount (1 - 10M USDC)
     */
    function _boundUsdcAmount(uint256 raw) internal pure returns (uint256) {
        return bound(raw, FC.MIN_USDC_AMOUNT, FC.MAX_USDC_AMOUNT);
    }

    // ============ Duration Bounds ============

    /**
     * @notice Bounds raw input to valid loan duration range
     * @param raw The raw fuzzed input
     * @return The bounded duration (1 - 60 months)
     */
    function _boundDuration(uint256 raw) internal pure returns (uint256) {
        return bound(raw, FC.MIN_DURATION, FC.MAX_DURATION);
    }

    // ============ Price Bounds ============

    /**
     * @notice Bounds raw input to valid BTC price range
     * @param raw The raw fuzzed input
     * @return The bounded BTC price ($1k - $1M)
     */
    function _boundBtcPrice(uint256 raw) internal pure returns (uint256) {
        return bound(raw, FC.MIN_BTC_PRICE, FC.MAX_BTC_PRICE);
    }

    // ============ Interest Rate Bounds ============

    /**
     * @notice Bounds raw input to valid interest rate range
     * @param raw The raw fuzzed input
     * @return The bounded interest rate (0 - 12% in RAY)
     */
    function _boundInterestRate(uint256 raw) internal pure returns (uint256) {
        return bound(raw, FC.MIN_INTEREST_RATE, FC.MAX_INTEREST_RATE);
    }

    // ============ Deposit Bounds ============

    /**
     * @notice Bounds raw input to valid deposit range based on collateral value
     * @dev Deposit must be between 30% and 100% of collateral value
     * @param collateralValueUsd The collateral value in USD (8 decimals)
     * @param raw The raw fuzzed input
     * @return The bounded deposit amount in USDC (6 decimals)
     */
    function _boundDeposit(uint256 collateralValueUsd, uint256 raw) internal pure returns (uint256) {
        uint256 minDepositUsd = (collateralValueUsd * FC.MIN_DEPOSIT_BPS) / FC.BPS_DENOMINATOR;
        uint256 maxDepositUsd = collateralValueUsd;

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

    // ============ Exponent Bounds (for LoanMath) ============

    /**
     * @notice Bounds raw input to valid exponent range for rayPow
     * @param raw The raw fuzzed input
     * @return The bounded exponent (0 - 120)
     */
    function _boundExponent(uint256 raw) internal pure returns (uint256) {
        return bound(raw, 0, FC.MAX_EXPONENT);
    }

    /**
     * @notice Bounds raw input to valid base for rayPow (prevents overflow)
     * @param raw The raw fuzzed input
     * @return The bounded base (1 - uint128.max)
     */
    function _boundRayBase(uint256 raw) internal pure returns (uint256) {
        return bound(raw, 1, FC.MAX_RAY_BASE);
    }

    // ============ Helper Functions ============

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
     * @notice Gets minimum deposit for a collateral amount at current oracle price
     * @param collateralAmount BTC amount (8 decimals)
     * @return Minimum deposit in USDC (6 decimals)
     */
    function _getMinDepositUsdc(uint256 collateralAmount) internal view returns (uint256) {
        uint256 btcPrice = mockOracle.getAssetPrice(address(mockCbBTC));
        uint256 collateralValueUsd = _getCollateralValueUsd(collateralAmount, btcPrice);
        uint256 minDepositUsd = (collateralValueUsd * FC.MIN_DEPOSIT_BPS) / FC.BPS_DENOMINATOR;
        return (minDepositUsd * 1e6) / 1e8;
    }
}
```

**Step 2: Verify compilation**

Run: `cd loan-provider && forge build --match-path "test/fuzz/**"`
Expected: Compilation successful

**Step 3: Commit**

```bash
git add test/fuzz/base/FuzzTestBase.sol
git commit -m "feat(fuzz): add FuzzTestBase with bound helpers for fuzz testing"
```

---

### Task 1.3: Remove .gitkeep and verify structure

**Step 1: Remove .gitkeep placeholder**

```bash
rm test/fuzz/.gitkeep
```

**Step 2: Create directory structure**

```bash
mkdir -p test/fuzz/pure
mkdir -p test/fuzz/stateful
mkdir -p test/fuzz/handlers
```

**Step 3: Final commit for base infrastructure**

```bash
git add -A
git commit -m "feat(fuzz): complete base infrastructure setup"
git push origin fuzz/base-infrastructure
```

---

## Phase 2: Parallel Agent Tasks

> **Important:** All Phase 2 agents start AFTER Phase 1 completes.
> Each agent must first merge `fuzz/base-infrastructure` into their branch.

---

## Agent 2: Loan Fuzz Tests

> **Worktree:** `../bitmor-fuzz-loan`
> **Branch:** `fuzz/loan-tests`

### Pre-Task: Merge base infrastructure

```bash
cd ../bitmor-fuzz-loan/loan-provider
git fetch origin
git merge origin/fuzz/base-infrastructure
```

### Task 2.1: Create LoanHandler.sol

**Files:**
- Create: `test/fuzz/handlers/LoanHandler.sol`
- Reference: `test/base/LoanUnitTestBase.sol`

**Step 1: Create the handler contract**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {FuzzTestBase} from "../base/FuzzTestBase.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";

/**
 * @title LoanHandler
 * @author Bitmor Protocol
 * @notice Handler contract for stateful fuzz testing of Loan contract
 * @dev Wraps Loan operations with proper setup and state tracking
 */
contract LoanHandler is FuzzTestBase {
    // ============ State Tracking ============

    /// @dev Array of all created LSA addresses
    address[] public activeLSAs;

    /// @dev Mapping of LSA to total amount repaid
    mapping(address => uint256) public totalRepaid;

    /// @dev Mapping of LSA to total collateral deposited
    mapping(address => uint256) public totalCollateral;

    /// @dev Counter for successful loan initializations
    uint256 public initializeCount;

    /// @dev Counter for successful repayments
    uint256 public repayCount;

    /// @dev Counter for successful closures
    uint256 public closeCount;

    // ============ Handler Actions ============

    /**
     * @notice Handler for loan initialization
     * @param collateralSeed Seed for collateral amount
     * @param depositSeed Seed for deposit amount
     * @param durationSeed Seed for duration
     */
    function handler_initializeLoan(
        uint256 collateralSeed,
        uint256 depositSeed,
        uint256 durationSeed
    ) external {
        // Bound inputs
        uint256 collateral = _boundCollateral(collateralSeed);
        uint256 duration = _boundDuration(durationSeed);

        // Get collateral value and bound deposit
        uint256 btcPrice = mockOracle.getAssetPrice(address(mockCbBTC));
        uint256 collateralValueUsd = _getCollateralValueUsd(collateral, btcPrice);
        uint256 deposit = _boundDeposit(collateralValueUsd, depositSeed);

        // Fund user
        _fundUSDCAndApprove(user, address(loan), deposit + FC.MAX_USDC_AMOUNT);

        // Create loan
        vm.prank(user);
        try loan.initializeLoan(deposit, 0, collateral, duration, "") returns (address lsa) {
            activeLSAs.push(lsa);
            totalCollateral[lsa] = collateral;
            initializeCount++;
        } catch {
            // Graceful failure - don't revert handler
        }
    }

    /**
     * @notice Handler for loan repayment
     * @param lsaIndexSeed Seed for selecting LSA
     * @param amountSeed Seed for repayment amount
     */
    function handler_repay(uint256 lsaIndexSeed, uint256 amountSeed) external {
        if (activeLSAs.length == 0) return;

        // Select LSA
        uint256 index = lsaIndexSeed % activeLSAs.length;
        address lsa = activeLSAs[index];

        // Check loan is active
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        if (loanData.status != DataTypes.LoanStatus.Active) return;

        // Get debt and bound repayment
        uint256 debt = _getDebtBalance(lsa);
        if (debt == 0) return;

        uint256 amount = bound(amountSeed, FC.MIN_USDC_AMOUNT, debt);

        // Fund user and repay
        _fundUSDCAndApprove(user, address(loan), amount);

        vm.prank(user);
        try loan.repay(lsa, amount) {
            totalRepaid[lsa] += amount;
            repayCount++;
        } catch {
            // Graceful failure
        }
    }

    /**
     * @notice Handler for loan closure
     * @param lsaIndexSeed Seed for selecting LSA
     * @param withdrawInBtc Whether to withdraw in BTC
     */
    function handler_closeLoan(uint256 lsaIndexSeed, bool withdrawInBtc) external {
        if (activeLSAs.length == 0) return;

        // Select LSA
        uint256 index = lsaIndexSeed % activeLSAs.length;
        address lsa = activeLSAs[index];

        // Check loan is active
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        if (loanData.status != DataTypes.LoanStatus.Active) return;

        // Fund user for closure (may need to repay remaining debt)
        uint256 debt = _getDebtBalance(lsa);
        _fundUSDCAndApprove(user, address(loan), debt + FC.MAX_USDC_AMOUNT);

        vm.prank(user);
        try loan.closeLoan(lsa, withdrawInBtc) {
            closeCount++;
            _removeFromActive(index);
        } catch {
            // Graceful failure
        }
    }

    // ============ View Functions ============

    /**
     * @notice Returns count of active loans
     */
    function getActiveLoanCount() external view returns (uint256) {
        return activeLSAs.length;
    }

    /**
     * @notice Returns LSA at index
     */
    function getLSAAt(uint256 index) external view returns (address) {
        require(index < activeLSAs.length, "Index out of bounds");
        return activeLSAs[index];
    }

    // ============ Internal Functions ============

    function _removeFromActive(uint256 index) internal {
        activeLSAs[index] = activeLSAs[activeLSAs.length - 1];
        activeLSAs.pop();
    }
}
```

**Step 2: Verify compilation**

Run: `forge build --match-path "test/fuzz/handlers/LoanHandler.sol"`
Expected: Compilation successful

**Step 3: Commit**

```bash
git add test/fuzz/handlers/LoanHandler.sol
git commit -m "feat(fuzz): add LoanHandler for stateful loan fuzz testing"
```

---

### Task 2.2: Create Loan.fuzz.t.sol

**Files:**
- Create: `test/fuzz/stateful/Loan.fuzz.t.sol`

**Step 1: Create the fuzz test contract**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {FuzzTestBase} from "../base/FuzzTestBase.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";
import {LoanHandler} from "../handlers/LoanHandler.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";

/**
 * @title LoanFuzzTest
 * @author Bitmor Protocol
 * @notice Fuzz tests for Loan contract
 * @dev Tests loan initialization, repayment, and closure with fuzzed parameters
 */
contract LoanFuzzTest is FuzzTestBase {
    LoanHandler public handler;

    function setUp() public override {
        super.setUp();
        handler = new LoanHandler();
    }

    // ============ Initialization Tests ============

    /// @audit-property LOAN-01: Loan initialization creates valid LSA with correct state
    /// @audit-category Core Functionality
    /// @audit-severity Critical
    function testFuzz_InitializeLoan_CreatesValidLSA(
        uint256 collateralSeed,
        uint256 depositSeed,
        uint256 durationSeed
    ) public {
        // Bound inputs
        uint256 collateral = _boundCollateral(collateralSeed);
        uint256 duration = _boundDuration(durationSeed);
        uint256 btcPrice = mockOracle.getAssetPrice(address(mockCbBTC));
        uint256 collateralValueUsd = _getCollateralValueUsd(collateral, btcPrice);
        uint256 deposit = _boundDeposit(collateralValueUsd, depositSeed);

        // Fund user
        _fundUSDCAndApprove(user, address(loan), deposit + FC.MAX_USDC_AMOUNT);

        // Initialize loan
        vm.prank(user);
        address lsa = loan.initializeLoan(deposit, 0, collateral, duration, "");

        // Assertions
        assertTrue(lsa != address(0), "LSA should be created");

        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(loanData.borrower, user, "borrower should be user");
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Active), "status should be Active");
        assertEq(loanData.duration, duration, "duration should match");
    }

    /// @audit-property LOAN-02: Insufficient deposit reverts with correct error
    /// @audit-category Input Validation
    /// @audit-severity High
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

        // Get insufficient deposit
        uint256 deposit = _boundInsufficientDeposit(collateralValueUsd, depositSeed);

        // Skip if deposit would be 0 (edge case)
        vm.assume(deposit > 0);

        // Fund user
        _fundUSDCAndApprove(user, address(loan), deposit);

        // Expect revert
        vm.expectRevert(Errors.InsufficientDeposit.selector);
        vm.prank(user);
        loan.initializeLoan(deposit, 0, collateral, duration, "");
    }

    /// @audit-property LOAN-03: Zero collateral reverts
    /// @audit-category Input Validation
    /// @audit-severity High
    function testFuzz_InitializeLoan_RevertsOnZeroCollateral(
        uint256 depositSeed,
        uint256 durationSeed
    ) public {
        uint256 duration = _boundDuration(durationSeed);
        uint256 deposit = _boundUsdcAmount(depositSeed);

        _fundUSDCAndApprove(user, address(loan), deposit);

        vm.expectRevert(); // Will revert due to validation
        vm.prank(user);
        loan.initializeLoan(deposit, 0, 0, duration, "");
    }

    // ============ Repayment Tests ============

    /// @audit-property LOAN-04: Repayment reduces debt
    /// @audit-category Core Functionality
    /// @audit-severity Critical
    function testFuzz_Repay_ReducesDebt(
        uint256 collateralSeed,
        uint256 repaymentSeed
    ) public {
        // Create loan
        uint256 collateral = _boundCollateral(collateralSeed);
        address lsa = _createLoanWithCollateral(collateral);

        // Get debt
        uint256 debtBefore = _getDebtBalance(lsa);
        vm.assume(debtBefore > FC.MIN_USDC_AMOUNT);

        // Bound repayment
        uint256 repayment = bound(repaymentSeed, FC.MIN_USDC_AMOUNT, debtBefore);

        // Fund and repay
        _fundUSDCAndApprove(user, address(loan), repayment);

        // Advance time to allow repayment
        vm.warp(block.timestamp + 30 days);

        vm.prank(user);
        loan.repay(lsa, repayment);

        // Assert debt decreased
        uint256 debtAfter = _getDebtBalance(lsa);
        assertLt(debtAfter, debtBefore, "debt should decrease after repayment");
    }

    /// @audit-property LOAN-05: Multiple repayments accumulate correctly
    /// @audit-category Core Functionality
    /// @audit-severity High
    function testFuzz_Repay_MultipleRepayments(
        uint256 collateralSeed,
        uint256 repayment1Seed,
        uint256 repayment2Seed
    ) public {
        // Create loan
        uint256 collateral = _boundCollateral(collateralSeed);
        address lsa = _createLoanWithCollateral(collateral);

        uint256 debtBefore = _getDebtBalance(lsa);
        vm.assume(debtBefore > FC.MIN_USDC_AMOUNT * 3);

        // First repayment
        uint256 repayment1 = bound(repayment1Seed, FC.MIN_USDC_AMOUNT, debtBefore / 3);
        _fundUSDCAndApprove(user, address(loan), repayment1);
        vm.warp(block.timestamp + 30 days);
        vm.prank(user);
        loan.repay(lsa, repayment1);

        uint256 debtAfter1 = _getDebtBalance(lsa);

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
        assertLt(debtAfter2, debtBefore, "debt should be less than original");
    }

    // ============ Closure Tests ============

    /// @audit-property LOAN-06: Loan closure returns collateral
    /// @audit-category Core Functionality
    /// @audit-severity Critical
    function testFuzz_CloseLoan_ReturnsCollateral(
        uint256 collateralSeed
    ) public {
        // Create loan
        uint256 collateral = _boundCollateral(collateralSeed);
        address lsa = _createLoanWithCollateral(collateral);

        // Get user BTC balance before
        uint256 btcBefore = mockCbBTC.balanceOf(user);

        // Fund user for closure
        uint256 debt = _getDebtBalance(lsa);
        _fundUSDCAndApprove(user, address(loan), debt + FC.MAX_USDC_AMOUNT);

        // Close loan
        vm.prank(user);
        loan.closeLoan(lsa, true); // withdraw in BTC

        // Assert collateral returned
        uint256 btcAfter = mockCbBTC.balanceOf(user);
        assertGt(btcAfter, btcBefore, "user should receive BTC collateral");

        // Assert loan completed
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Completed), "loan should be completed");
    }

    // ============ Internal Helpers ============

    function _createLoanWithCollateral(uint256 collateral) internal returns (address) {
        uint256 btcPrice = mockOracle.getAssetPrice(address(mockCbBTC));
        uint256 collateralValueUsd = _getCollateralValueUsd(collateral, btcPrice);
        uint256 deposit = (collateralValueUsd * FC.MIN_DEPOSIT_BPS) / FC.BPS_DENOMINATOR;
        uint256 depositUsdc = (deposit * 1e6) / 1e8;

        // Add buffer for fees
        depositUsdc = depositUsdc + FC.MAX_USDC_AMOUNT;

        _fundUSDCAndApprove(user, address(loan), depositUsdc);

        vm.prank(user);
        return loan.initializeLoan(depositUsdc, 0, collateral, FC.MIN_DURATION, "");
    }
}
```

**Step 2: Run fuzz tests**

Run: `FOUNDRY_PROFILE=fuzz forge test --match-contract LoanFuzzTest -vvv`
Expected: All tests pass with 1000 runs each

**Step 3: Commit**

```bash
git add test/fuzz/stateful/Loan.fuzz.t.sol
git commit -m "feat(fuzz): add Loan contract fuzz tests with 6 properties"
git push origin fuzz/loan-tests
```

---

## Agent 3: BTCVault Fuzz Tests

> **Worktree:** `../bitmor-fuzz-btcvault`
> **Branch:** `fuzz/btcvault-tests`

### Pre-Task: Merge base infrastructure

```bash
cd ../bitmor-fuzz-btcvault/loan-provider
git fetch origin
git merge origin/fuzz/base-infrastructure
```

### Task 3.1: Create VaultHandler.sol

**Files:**
- Create: `test/fuzz/handlers/VaultHandler.sol`

**Step 1: Create the handler contract**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {FuzzTestBase} from "../base/FuzzTestBase.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";

/**
 * @title VaultHandler
 * @author Bitmor Protocol
 * @notice Handler contract for stateful fuzz testing of BTCVault and USDCVault
 * @dev Tracks deposits and withdrawals for invariant verification
 */
contract VaultHandler is FuzzTestBase {
    // ============ State Tracking ============

    /// @dev Total BTC deposited across all operations
    uint256 public totalBtcDeposited;

    /// @dev Total BTC withdrawn across all operations
    uint256 public totalBtcWithdrawn;

    /// @dev Total shares minted
    uint256 public totalSharesMinted;

    /// @dev Total shares redeemed
    uint256 public totalSharesRedeemed;

    /// @dev Counter for deposit operations
    uint256 public depositCount;

    /// @dev Counter for withdraw operations
    uint256 public withdrawCount;

    /// @dev Mapping of user to deposited amount
    mapping(address => uint256) public userDeposits;

    // ============ BTC Vault Handlers ============

    /**
     * @notice Handler for BTC vault deposit
     * @param amountSeed Seed for deposit amount
     */
    function handler_btcDeposit(uint256 amountSeed) external {
        uint256 amount = _boundBtcAmount(amountSeed);

        // Fund user
        _fundCbBTCAndApprove(user, address(mockBTCVault), amount);

        uint256 sharesBefore = mockBTCVault.balanceOf(user);

        vm.prank(user);
        try mockBTCVault.deposit(amount, user) returns (uint256 shares) {
            totalBtcDeposited += amount;
            totalSharesMinted += shares;
            userDeposits[user] += amount;
            depositCount++;
        } catch {
            // Graceful failure
        }
    }

    /**
     * @notice Handler for BTC vault withdrawal
     * @param sharesSeed Seed for shares to redeem
     */
    function handler_btcWithdraw(uint256 sharesSeed) external {
        uint256 userShares = mockBTCVault.balanceOf(user);
        if (userShares == 0) return;

        uint256 shares = bound(sharesSeed, 1, userShares);

        vm.prank(user);
        try mockBTCVault.redeem(shares, user, user) returns (uint256 assets) {
            totalBtcWithdrawn += assets;
            totalSharesRedeemed += shares;
            withdrawCount++;
        } catch {
            // Graceful failure
        }
    }

    /**
     * @notice Handler for BTC vault mint (shares-based deposit)
     * @param sharesSeed Seed for shares to mint
     */
    function handler_btcMint(uint256 sharesSeed) external {
        uint256 shares = bound(sharesSeed, 1, FC.MAX_BTC_AMOUNT);

        // Preview assets needed
        uint256 assets = mockBTCVault.previewMint(shares);
        if (assets == 0 || assets > FC.MAX_BTC_AMOUNT) return;

        // Fund user
        _fundCbBTCAndApprove(user, address(mockBTCVault), assets);

        vm.prank(user);
        try mockBTCVault.mint(shares, user) returns (uint256 assetsUsed) {
            totalBtcDeposited += assetsUsed;
            totalSharesMinted += shares;
            depositCount++;
        } catch {
            // Graceful failure
        }
    }

    /**
     * @notice Handler for BTC vault withdraw (assets-based withdrawal)
     * @param assetsSeed Seed for assets to withdraw
     */
    function handler_btcWithdrawAssets(uint256 assetsSeed) external {
        uint256 maxWithdraw = mockBTCVault.maxWithdraw(user);
        if (maxWithdraw == 0) return;

        uint256 assets = bound(assetsSeed, 1, maxWithdraw);

        vm.prank(user);
        try mockBTCVault.withdraw(assets, user, user) returns (uint256 shares) {
            totalBtcWithdrawn += assets;
            totalSharesRedeemed += shares;
            withdrawCount++;
        } catch {
            // Graceful failure
        }
    }

    // ============ View Functions ============

    /**
     * @notice Returns net BTC flow (deposited - withdrawn)
     */
    function getNetBtcFlow() external view returns (int256) {
        return int256(totalBtcDeposited) - int256(totalBtcWithdrawn);
    }

    /**
     * @notice Returns net shares flow (minted - redeemed)
     */
    function getNetSharesFlow() external view returns (int256) {
        return int256(totalSharesMinted) - int256(totalSharesRedeemed);
    }
}
```

**Step 2: Verify compilation**

Run: `forge build --match-path "test/fuzz/handlers/VaultHandler.sol"`
Expected: Compilation successful

**Step 3: Commit**

```bash
git add test/fuzz/handlers/VaultHandler.sol
git commit -m "feat(fuzz): add VaultHandler for stateful vault fuzz testing"
```

---

### Task 3.2: Create BTCVault.fuzz.t.sol

**Files:**
- Create: `test/fuzz/stateful/BTCVault.fuzz.t.sol`

**Step 1: Create the fuzz test contract**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {FuzzTestBase} from "../base/FuzzTestBase.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";
import {VaultHandler} from "../handlers/VaultHandler.sol";

/**
 * @title BTCVaultFuzzTest
 * @author Bitmor Protocol
 * @notice Fuzz tests for BTCVault contract (ERC-4626)
 * @dev Tests deposit, withdraw, mint, redeem with fuzzed parameters
 */
contract BTCVaultFuzzTest is FuzzTestBase {
    VaultHandler public handler;

    function setUp() public override {
        super.setUp();
        handler = new VaultHandler();
    }

    // ============ Deposit/Withdraw Roundtrip Tests ============

    /// @audit-property BTC-01: Deposit/withdraw roundtrip preserves value within slippage
    /// @audit-category ERC-4626 Compliance
    /// @audit-severity Critical
    function testFuzz_DepositWithdraw_Roundtrip(uint256 depositSeed) public {
        uint256 depositAmount = _boundBtcAmount(depositSeed);

        // Fund user
        _fundCbBTCAndApprove(user, address(mockBTCVault), depositAmount);

        uint256 balanceBefore = mockCbBTC.balanceOf(user);

        // Deposit
        vm.prank(user);
        uint256 shares = mockBTCVault.deposit(depositAmount, user);

        assertGt(shares, 0, "should receive shares");

        // Withdraw all shares
        vm.prank(user);
        uint256 assetsReceived = mockBTCVault.redeem(shares, user, user);

        uint256 balanceAfter = mockCbBTC.balanceOf(user);

        // Assert roundtrip within slippage
        assertApproxEqRel(
            balanceAfter,
            balanceBefore,
            FC.MAX_ROUNDTRIP_SLIPPAGE,
            "roundtrip should preserve value within slippage"
        );
    }

    /// @audit-property BTC-02: Mint/redeem roundtrip preserves value within slippage
    /// @audit-category ERC-4626 Compliance
    /// @audit-severity Critical
    function testFuzz_MintRedeem_Roundtrip(uint256 sharesSeed) public {
        uint256 sharesToMint = bound(sharesSeed, FC.MIN_BTC_AMOUNT, FC.MAX_BTC_AMOUNT);

        // Preview assets needed
        uint256 assetsNeeded = mockBTCVault.previewMint(sharesToMint);
        vm.assume(assetsNeeded > 0 && assetsNeeded <= FC.MAX_BTC_AMOUNT);

        // Fund user
        _fundCbBTCAndApprove(user, address(mockBTCVault), assetsNeeded);

        uint256 balanceBefore = mockCbBTC.balanceOf(user);

        // Mint shares
        vm.prank(user);
        uint256 assetsUsed = mockBTCVault.mint(sharesToMint, user);

        // Redeem all shares
        vm.prank(user);
        uint256 assetsReceived = mockBTCVault.redeem(sharesToMint, user, user);

        uint256 balanceAfter = mockCbBTC.balanceOf(user);

        // Assert roundtrip within slippage
        assertApproxEqRel(
            balanceAfter,
            balanceBefore,
            FC.MAX_ROUNDTRIP_SLIPPAGE,
            "mint/redeem roundtrip should preserve value"
        );
    }

    // ============ Proportionality Tests ============

    /// @audit-property BTC-03: Shares minted proportional to deposit amount
    /// @audit-category ERC-4626 Compliance
    /// @audit-severity High
    function testFuzz_Deposit_SharesProportional(
        uint256 amount1Seed,
        uint256 amount2Seed
    ) public {
        uint256 amount1 = _boundBtcAmount(amount1Seed);
        uint256 amount2 = _boundBtcAmount(amount2Seed);

        // Ensure amounts are different for meaningful test
        vm.assume(amount1 != amount2);
        vm.assume(amount1 > FC.MIN_BTC_AMOUNT && amount2 > FC.MIN_BTC_AMOUNT);

        // First deposit
        _fundCbBTCAndApprove(user, address(mockBTCVault), amount1);
        vm.prank(user);
        uint256 shares1 = mockBTCVault.deposit(amount1, user);

        // Second deposit from different user
        address user2 = makeAddr("user2");
        _fundCbBTCAndApprove(user2, address(mockBTCVault), amount2);
        vm.prank(user2);
        uint256 shares2 = mockBTCVault.deposit(amount2, user2);

        // Assert proportionality (within tolerance for rounding)
        // shares1/amount1 ≈ shares2/amount2
        // => shares1 * amount2 ≈ shares2 * amount1
        uint256 cross1 = shares1 * amount2;
        uint256 cross2 = shares2 * amount1;

        assertApproxEqRel(
            cross1,
            cross2,
            FC.MAX_ROUNDTRIP_SLIPPAGE,
            "shares should be proportional to deposit"
        );
    }

    // ============ ERC-4626 Invariant Tests ============

    /// @audit-property BTC-04: convertToAssets(convertToShares(x)) <= x (no free money)
    /// @audit-category ERC-4626 Compliance
    /// @audit-severity Critical
    function testFuzz_ConvertRoundtrip_NoFreeMoney(uint256 assetsSeed) public {
        uint256 assets = _boundBtcAmount(assetsSeed);

        uint256 shares = mockBTCVault.convertToShares(assets);
        uint256 assetsBack = mockBTCVault.convertToAssets(shares);

        assertLe(assetsBack, assets, "roundtrip conversion should not create free money");
    }

    /// @audit-property BTC-05: previewDeposit <= actual deposit shares
    /// @audit-category ERC-4626 Compliance
    /// @audit-severity High
    function testFuzz_PreviewDeposit_Conservative(uint256 depositSeed) public {
        uint256 depositAmount = _boundBtcAmount(depositSeed);

        // Preview
        uint256 previewShares = mockBTCVault.previewDeposit(depositAmount);

        // Fund and deposit
        _fundCbBTCAndApprove(user, address(mockBTCVault), depositAmount);
        vm.prank(user);
        uint256 actualShares = mockBTCVault.deposit(depositAmount, user);

        assertGe(actualShares, previewShares, "actual shares should be >= preview");
    }

    /// @audit-property BTC-06: previewWithdraw >= actual withdraw shares
    /// @audit-category ERC-4626 Compliance
    /// @audit-severity High
    function testFuzz_PreviewWithdraw_Conservative(uint256 depositSeed) public {
        uint256 depositAmount = _boundBtcAmount(depositSeed);

        // Setup: deposit first
        _fundCbBTCAndApprove(user, address(mockBTCVault), depositAmount);
        vm.prank(user);
        mockBTCVault.deposit(depositAmount, user);

        uint256 maxWithdraw = mockBTCVault.maxWithdraw(user);
        vm.assume(maxWithdraw > 0);

        uint256 withdrawAmount = bound(depositSeed, 1, maxWithdraw);

        // Preview
        uint256 previewShares = mockBTCVault.previewWithdraw(withdrawAmount);

        // Withdraw
        vm.prank(user);
        uint256 actualShares = mockBTCVault.withdraw(withdrawAmount, user, user);

        assertLe(actualShares, previewShares, "actual shares should be <= preview");
    }

    // ============ Max Functions Tests ============

    /// @audit-property BTC-07: maxDeposit returns valid limit
    /// @audit-category ERC-4626 Compliance
    /// @audit-severity Medium
    function testFuzz_MaxDeposit_Respected(uint256 depositSeed) public {
        uint256 maxDeposit = mockBTCVault.maxDeposit(user);
        vm.assume(maxDeposit > 0);

        uint256 depositAmount = bound(depositSeed, 1, maxDeposit);

        _fundCbBTCAndApprove(user, address(mockBTCVault), depositAmount);

        // Should not revert
        vm.prank(user);
        uint256 shares = mockBTCVault.deposit(depositAmount, user);

        assertGt(shares, 0, "deposit within max should succeed");
    }
}
```

**Step 2: Run fuzz tests**

Run: `FOUNDRY_PROFILE=fuzz forge test --match-contract BTCVaultFuzzTest -vvv`
Expected: All tests pass with 1000 runs each

**Step 3: Commit**

```bash
git add test/fuzz/stateful/BTCVault.fuzz.t.sol
git commit -m "feat(fuzz): add BTCVault ERC-4626 fuzz tests with 7 properties"
git push origin fuzz/btcvault-tests
```

---

## Agent 4: USDCVault Fuzz Tests

> **Worktree:** `../bitmor-fuzz-usdcvault`
> **Branch:** `fuzz/usdcvault-tests`

### Pre-Task: Merge base infrastructure and BTCVault (for VaultHandler)

```bash
cd ../bitmor-fuzz-usdcvault/loan-provider
git fetch origin
git merge origin/fuzz/base-infrastructure
git merge origin/fuzz/btcvault-tests  # For VaultHandler
```

### Task 4.1: Create USDCVault.fuzz.t.sol

**Files:**
- Create: `test/fuzz/stateful/USDCVault.fuzz.t.sol`

**Step 1: Create the fuzz test contract**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {FuzzTestBase} from "../base/FuzzTestBase.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";

/**
 * @title USDCVaultFuzzTest
 * @author Bitmor Protocol
 * @notice Fuzz tests for USDCVault contract
 * @dev Tests USDC-specific vault operations with fuzzed parameters
 */
contract USDCVaultFuzzTest is FuzzTestBase {

    function setUp() public override {
        super.setUp();
    }

    // ============ Deposit/Withdraw Roundtrip Tests ============

    /// @audit-property USDC-01: Deposit/withdraw roundtrip preserves value within slippage
    /// @audit-category ERC-4626 Compliance
    /// @audit-severity Critical
    function testFuzz_DepositWithdraw_Roundtrip(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        // Fund user
        _fundUSDCAndApprove(user, address(mockUSDCVault), depositAmount);

        uint256 balanceBefore = mockUSDC.balanceOf(user);

        // Deposit
        vm.prank(user);
        uint256 shares = mockUSDCVault.deposit(depositAmount, user);

        assertGt(shares, 0, "should receive shares");

        // Withdraw all shares
        vm.prank(user);
        uint256 assetsReceived = mockUSDCVault.redeem(shares, user, user);

        uint256 balanceAfter = mockUSDC.balanceOf(user);

        // Assert roundtrip within slippage
        assertApproxEqRel(
            balanceAfter,
            balanceBefore,
            FC.MAX_ROUNDTRIP_SLIPPAGE,
            "USDC roundtrip should preserve value within slippage"
        );
    }

    // ============ Proportionality Tests ============

    /// @audit-property USDC-02: Shares minted proportional to deposit amount
    /// @audit-category ERC-4626 Compliance
    /// @audit-severity High
    function testFuzz_Deposit_SharesProportional(
        uint256 amount1Seed,
        uint256 amount2Seed
    ) public {
        uint256 amount1 = _boundUsdcAmount(amount1Seed);
        uint256 amount2 = _boundUsdcAmount(amount2Seed);

        // Ensure amounts are different
        vm.assume(amount1 != amount2);
        vm.assume(amount1 > FC.MIN_USDC_AMOUNT && amount2 > FC.MIN_USDC_AMOUNT);

        // First deposit
        _fundUSDCAndApprove(user, address(mockUSDCVault), amount1);
        vm.prank(user);
        uint256 shares1 = mockUSDCVault.deposit(amount1, user);

        // Second deposit from different user
        address user2 = makeAddr("user2");
        _fundUSDCAndApprove(user2, address(mockUSDCVault), amount2);
        vm.prank(user2);
        uint256 shares2 = mockUSDCVault.deposit(amount2, user2);

        // Assert proportionality
        uint256 cross1 = shares1 * amount2;
        uint256 cross2 = shares2 * amount1;

        assertApproxEqRel(
            cross1,
            cross2,
            FC.MAX_ROUNDTRIP_SLIPPAGE,
            "USDC shares should be proportional to deposit"
        );
    }

    // ============ ERC-4626 Invariant Tests ============

    /// @audit-property USDC-03: convertToAssets(convertToShares(x)) <= x
    /// @audit-category ERC-4626 Compliance
    /// @audit-severity Critical
    function testFuzz_ConvertRoundtrip_NoFreeMoney(uint256 assetsSeed) public {
        uint256 assets = _boundUsdcAmount(assetsSeed);

        uint256 shares = mockUSDCVault.convertToShares(assets);
        uint256 assetsBack = mockUSDCVault.convertToAssets(shares);

        assertLe(assetsBack, assets, "USDC roundtrip conversion should not create free money");
    }

    /// @audit-property USDC-04: previewDeposit <= actual deposit shares
    /// @audit-category ERC-4626 Compliance
    /// @audit-severity High
    function testFuzz_PreviewDeposit_Conservative(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        // Preview
        uint256 previewShares = mockUSDCVault.previewDeposit(depositAmount);

        // Fund and deposit
        _fundUSDCAndApprove(user, address(mockUSDCVault), depositAmount);
        vm.prank(user);
        uint256 actualShares = mockUSDCVault.deposit(depositAmount, user);

        assertGe(actualShares, previewShares, "USDC actual shares should be >= preview");
    }

    /// @audit-property USDC-05: previewRedeem <= actual redeem assets
    /// @audit-category ERC-4626 Compliance
    /// @audit-severity High
    function testFuzz_PreviewRedeem_Conservative(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        // Setup: deposit first
        _fundUSDCAndApprove(user, address(mockUSDCVault), depositAmount);
        vm.prank(user);
        uint256 shares = mockUSDCVault.deposit(depositAmount, user);

        vm.assume(shares > 0);

        // Preview
        uint256 previewAssets = mockUSDCVault.previewRedeem(shares);

        // Redeem
        vm.prank(user);
        uint256 actualAssets = mockUSDCVault.redeem(shares, user, user);

        assertGe(actualAssets, previewAssets, "USDC actual assets should be >= preview");
    }

    // ============ Liquidity Tests ============

    /// @audit-property USDC-06: Withdrawal respects available liquidity
    /// @audit-category Liquidity Management
    /// @audit-severity High
    function testFuzz_Withdraw_RespectsMaxWithdraw(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        // Setup: deposit
        _fundUSDCAndApprove(user, address(mockUSDCVault), depositAmount);
        vm.prank(user);
        mockUSDCVault.deposit(depositAmount, user);

        // Get max withdraw
        uint256 maxWithdraw = mockUSDCVault.maxWithdraw(user);

        // Attempting to withdraw more than max should revert
        if (maxWithdraw < depositAmount) {
            vm.expectRevert();
            vm.prank(user);
            mockUSDCVault.withdraw(depositAmount, user, user);
        }
    }

    /// @audit-property USDC-07: Multiple users can deposit and withdraw
    /// @audit-category Multi-User
    /// @audit-severity High
    function testFuzz_MultiUser_DepositWithdraw(
        uint256 amount1Seed,
        uint256 amount2Seed,
        uint256 amount3Seed
    ) public {
        uint256 amount1 = _boundUsdcAmount(amount1Seed);
        uint256 amount2 = _boundUsdcAmount(amount2Seed);
        uint256 amount3 = _boundUsdcAmount(amount3Seed);

        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        // All users deposit
        _fundUSDCAndApprove(user, address(mockUSDCVault), amount1);
        vm.prank(user);
        uint256 shares1 = mockUSDCVault.deposit(amount1, user);

        _fundUSDCAndApprove(user2, address(mockUSDCVault), amount2);
        vm.prank(user2);
        uint256 shares2 = mockUSDCVault.deposit(amount2, user2);

        _fundUSDCAndApprove(user3, address(mockUSDCVault), amount3);
        vm.prank(user3);
        uint256 shares3 = mockUSDCVault.deposit(amount3, user3);

        // Verify total supply
        uint256 totalSupply = mockUSDCVault.totalSupply();
        assertEq(totalSupply, shares1 + shares2 + shares3, "total supply should equal sum of shares");

        // All users withdraw
        vm.prank(user);
        mockUSDCVault.redeem(shares1, user, user);

        vm.prank(user2);
        mockUSDCVault.redeem(shares2, user2, user2);

        vm.prank(user3);
        mockUSDCVault.redeem(shares3, user3, user3);

        // Verify vault is empty
        assertEq(mockUSDCVault.totalSupply(), 0, "vault should be empty after all withdrawals");
    }
}
```

**Step 2: Run fuzz tests**

Run: `FOUNDRY_PROFILE=fuzz forge test --match-contract USDCVaultFuzzTest -vvv`
Expected: All tests pass with 1000 runs each

**Step 3: Commit**

```bash
git add test/fuzz/stateful/USDCVault.fuzz.t.sol
git commit -m "feat(fuzz): add USDCVault fuzz tests with 7 properties"
git push origin fuzz/usdcvault-tests
```

---

## Agent 5: LoanMath Fuzz Tests

> **Worktree:** `../bitmor-fuzz-loanmath`
> **Branch:** `fuzz/loanmath-tests`

### Pre-Task: Merge base infrastructure

```bash
cd ../bitmor-fuzz-loanmath/loan-provider
git fetch origin
git merge origin/fuzz/base-infrastructure
```

### Task 5.1: Create LoanMathHarness.sol

**Files:**
- Create: `test/harness/LoanMathHarness.sol`
- Reference: `src/libraries/helpers/LoanMath.sol`

**Step 1: Create the harness contract**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {LoanMath} from "@bitmor/libraries/helpers/LoanMath.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";

/**
 * @title LoanMathHarness
 * @author Bitmor Protocol
 * @notice Harness contract to expose internal LoanMath functions for fuzz testing
 * @dev Wraps library functions as external calls for direct testing
 */
contract LoanMathHarness {

    /**
     * @notice Exposes LoanMath.rayPow for testing
     */
    function exposed_rayPow(uint256 base, uint256 exponent) external pure returns (uint256) {
        return LoanMath.rayPow(base, exponent);
    }

    /**
     * @notice Exposes LoanMath.calculateLoanAmt for testing
     */
    function exposed_calculateLoanAmt(DataTypes.CalculateLoanAmt memory data)
        external
        pure
        returns (uint256 loanAmount, uint256 monthlyPayAmt, uint256 minDepositRequired)
    {
        return LoanMath.calculateLoanAmt(data);
    }

    /**
     * @notice Exposes LoanMath.calculateLoanDetails for testing
     */
    function exposed_calculateLoanDetails(
        uint256 collateralAmount,
        uint256 collateralPriceUSD,
        uint256 collateralAssetDecimals,
        uint256 debtPriceUSD,
        uint256 debtAssetDecimals,
        uint256 interestRate,
        uint256 duration,
        uint256 minDepositBps
    ) external pure returns (uint256 loanAmount, uint256 monthlyPayAmt, uint256 minDepositRequired) {
        return LoanMath.calculateLoanDetails(
            collateralAmount,
            collateralPriceUSD,
            collateralAssetDecimals,
            debtPriceUSD,
            debtAssetDecimals,
            interestRate,
            duration,
            minDepositBps
        );
    }

    /**
     * @notice Exposes LoanMath.calculateStrikePrice for testing
     */
    function exposed_calculateStrikePrice(
        uint256 btcPriceUSD,
        uint256 loanAmount,
        uint256 deposit
    ) external pure returns (uint256) {
        return LoanMath.calculateStrikePrice(btcPriceUSD, loanAmount, deposit);
    }

    /**
     * @notice Exposes LoanMath.min for testing
     */
    function exposed_min(uint256 a, uint256 b) external pure returns (uint256) {
        return LoanMath.min(a, b);
    }
}
```

**Step 2: Verify compilation**

Run: `forge build --match-path "test/harness/LoanMathHarness.sol"`
Expected: Compilation successful

**Step 3: Commit**

```bash
git add test/harness/LoanMathHarness.sol
git commit -m "feat(fuzz): add LoanMathHarness to expose internal functions for testing"
```

---

### Task 5.2: Create LoanMath.fuzz.t.sol

**Files:**
- Create: `test/fuzz/pure/LoanMath.fuzz.t.sol`

**Step 1: Create the fuzz test contract**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";
import {LoanMathHarness} from "../../harness/LoanMathHarness.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";

/**
 * @title LoanMathFuzzTest
 * @author Bitmor Protocol
 * @notice Fuzz tests for LoanMath library pure functions
 * @dev Tests mathematical properties without requiring contract state
 */
contract LoanMathFuzzTest is Test {
    LoanMathHarness public harness;

    uint256 constant RAY = 1e27;
    uint256 constant CBBTC_DECIMALS = 8;
    uint256 constant USDC_DECIMALS = 6;

    function setUp() public {
        harness = new LoanMathHarness();
    }

    // ============ rayPow Tests ============

    /// @audit-property MATH-01: rayPow(base, 0) == RAY (identity property)
    /// @audit-category Mathematical Identity
    /// @audit-severity Critical
    function testFuzz_RayPow_ExponentZero(uint256 baseSeed) public view {
        uint256 base = bound(baseSeed, 1, FC.MAX_RAY_BASE);

        uint256 result = harness.exposed_rayPow(base, 0);

        assertEq(result, RAY, "x^0 should equal 1 (RAY)");
    }

    /// @audit-property MATH-02: rayPow(RAY, n) == RAY (1^n == 1)
    /// @audit-category Mathematical Identity
    /// @audit-severity Critical
    function testFuzz_RayPow_BaseOne(uint256 exponentSeed) public view {
        uint256 exponent = bound(exponentSeed, 0, FC.MAX_EXPONENT);

        uint256 result = harness.exposed_rayPow(RAY, exponent);

        assertEq(result, RAY, "1^n should equal 1 (RAY)");
    }

    /// @audit-property MATH-03: rayPow(base, 1) == base (identity)
    /// @audit-category Mathematical Identity
    /// @audit-severity High
    function testFuzz_RayPow_ExponentOne(uint256 baseSeed) public view {
        uint256 base = bound(baseSeed, 1, FC.MAX_RAY_BASE);

        uint256 result = harness.exposed_rayPow(base, 1);

        assertEq(result, base, "x^1 should equal x");
    }

    /// @audit-property MATH-04: rayPow monotonically increasing for base > RAY
    /// @audit-category Monotonicity
    /// @audit-severity High
    function testFuzz_RayPow_Monotonic(uint256 baseSeed, uint256 exp1Seed, uint256 exp2Seed) public view {
        // Base must be > RAY for increasing behavior
        uint256 base = bound(baseSeed, RAY + 1, FC.MAX_RAY_BASE);
        uint256 exp1 = bound(exp1Seed, 0, FC.MAX_EXPONENT / 2);
        uint256 exp2 = bound(exp2Seed, exp1 + 1, FC.MAX_EXPONENT);

        uint256 result1 = harness.exposed_rayPow(base, exp1);
        uint256 result2 = harness.exposed_rayPow(base, exp2);

        assertLe(result1, result2, "rayPow should be monotonically increasing for base > 1");
    }

    // ============ calculateStrikePrice Tests ============

    /// @audit-property MATH-05: Strike price always > 0 for valid inputs
    /// @audit-category Output Validity
    /// @audit-severity Critical
    function testFuzz_StrikePrice_AlwaysPositive(
        uint256 btcPriceSeed,
        uint256 loanAmountSeed,
        uint256 depositSeed
    ) public view {
        uint256 btcPrice = bound(btcPriceSeed, FC.MIN_BTC_PRICE, FC.MAX_BTC_PRICE);
        uint256 loanAmount = bound(loanAmountSeed, FC.MIN_USDC_AMOUNT, FC.MAX_USDC_AMOUNT);
        uint256 deposit = bound(depositSeed, FC.MIN_USDC_AMOUNT, FC.MAX_USDC_AMOUNT);

        uint256 strikePrice = harness.exposed_calculateStrikePrice(btcPrice, loanAmount, deposit);

        assertGt(strikePrice, 0, "strike price should always be positive");
    }

    /// @audit-property MATH-06: Strike price increases with BTC price
    /// @audit-category Monotonicity
    /// @audit-severity High
    function testFuzz_StrikePrice_IncreasesWithBtcPrice(
        uint256 price1Seed,
        uint256 price2Seed,
        uint256 loanAmountSeed,
        uint256 depositSeed
    ) public view {
        uint256 price1 = bound(price1Seed, FC.MIN_BTC_PRICE, FC.MAX_BTC_PRICE / 2);
        uint256 price2 = bound(price2Seed, price1 + 1, FC.MAX_BTC_PRICE);
        uint256 loanAmount = bound(loanAmountSeed, FC.MIN_USDC_AMOUNT, FC.MAX_USDC_AMOUNT);
        uint256 deposit = bound(depositSeed, FC.MIN_USDC_AMOUNT, FC.MAX_USDC_AMOUNT);

        uint256 strike1 = harness.exposed_calculateStrikePrice(price1, loanAmount, deposit);
        uint256 strike2 = harness.exposed_calculateStrikePrice(price2, loanAmount, deposit);

        assertLt(strike1, strike2, "higher BTC price should result in higher strike price");
    }

    // ============ calculateLoanDetails Tests ============

    /// @audit-property MATH-07: Monthly payment * duration >= loan amount (no negative amortization)
    /// @audit-category Financial Soundness
    /// @audit-severity Critical
    function testFuzz_MonthlyPayment_CoversLoan(
        uint256 collateralSeed,
        uint256 btcPriceSeed,
        uint256 interestRateSeed,
        uint256 durationSeed
    ) public view {
        uint256 collateral = bound(collateralSeed, FC.MIN_BTC_AMOUNT, FC.MAX_BTC_AMOUNT);
        uint256 btcPrice = bound(btcPriceSeed, FC.MIN_BTC_PRICE, FC.MAX_BTC_PRICE);
        uint256 interestRate = bound(interestRateSeed, FC.MIN_INTEREST_RATE, FC.MAX_INTEREST_RATE);
        uint256 duration = bound(durationSeed, FC.MIN_DURATION, FC.MAX_DURATION);

        (uint256 loanAmount, uint256 monthlyPayment,) = harness.exposed_calculateLoanDetails(
            collateral,
            btcPrice,
            CBBTC_DECIMALS,
            FC.USDC_PRICE,
            USDC_DECIMALS,
            interestRate,
            duration,
            FC.MIN_DEPOSIT_BPS
        );

        // Total payments should cover at least the loan amount
        uint256 totalPayments = monthlyPayment * duration;
        assertGe(totalPayments, loanAmount, "total payments should cover loan amount");
    }

    /// @audit-property MATH-08: Higher interest rate results in higher monthly payment
    /// @audit-category Monotonicity
    /// @audit-severity High
    function testFuzz_MonthlyPayment_IncreasesWithRate(
        uint256 collateralSeed,
        uint256 btcPriceSeed,
        uint256 rate1Seed,
        uint256 rate2Seed,
        uint256 durationSeed
    ) public view {
        uint256 collateral = bound(collateralSeed, FC.MIN_BTC_AMOUNT, FC.MAX_BTC_AMOUNT);
        uint256 btcPrice = bound(btcPriceSeed, FC.MIN_BTC_PRICE, FC.MAX_BTC_PRICE);
        uint256 duration = bound(durationSeed, FC.MIN_DURATION, FC.MAX_DURATION);

        // Ensure rate1 < rate2
        uint256 rate1 = bound(rate1Seed, FC.MIN_INTEREST_RATE, FC.MAX_INTEREST_RATE / 2);
        uint256 rate2 = bound(rate2Seed, rate1 + 0.01e27, FC.MAX_INTEREST_RATE);

        (, uint256 payment1,) = harness.exposed_calculateLoanDetails(
            collateral, btcPrice, CBBTC_DECIMALS, FC.USDC_PRICE, USDC_DECIMALS,
            rate1, duration, FC.MIN_DEPOSIT_BPS
        );

        (, uint256 payment2,) = harness.exposed_calculateLoanDetails(
            collateral, btcPrice, CBBTC_DECIMALS, FC.USDC_PRICE, USDC_DECIMALS,
            rate2, duration, FC.MIN_DEPOSIT_BPS
        );

        assertLe(payment1, payment2, "higher interest rate should result in higher payment");
    }

    /// @audit-property MATH-09: Longer duration results in lower monthly payment
    /// @audit-category Monotonicity
    /// @audit-severity High
    function testFuzz_MonthlyPayment_DecreasesWithDuration(
        uint256 collateralSeed,
        uint256 btcPriceSeed,
        uint256 interestRateSeed,
        uint256 duration1Seed,
        uint256 duration2Seed
    ) public view {
        uint256 collateral = bound(collateralSeed, FC.MIN_BTC_AMOUNT, FC.MAX_BTC_AMOUNT);
        uint256 btcPrice = bound(btcPriceSeed, FC.MIN_BTC_PRICE, FC.MAX_BTC_PRICE);
        uint256 interestRate = bound(interestRateSeed, FC.MIN_INTEREST_RATE, FC.MAX_INTEREST_RATE);

        // Ensure duration1 < duration2
        uint256 duration1 = bound(duration1Seed, FC.MIN_DURATION, FC.MAX_DURATION / 2);
        uint256 duration2 = bound(duration2Seed, duration1 + 1, FC.MAX_DURATION);

        (, uint256 payment1,) = harness.exposed_calculateLoanDetails(
            collateral, btcPrice, CBBTC_DECIMALS, FC.USDC_PRICE, USDC_DECIMALS,
            interestRate, duration1, FC.MIN_DEPOSIT_BPS
        );

        (, uint256 payment2,) = harness.exposed_calculateLoanDetails(
            collateral, btcPrice, CBBTC_DECIMALS, FC.USDC_PRICE, USDC_DECIMALS,
            interestRate, duration2, FC.MIN_DEPOSIT_BPS
        );

        assertGe(payment1, payment2, "longer duration should result in lower monthly payment");
    }

    // ============ min Tests ============

    /// @audit-property MATH-10: min returns smaller value
    /// @audit-category Mathematical Correctness
    /// @audit-severity Low
    function testFuzz_Min_ReturnsSmaller(uint256 a, uint256 b) public view {
        uint256 result = harness.exposed_min(a, b);

        assertLe(result, a, "min should be <= a");
        assertLe(result, b, "min should be <= b");
        assertTrue(result == a || result == b, "min should equal one of the inputs");
    }
}
```

**Step 2: Run fuzz tests**

Run: `FOUNDRY_PROFILE=fuzz forge test --match-contract LoanMathFuzzTest -vvv`
Expected: All tests pass with 1000 runs each

**Step 3: Commit**

```bash
git add test/fuzz/pure/LoanMath.fuzz.t.sol
git commit -m "feat(fuzz): add LoanMath pure function fuzz tests with 10 properties"
git push origin fuzz/loanmath-tests
```

---

## Phase 3: Merge All Branches

> **Execute after all Phase 2 agents complete**

### Task 6.1: Merge all fuzz branches into feat/fuzzTests

```bash
cd /Users/megabyte0x/Developer/bitmor/bitmor-core/loan-provider
git checkout feat/fuzzTests

# Merge all branches in order
git merge origin/fuzz/base-infrastructure --no-edit
git merge origin/fuzz/loan-tests --no-edit
git merge origin/fuzz/btcvault-tests --no-edit
git merge origin/fuzz/usdcvault-tests --no-edit
git merge origin/fuzz/loanmath-tests --no-edit
```

### Task 6.2: Run all fuzz tests to verify

```bash
FOUNDRY_PROFILE=fuzz forge test --match-path "test/fuzz/**" -vvv
```

Expected: All 30 fuzz tests pass

### Task 6.3: Clean up worktrees

```bash
cd /Users/megabyte0x/Developer/bitmor/bitmor-core

git worktree remove ../bitmor-fuzz-base
git worktree remove ../bitmor-fuzz-loan
git worktree remove ../bitmor-fuzz-btcvault
git worktree remove ../bitmor-fuzz-usdcvault
git worktree remove ../bitmor-fuzz-loanmath

# Delete remote branches (optional)
git push origin --delete fuzz/base-infrastructure
git push origin --delete fuzz/loan-tests
git push origin --delete fuzz/btcvault-tests
git push origin --delete fuzz/usdcvault-tests
git push origin --delete fuzz/loanmath-tests
```

### Task 6.4: Final commit on feat/fuzzTests

```bash
git add -A
git commit -m "feat(fuzz): complete fuzz testing infrastructure

- Add FuzzTestBase with bound helpers
- Add FuzzConstants with protocol-specific bounds
- Add LoanMath pure function fuzz tests (10 properties)
- Add Loan contract fuzz tests (6 properties)
- Add BTCVault ERC-4626 fuzz tests (7 properties)
- Add USDCVault fuzz tests (7 properties)
- Add LoanHandler and VaultHandler for stateful fuzzing
- Add LoanMathHarness for internal function testing

Total: 30 fuzz test properties covering:
- Mathematical correctness (rayPow, EMI, strike price)
- ERC-4626 compliance (deposit/withdraw roundtrip, proportionality)
- Input validation (insufficient deposit, zero collateral)
- Core functionality (loan lifecycle, repayment, closure)"

git push origin feat/fuzzTests
```

---

## Summary

| Phase | Agent | Branch | Files | Properties |
|-------|-------|--------|-------|------------|
| 1 | Agent 1 | fuzz/base-infrastructure | 2 | - |
| 2 | Agent 2 | fuzz/loan-tests | 2 | 6 |
| 2 | Agent 3 | fuzz/btcvault-tests | 2 | 7 |
| 2 | Agent 4 | fuzz/usdcvault-tests | 1 | 7 |
| 2 | Agent 5 | fuzz/loanmath-tests | 2 | 10 |
| 3 | Main | feat/fuzzTests | - | - |
| **Total** | | | **10 files** | **30 properties** |

## Running Tests

```bash
# Run all fuzz tests
FOUNDRY_PROFILE=fuzz forge test --match-path "test/fuzz/**" -vvv

# Run specific contract
FOUNDRY_PROFILE=fuzz forge test --match-contract LoanFuzzTest -vvv

# Run with more iterations
FOUNDRY_PROFILE=fuzz forge test --fuzz-runs 10000

# Generate report
FOUNDRY_PROFILE=fuzz forge test --match-path "test/fuzz/**" -vvv > fuzz-report.txt
```
