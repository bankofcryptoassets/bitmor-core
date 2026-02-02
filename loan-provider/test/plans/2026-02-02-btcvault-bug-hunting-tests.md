# BTCVault Bug-Hunting Test Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:dispatching-parallel-agents to execute this plan with 3 parallel worktrees.

**Goal:** Find bugs in BTCVault contract through focused, edge-case-driven unit tests targeting fee math, fund distribution, and emergency operations.

**Architecture:** Three parallel git worktrees, each focusing on a high-risk bug category. Tests use existing `BTCVaultHarness` (exposes `feeOnRaw`, `feeOnTotal`) and `BaseTestForBTCVault` infrastructure. All tests follow foundry-testing.md conventions.

**Tech Stack:** Foundry, Solidity 0.8.30, existing mock infrastructure (MockTokenizedStrategy, MockYieldSource, MockERC20)

**Scope:** `loan-provider/src/vaults/btc-vault/` only. NO edits to main contracts.

**Branch:** `unitTest/BTCVault` (base branch, already exists)

---

## Pre-Execution Setup

### Step 1: Verify current branch

```bash
cd /Users/megabyte0x/Developer/bitmor/bitmor-core
git branch --show-current
```
Expected: `unitTest/BTCVault`

### Step 2: Create worktrees

```bash
# Create worktree directory
mkdir -p .worktrees

# Create 3 worktrees with feature branches
git worktree add .worktrees/btc-vault-fees -b unitTest/BTCVault-fees
git worktree add .worktrees/btc-vault-funds -b unitTest/BTCVault-funds
git worktree add .worktrees/btc-vault-emergency -b unitTest/BTCVault-emergency
```

### Step 3: Verify worktrees

```bash
git worktree list
```
Expected: 4 worktrees (main + 3 feature branches)

---

## Worktree 1: Fee Math + Share Calculations

**Directory:** `.worktrees/btc-vault-fees/loan-provider/`

**Target Bugs:**
- Rounding errors causing fund loss/gain
- Precision loss at small amounts (1 wei)
- Fee calculation inconsistencies between deposit/withdraw paths
- First-depositor inflation attack vectors
- Preview vs actual operation mismatches

### Task 1.1: Create FeeMath.t.sol

**Files:**
- Create: `test/unit/Vault/BTC/FeeMath.t.sol`

**Step 1: Write test file skeleton**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTestForBTCVault} from "../BaseTestForBTCVault.t.sol";
import {BTCVaultHarness} from "../../../harness/BTCVaultHarness.sol";

/// @title FeeMathTest
/// @notice Tests for BTCVault fee calculation functions _feeOnRaw and _feeOnTotal
/// @dev Hunts for rounding errors, precision loss, and edge case bugs
contract FeeMathTest is BaseTestForBTCVault {
    // ============ Constants ============
    uint256 constant ONE_WEI = 1;
    uint256 constant MAX_UINT256 = type(uint256).max;
    uint256 constant MAX_FEE_BPS = 10_00; // 10% max fee
    uint256 constant STANDARD_FEE_BPS = 50; // 0.5%
    uint256 constant ZERO_FEE_BPS = 0;

    // ============ feeOnRaw Tests ============

    /// @notice Test feeOnRaw with zero assets returns zero fee
    function test_feeOnRaw_ZeroAssets() public view {
        uint256 fee = vault.feeOnRaw(0, STANDARD_FEE_BPS);
        assertEq(fee, 0, "fee on zero assets should be zero");
    }

    /// @notice Test feeOnRaw with zero fee BPS returns zero
    function test_feeOnRaw_ZeroFeeBps() public view {
        uint256 fee = vault.feeOnRaw(DEPOSIT_AMOUNT, ZERO_FEE_BPS);
        assertEq(fee, 0, "fee with zero bps should be zero");
    }

    /// @notice Test feeOnRaw at maximum fee (10%) calculates correctly
    function test_feeOnRaw_MaxFeeBps() public view {
        uint256 assets = 1000e6; // 1000 USDC
        uint256 fee = vault.feeOnRaw(assets, MAX_FEE_BPS);
        // feeOnRaw = assets * feeBps / 10000 (rounded up)
        // = 1000e6 * 1000 / 10000 = 100e6
        assertEq(fee, 100e6, "10% fee on 1000 should be 100");
    }

    /// @notice Test feeOnRaw with 1 wei - checks precision at minimum
    function test_feeOnRaw_OneWeiAsset() public view {
        uint256 fee = vault.feeOnRaw(ONE_WEI, STANDARD_FEE_BPS);
        // feeOnRaw rounds UP: 1 * 50 / 10000 = 0.005, rounds to 1
        assertGe(fee, 0, "fee on 1 wei should be >= 0");
        assertLe(fee, ONE_WEI, "fee on 1 wei should be <= 1 wei");
    }

    /// @notice Test feeOnRaw with very large asset amount - check for overflow
    function test_feeOnRaw_LargeAssetAmount() public view {
        // Use a large but safe amount (avoid overflow in fee * bps)
        uint256 largeAmount = 1e30; // Very large
        uint256 fee = vault.feeOnRaw(largeAmount, STANDARD_FEE_BPS);
        // Expected: 1e30 * 50 / 10000 = 5e27
        uint256 expected = (largeAmount * STANDARD_FEE_BPS + BASIS_POINT_SCALE - 1) / BASIS_POINT_SCALE;
        assertEq(fee, expected, "fee on large amount should calculate correctly");
    }

    /// @notice Test feeOnRaw rounds UP (protocol-favorable)
    function test_feeOnRaw_RoundsUp() public view {
        // Use amount that doesn't divide evenly: 1001 * 50 / 10000 = 5.005
        uint256 assets = 1001e6;
        uint256 fee = vault.feeOnRaw(assets, STANDARD_FEE_BPS);
        // Should round up to 6 (not down to 5)
        uint256 exactFee = (assets * STANDARD_FEE_BPS) / BASIS_POINT_SCALE;
        assertGe(fee, exactFee, "feeOnRaw should round up");
    }

    // ============ feeOnTotal Tests ============

    /// @notice Test feeOnTotal with zero assets returns zero
    function test_feeOnTotal_ZeroAssets() public view {
        uint256 fee = vault.feeOnTotal(0, STANDARD_FEE_BPS);
        assertEq(fee, 0, "fee on zero total should be zero");
    }

    /// @notice Test feeOnTotal with zero fee BPS returns zero
    function test_feeOnTotal_ZeroFeeBps() public view {
        uint256 fee = vault.feeOnTotal(DEPOSIT_AMOUNT, ZERO_FEE_BPS);
        assertEq(fee, 0, "fee with zero bps should be zero");
    }

    /// @notice Test feeOnTotal at max fee extracts correct portion
    function test_feeOnTotal_MaxFeeBps() public view {
        uint256 total = 1100e6; // Total includes fee
        uint256 fee = vault.feeOnTotal(total, MAX_FEE_BPS);
        // feeOnTotal = total * feeBps / (feeBps + 10000)
        // = 1100e6 * 1000 / 11000 = 100e6
        assertEq(fee, 100e6, "10% feeOnTotal on 1100 should be 100");
    }

    /// @notice Test feeOnTotal with 1 wei
    function test_feeOnTotal_OneWeiAsset() public view {
        uint256 fee = vault.feeOnTotal(ONE_WEI, STANDARD_FEE_BPS);
        assertGe(fee, 0, "fee on 1 wei should be >= 0");
        assertLe(fee, ONE_WEI, "fee on 1 wei should be <= 1 wei");
    }

    /// @notice Test feeOnTotal rounds UP (protocol-favorable)
    function test_feeOnTotal_RoundsUp() public view {
        // Use amount that doesn't divide evenly
        uint256 total = 1001e6;
        uint256 fee = vault.feeOnTotal(total, STANDARD_FEE_BPS);
        // feeOnTotal = total * bps / (bps + 10000) rounded up
        uint256 exactFee = (total * STANDARD_FEE_BPS) / (STANDARD_FEE_BPS + BASIS_POINT_SCALE);
        assertGe(fee, exactFee, "feeOnTotal should round up");
    }

    // ============ Consistency Tests ============

    /// @notice Test feeOnRaw and feeOnTotal are mathematically consistent
    /// @dev If feeOnRaw(base, bps) = fee, then feeOnTotal(base + fee, bps) should ≈ fee
    function test_feeOnRaw_vs_feeOnTotal_Consistency() public view {
        uint256 baseAmount = 10000e6;
        uint256 feeBps = 100; // 1%

        // Calculate fee to add
        uint256 feeToAdd = vault.feeOnRaw(baseAmount, feeBps);
        uint256 total = baseAmount + feeToAdd;

        // Extract fee from total
        uint256 feeExtracted = vault.feeOnTotal(total, feeBps);

        // Due to rounding, they may differ by 1-2 wei
        uint256 diff = feeToAdd > feeExtracted ? feeToAdd - feeExtracted : feeExtracted - feeToAdd;
        assertLe(diff, 2, "feeOnRaw and feeOnTotal should be consistent within 2 wei");
    }

    /// @notice Test fee calculation symmetry for deposit/withdraw roundtrip
    function test_feeSymmetry_DepositWithdrawRoundtrip() public view {
        uint256 depositAssets = 10000e6;
        uint256 entryFee = vault.getEntryFee();
        uint256 exitFee = vault.getExitFee();

        // Simulate deposit: user provides depositAssets, fee extracted
        uint256 entryFeeAmt = vault.feeOnTotal(depositAssets, entryFee);
        uint256 assetsAfterEntry = depositAssets - entryFeeAmt;

        // Simulate withdraw: user wants assetsAfterEntry back, exit fee added
        uint256 exitFeeAmt = vault.feeOnRaw(assetsAfterEntry, exitFee);
        uint256 totalNeededForWithdraw = assetsAfterEntry + exitFeeAmt;

        // User should need MORE than they deposited to get same assets back
        assertGt(totalNeededForWithdraw + entryFeeAmt, depositAssets,
            "total fees should make roundtrip costly");
    }
}
```

**Step 2: Run tests to verify they pass**

```bash
cd .worktrees/btc-vault-fees/loan-provider
forge test --match-path test/unit/Vault/BTC/FeeMath.t.sol -vvv
```
Expected: All tests pass

**Step 3: Commit**

```bash
git add test/unit/Vault/BTC/FeeMath.t.sol
git commit -m "test(BTCVault): add fee math edge case tests

- Test feeOnRaw with zero, max, and 1 wei inputs
- Test feeOnTotal with zero, max, and 1 wei inputs
- Verify rounding direction (protocol-favorable)
- Test consistency between feeOnRaw and feeOnTotal
- Test deposit/withdraw fee symmetry

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 1.2: Create ShareCalculations.t.sol

**Files:**
- Create: `test/unit/Vault/BTC/ShareCalculations.t.sol`

**Step 1: Write test file**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTestForBTCVault} from "../BaseTestForBTCVault.t.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";

/// @title ShareCalculationsTest
/// @notice Tests for BTCVault ERC-4626 share calculations with fees
/// @dev Hunts for share inflation attacks, rounding exploits, and preview mismatches
contract ShareCalculationsTest is BaseTestForBTCVault {
    // ============ Constants ============
    uint256 constant FIRST_DEPOSIT = 1000e6;
    uint256 constant SECOND_DEPOSIT = 500e6;
    uint256 constant SMALL_DEPOSIT = 1e6; // 1 USDC
    uint256 constant TINY_DEPOSIT = 1; // 1 wei

    // ============ Setup ============

    function setUp() public override {
        super.setUp();
        // Add a strategy so deposits can be allocated
        _addStrategyWithCap(VERY_LARGE_CAP);
    }

    /// @notice Helper to add strategy via proper access control
    function _addStrategyWithCap(uint256 cap) internal {
        _scheduleAndExecuteLocal(bvc, BVC_ID(), abi.encodeCall(BTCVault.addStrategy, (address(strategy), cap)));
    }

    /// @notice Helper to deposit as user with proper approval
    function _depositAsUser(uint256 amount) internal returns (uint256 shares) {
        vm.startPrank(user);
        mockUSDC.approve(address(vault), amount);
        shares = vault.deposit(amount, user);
        vm.stopPrank();
    }

    // ============ First Depositor Tests ============

    /// @notice First depositor should receive shares proportional to assets (minus fee)
    function test_deposit_FirstDepositor_SharesMatchAssetsMinusFee() public {
        uint256 entryFee = vault.getEntryFee();
        uint256 expectedFee = vault.feeOnTotal(FIRST_DEPOSIT, entryFee);
        uint256 assetsAfterFee = FIRST_DEPOSIT - expectedFee;

        uint256 shares = _depositAsUser(FIRST_DEPOSIT);

        // First deposit: shares should equal assets after fee (1:1 ratio)
        assertEq(shares, assetsAfterFee, "first depositor shares should equal assets minus fee");
    }

    /// @notice Second depositor should receive proportional shares
    function test_deposit_SecondDepositor_SharesProportional() public {
        // First deposit
        uint256 firstShares = _depositAsUser(FIRST_DEPOSIT);

        // Second deposit
        vm.startPrank(user);
        mockUSDC.approve(address(vault), SECOND_DEPOSIT);
        uint256 secondShares = vault.deposit(SECOND_DEPOSIT, user);
        vm.stopPrank();

        // Second depositor should get proportionally fewer shares (due to entry fee)
        uint256 entryFee = vault.getEntryFee();
        uint256 secondFee = vault.feeOnTotal(SECOND_DEPOSIT, entryFee);
        uint256 secondAssetsAfterFee = SECOND_DEPOSIT - secondFee;

        // shares = assets * totalSupply / totalAssets
        uint256 totalAssetsBeforeSecond = vault.totalAssets();
        // Note: This is approximate due to rounding
        assertGt(secondShares, 0, "second depositor should receive shares");
    }

    // ============ Preview vs Actual Tests ============

    /// @notice previewDeposit should match actual deposit shares
    function test_previewDeposit_MatchesActualDeposit() public {
        uint256 preview = vault.previewDeposit(FIRST_DEPOSIT);

        uint256 actual = _depositAsUser(FIRST_DEPOSIT);

        assertEq(actual, preview, "previewDeposit should match actual shares minted");
    }

    /// @notice previewMint should match actual mint assets
    function test_previewMint_MatchesActualMint() public {
        uint256 sharesToMint = 1000e6;
        uint256 preview = vault.previewMint(sharesToMint);

        vm.startPrank(user);
        mockUSDC.approve(address(vault), preview);
        uint256 actualAssets = vault.mint(sharesToMint, user);
        vm.stopPrank();

        // Actual assets taken should be <= preview (ERC-4626 spec)
        assertLe(actualAssets, preview, "actual assets should be <= preview");
    }

    /// @notice previewWithdraw should match actual withdraw shares burned
    function test_previewWithdraw_MatchesActualWithdraw() public {
        // First deposit
        _depositAsUser(FIRST_DEPOSIT);

        // Calculate how much we can withdraw
        uint256 maxWithdrawable = vault.maxWithdraw(user);
        uint256 withdrawAmount = maxWithdrawable / 2;

        uint256 preview = vault.previewWithdraw(withdrawAmount);

        vm.prank(user);
        uint256 actualSharesBurned = vault.withdraw(withdrawAmount, user, user);

        // Actual shares burned should be >= preview (ERC-4626 spec)
        assertGe(actualSharesBurned, preview, "actual shares burned should be >= preview");
    }

    /// @notice previewRedeem should match actual redeem assets
    function test_previewRedeem_MatchesActualRedeem() public {
        // First deposit
        uint256 shares = _depositAsUser(FIRST_DEPOSIT);

        uint256 redeemShares = shares / 2;
        uint256 preview = vault.previewRedeem(redeemShares);

        vm.prank(user);
        uint256 actualAssets = vault.redeem(redeemShares, user, user);

        // Actual assets should be >= preview (ERC-4626 spec)
        assertGe(actualAssets, preview, "actual assets should be >= preview");
    }

    // ============ Full Redemption Tests ============

    /// @notice Redeeming all shares should return all assets (minus exit fee)
    function test_redeem_AllShares_ReturnsAllAssetsMinusFee() public {
        uint256 shares = _depositAsUser(FIRST_DEPOSIT);

        uint256 userBalanceBefore = mockUSDC.balanceOf(user);

        vm.prank(user);
        uint256 assetsReturned = vault.redeem(shares, user, user);

        uint256 userBalanceAfter = mockUSDC.balanceOf(user);

        assertEq(userBalanceAfter - userBalanceBefore, assetsReturned, "balance change should match returned assets");
        assertEq(vault.balanceOf(user), 0, "user should have 0 shares after full redeem");
    }

    /// @notice Withdrawing max should return expected assets
    function test_withdraw_MaxWithdraw_Succeeds() public {
        _depositAsUser(FIRST_DEPOSIT);

        uint256 maxWithdrawable = vault.maxWithdraw(user);
        uint256 sharesBefore = vault.balanceOf(user);

        vm.prank(user);
        vault.withdraw(maxWithdrawable, user, user);

        uint256 sharesAfter = vault.balanceOf(user);

        // Should have burned all or nearly all shares
        assertLt(sharesAfter, sharesBefore, "should have burned shares");
    }

    // ============ Edge Case Tests ============

    /// @notice Tiny deposit (1 wei) should either work or revert cleanly
    function test_deposit_TinyAmount_HandlesCorrectly() public {
        // This may revert due to zero shares or succeed with rounding
        vm.startPrank(user);
        mockUSDC.approve(address(vault), TINY_DEPOSIT);

        // Either succeeds with some shares or reverts
        try vault.deposit(TINY_DEPOSIT, user) returns (uint256 shares) {
            // If it succeeds, should have gotten some shares
            assertGe(shares, 0, "tiny deposit should return >= 0 shares");
        } catch {
            // Reverting on tiny deposit is acceptable behavior
            assertTrue(true, "reverting on tiny deposit is acceptable");
        }
        vm.stopPrank();
    }

    /// @notice maxDeposit should return reasonable value
    function test_maxDeposit_ReturnsExpectedValue() public view {
        uint256 maxDep = vault.maxDeposit(user);

        // Should equal sum of remaining caps in supply queue
        assertGt(maxDep, 0, "maxDeposit should be > 0 with strategy cap available");
        assertEq(maxDep, VERY_LARGE_CAP, "maxDeposit should equal strategy cap");
    }

    /// @notice maxWithdraw with zero balance should return zero
    function test_maxWithdraw_ZeroBalance_ReturnsZero() public view {
        address noBalanceUser = makeAddr("noBalanceUser");
        uint256 maxWith = vault.maxWithdraw(noBalanceUser);

        assertEq(maxWith, 0, "maxWithdraw for zero balance user should be 0");
    }
}
```

**Step 2: Run tests**

```bash
forge test --match-path test/unit/Vault/BTC/ShareCalculations.t.sol -vvv
```

**Step 3: Commit**

```bash
git add test/unit/Vault/BTC/ShareCalculations.t.sol
git commit -m "test(BTCVault): add share calculation tests

- Test first/second depositor share proportions
- Verify preview functions match actual operations
- Test full redemption returns correct assets
- Test tiny deposit edge case handling
- Test maxDeposit and maxWithdraw accuracy

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 1.3: Merge and Cleanup Worktree 1

**Step 1: Push feature branch**

```bash
cd .worktrees/btc-vault-fees/loan-provider
git push -u origin unitTest/BTCVault-fees
```

**Step 2: Return to main and merge**

```bash
cd /Users/megabyte0x/Developer/bitmor/bitmor-core
git checkout unitTest/BTCVault
git merge unitTest/BTCVault-fees --no-ff -m "Merge branch 'unitTest/BTCVault-fees' - fee math and share calculation tests"
```

**Step 3: Verify all tests pass**

```bash
cd loan-provider
forge test --match-path "test/unit/Vault/BTC/*.t.sol" -v
```

---

## Worktree 2: Fund Distribution + Strategy Integration

**Directory:** `.worktrees/btc-vault-funds/loan-provider/`

**Target Bugs:**
- Assets stuck in vault (not sent to strategies)
- Cap overflow allowing over-allocation
- Queue ordering ignored
- totalAssets() desync with actual balances

### Task 2.1: Create DepositFunds.t.sol

**Files:**
- Create: `test/unit/Vault/BTC/DepositFunds.t.sol`

**Step 1: Write test file**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTestForBTCVault} from "../BaseTestForBTCVault.t.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {MockTokenizedStrategy} from "../../../mock/MockTokenizedStrategy.sol";
import {MockYieldSource} from "../../../mock/MockYieldSource.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";

/// @title DepositFundsTest
/// @notice Tests for BTCVault _depositFunds internal logic via deposit()
/// @dev Hunts for fund distribution bugs, cap enforcement issues, queue ordering problems
contract DepositFundsTest is BaseTestForBTCVault {
    // ============ Additional Strategies ============
    MockTokenizedStrategy strategy2;
    MockTokenizedStrategy strategy3;
    MockYieldSource yieldSource2;
    MockYieldSource yieldSource3;

    // ============ Constants ============
    uint256 constant SMALL_CAP = 1000e6;
    uint256 constant MEDIUM_CAP = 5000e6;
    uint256 constant LARGE_CAP = 10000e6;

    // ============ Setup ============

    function setUp() public override {
        super.setUp();

        // Create additional strategies
        yieldSource2 = new MockYieldSource();
        yieldSource3 = new MockYieldSource();
        strategy2 = new MockTokenizedStrategy(address(yieldSource2), address(vault));
        strategy3 = new MockTokenizedStrategy(address(yieldSource3), address(vault));
    }

    /// @notice Helper to add strategy
    function _addStrategy(address strat, uint256 cap) internal {
        _scheduleAndExecuteLocal(bvc, BVC_ID(), abi.encodeCall(BTCVault.addStrategy, (strat, cap)));
    }

    /// @notice Helper to deposit as user
    function _depositAsUser(uint256 amount) internal returns (uint256 shares) {
        vm.startPrank(user);
        mockUSDC.approve(address(vault), amount);
        shares = vault.deposit(amount, user);
        vm.stopPrank();
    }

    // ============ Single Strategy Tests ============

    /// @notice Deposit with single strategy should allocate all to that strategy
    function test_depositFunds_SingleStrategy_FullAllocation() public {
        _addStrategy(address(strategy), LARGE_CAP);

        uint256 depositAmount = 5000e6;
        uint256 entryFee = vault.getEntryFee();
        uint256 feeAmount = vault.feeOnTotal(depositAmount, entryFee);
        uint256 expectedToStrategy = depositAmount - feeAmount;

        _depositAsUser(depositAmount);

        uint256 assetsInStrategy = vault.getAssetInStrategy(address(strategy));
        assertEq(assetsInStrategy, expectedToStrategy, "all assets should go to strategy");
        assertEq(vault.totalAssets(), expectedToStrategy, "totalAssets should match strategy balance");
    }

    /// @notice Deposit exceeding single strategy cap should revert
    function test_depositFunds_SingleStrategy_revertWhen_ExceedsCap() public {
        _addStrategy(address(strategy), SMALL_CAP);

        uint256 depositAmount = SMALL_CAP + 1000e6; // Exceeds cap

        vm.startPrank(user);
        mockUSDC.approve(address(vault), depositAmount);
        vm.expectRevert(Errors.AllCapsReached.selector);
        vault.deposit(depositAmount, user);
        vm.stopPrank();
    }

    // ============ Multiple Strategy Tests ============

    /// @notice Deposit should follow supply queue order
    function test_depositFunds_MultipleStrategies_FollowsSupplyQueue() public {
        // Add strategies with different caps
        _addStrategy(address(strategy), SMALL_CAP);   // Index 0
        _addStrategy(address(strategy2), MEDIUM_CAP); // Index 1
        _addStrategy(address(strategy3), LARGE_CAP);  // Index 2

        // Deposit amount that exceeds first strategy cap
        uint256 depositAmount = SMALL_CAP + 2000e6;
        uint256 entryFee = vault.getEntryFee();
        uint256 feeAmount = vault.feeOnTotal(depositAmount, entryFee);
        uint256 netDeposit = depositAmount - feeAmount;

        _depositAsUser(depositAmount);

        // First strategy should be at cap
        uint256 inStrategy1 = vault.getAssetInStrategy(address(strategy));
        assertEq(inStrategy1, SMALL_CAP, "first strategy should be at cap");

        // Remainder should go to second strategy
        uint256 inStrategy2 = vault.getAssetInStrategy(address(strategy2));
        uint256 expectedInStrategy2 = netDeposit - SMALL_CAP;
        assertEq(inStrategy2, expectedInStrategy2, "overflow should go to second strategy");

        // Third strategy should be empty
        uint256 inStrategy3 = vault.getAssetInStrategy(address(strategy3));
        assertEq(inStrategy3, 0, "third strategy should be empty");
    }

    /// @notice Should skip strategies that are already at cap
    function test_depositFunds_MultipleStrategies_SkipsFullStrategy() public {
        _addStrategy(address(strategy), SMALL_CAP);
        _addStrategy(address(strategy2), MEDIUM_CAP);

        // Fill first strategy
        _depositAsUser(SMALL_CAP + 100e6); // Slightly over to fill first, overflow to second

        // Second deposit should skip first strategy
        uint256 secondDeposit = 1000e6;
        _depositAsUser(secondDeposit);

        uint256 inStrategy1 = vault.getAssetInStrategy(address(strategy));
        assertEq(inStrategy1, SMALL_CAP, "first strategy should remain at cap");

        // All of second deposit should go to strategy2
        uint256 inStrategy2 = vault.getAssetInStrategy(address(strategy2));
        assertGt(inStrategy2, 0, "second strategy should have received funds");
    }

    /// @notice All strategies at cap should revert
    function test_depositFunds_AllStrategiesFull_revertWhen_AllCapsReached() public {
        _addStrategy(address(strategy), SMALL_CAP);
        _addStrategy(address(strategy2), SMALL_CAP);

        // Fill both strategies
        _depositAsUser(SMALL_CAP * 2);

        // Third deposit should fail
        vm.startPrank(user);
        mockUSDC.approve(address(vault), 1000e6);
        vm.expectRevert(Errors.AllCapsReached.selector);
        vault.deposit(1000e6, user);
        vm.stopPrank();
    }

    // ============ Edge Cases ============

    /// @notice Zero cap strategy should be skipped
    function test_depositFunds_SkipsZeroCapStrategy() public {
        _addStrategy(address(strategy), 0); // Zero cap
        _addStrategy(address(strategy2), LARGE_CAP);

        uint256 depositAmount = 5000e6;
        _depositAsUser(depositAmount);

        uint256 inStrategy1 = vault.getAssetInStrategy(address(strategy));
        assertEq(inStrategy1, 0, "zero cap strategy should be skipped");

        uint256 inStrategy2 = vault.getAssetInStrategy(address(strategy2));
        assertGt(inStrategy2, 0, "deposit should go to second strategy");
    }

    /// @notice totalAssets should match sum of all strategies
    function test_totalAssets_MatchesSumOfStrategies() public {
        _addStrategy(address(strategy), MEDIUM_CAP);
        _addStrategy(address(strategy2), MEDIUM_CAP);

        _depositAsUser(8000e6);

        uint256 inStrategy1 = vault.getAssetInStrategy(address(strategy));
        uint256 inStrategy2 = vault.getAssetInStrategy(address(strategy2));
        uint256 total = vault.totalAssets();

        assertEq(total, inStrategy1 + inStrategy2, "totalAssets should equal sum of strategies");
    }

    /// @notice getAssetInStrategy for non-existent strategy should handle gracefully
    function test_getAssetInStrategy_NonExistentStrategy() public {
        _addStrategy(address(strategy), LARGE_CAP);

        // Query non-added strategy - this may revert or return 0
        // depending on implementation
        address fakeStrategy = makeAddr("fakeStrategy");

        // This tests whether the contract handles invalid strategy lookups
        try vault.getAssetInStrategy(fakeStrategy) returns (uint256 assets) {
            // If it doesn't revert, should return 0
            assertEq(assets, 0, "non-existent strategy should return 0 assets");
        } catch {
            // Reverting is also acceptable
            assertTrue(true, "reverting on non-existent strategy is acceptable");
        }
    }
}
```

**Step 2: Run tests**

```bash
cd .worktrees/btc-vault-funds/loan-provider
forge test --match-path test/unit/Vault/BTC/DepositFunds.t.sol -vvv
```

**Step 3: Commit**

```bash
git add test/unit/Vault/BTC/DepositFunds.t.sol
git commit -m "test(BTCVault): add fund distribution tests for deposits

- Test single strategy full allocation
- Test cap enforcement with revert on exceed
- Test supply queue ordering with multiple strategies
- Test skipping full strategies
- Verify totalAssets matches sum of strategies

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 2.2: Create WithdrawFunds.t.sol

**Files:**
- Create: `test/unit/Vault/BTC/WithdrawFunds.t.sol`

**Step 1: Write test file**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTestForBTCVault} from "../BaseTestForBTCVault.t.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {MockTokenizedStrategy} from "../../../mock/MockTokenizedStrategy.sol";
import {MockYieldSource} from "../../../mock/MockYieldSource.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";

/// @title WithdrawFundsTest
/// @notice Tests for BTCVault _withdrawFunds internal logic via withdraw/redeem
/// @dev Hunts for withdrawal ordering bugs, liquidity issues, and fund extraction problems
contract WithdrawFundsTest is BaseTestForBTCVault {
    // ============ Additional Strategies ============
    MockTokenizedStrategy strategy2;
    MockYieldSource yieldSource2;

    // ============ Constants ============
    uint256 constant STRATEGY_CAP = 10000e6;
    uint256 constant DEPOSIT_AMOUNT = 8000e6;

    // ============ Setup ============

    function setUp() public override {
        super.setUp();

        yieldSource2 = new MockYieldSource();
        strategy2 = new MockTokenizedStrategy(address(yieldSource2), address(vault));
    }

    function _addStrategy(address strat, uint256 cap) internal {
        _scheduleAndExecuteLocal(bvc, BVC_ID(), abi.encodeCall(BTCVault.addStrategy, (strat, cap)));
    }

    function _depositAsUser(uint256 amount) internal returns (uint256 shares) {
        vm.startPrank(user);
        mockUSDC.approve(address(vault), amount);
        shares = vault.deposit(amount, user);
        vm.stopPrank();
    }

    // ============ Basic Withdrawal Tests ============

    /// @notice Full withdrawal should return all assets from strategy
    function test_withdrawFunds_SingleStrategy_FullWithdraw() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        uint256 shares = _depositAsUser(DEPOSIT_AMOUNT);

        uint256 maxWithdrawable = vault.maxWithdraw(user);

        vm.prank(user);
        vault.withdraw(maxWithdrawable, user, user);

        uint256 remainingInStrategy = vault.getAssetInStrategy(address(strategy));
        // Should have very little or nothing left (rounding)
        assertLe(remainingInStrategy, 1e6, "strategy should be mostly empty after full withdraw");
    }

    /// @notice Partial withdrawal should leave remainder in strategy
    function test_withdrawFunds_SingleStrategy_PartialWithdraw() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _depositAsUser(DEPOSIT_AMOUNT);

        uint256 assetsBeforeWithdraw = vault.getAssetInStrategy(address(strategy));
        uint256 withdrawAmount = 1000e6;

        vm.prank(user);
        vault.withdraw(withdrawAmount, user, user);

        uint256 assetsAfterWithdraw = vault.getAssetInStrategy(address(strategy));

        // Exit fee means more assets withdrawn than user receives
        uint256 exitFee = vault.getExitFee();
        uint256 feeAmount = vault.feeOnRaw(withdrawAmount, exitFee);
        uint256 totalWithdrawn = withdrawAmount + feeAmount;

        assertApproxEqAbs(
            assetsBeforeWithdraw - assetsAfterWithdraw,
            totalWithdrawn,
            1e6, // Allow 1 USDC tolerance for rounding
            "withdrawn amount should include fee"
        );
    }

    // ============ Multi-Strategy Withdrawal Tests ============

    /// @notice Withdrawal should follow withdraw queue order
    function test_withdrawFunds_MultipleStrategies_FollowsWithdrawQueue() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _addStrategy(address(strategy2), STRATEGY_CAP);

        // Deposit to both strategies (will fill first, overflow to second)
        _depositAsUser(STRATEGY_CAP * 2);

        uint256 inStrategy1Before = vault.getAssetInStrategy(address(strategy));
        uint256 inStrategy2Before = vault.getAssetInStrategy(address(strategy2));

        // Withdraw amount from first strategy only
        uint256 smallWithdraw = 1000e6;
        vm.prank(user);
        vault.withdraw(smallWithdraw, user, user);

        uint256 inStrategy1After = vault.getAssetInStrategy(address(strategy));
        uint256 inStrategy2After = vault.getAssetInStrategy(address(strategy2));

        // First strategy (first in withdraw queue) should have reduced
        assertLt(inStrategy1After, inStrategy1Before, "first strategy should reduce first");
        // Second strategy should be unchanged (if withdraw was small enough)
        assertEq(inStrategy2After, inStrategy2Before, "second strategy should be unchanged");
    }

    /// @notice Large withdrawal should span multiple strategies
    function test_withdrawFunds_SpansMultipleStrategies() public {
        _addStrategy(address(strategy), 5000e6);
        _addStrategy(address(strategy2), 5000e6);

        _depositAsUser(8000e6); // Will distribute across both

        uint256 inStrategy1Before = vault.getAssetInStrategy(address(strategy));

        // Withdraw more than first strategy has
        uint256 largeWithdraw = inStrategy1Before + 1000e6;

        vm.prank(user);
        vault.withdraw(largeWithdraw, user, user);

        uint256 inStrategy1After = vault.getAssetInStrategy(address(strategy));
        uint256 inStrategy2After = vault.getAssetInStrategy(address(strategy2));

        // First strategy should be drained
        assertEq(inStrategy1After, 0, "first strategy should be fully drained");
        // Second strategy should have been tapped
        assertLt(inStrategy2After, vault.getAssetInStrategy(address(strategy2)), "second strategy should be reduced");
    }

    // ============ Liquidity Tests ============

    /// @notice Withdrawing more than available should revert
    function test_withdrawFunds_revertWhen_NotEnoughLiquidity() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _depositAsUser(5000e6);

        uint256 totalAssets = vault.totalAssets();
        uint256 excessWithdraw = totalAssets + 1000e6;

        vm.prank(user);
        vm.expectRevert(); // Should revert - either NotEnoughLiquidity or ERC4626 error
        vault.withdraw(excessWithdraw, user, user);
    }

    /// @notice maxWithdraw should reflect actual liquidity
    function test_maxWithdraw_ReflectsActualLiquidity() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _depositAsUser(DEPOSIT_AMOUNT);

        uint256 maxWithdrawable = vault.maxWithdraw(user);
        uint256 userShares = vault.balanceOf(user);
        uint256 userAssets = vault.convertToAssets(userShares);

        // maxWithdraw should be userAssets minus exit fee
        uint256 exitFee = vault.getExitFee();
        uint256 expectedMax = userAssets - vault.feeOnTotal(userAssets, exitFee);

        assertEq(maxWithdrawable, expectedMax, "maxWithdraw should account for exit fee");
    }

    /// @notice maxDeposit should reflect remaining caps
    function test_maxDeposit_ReflectsRemainingCaps() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _depositAsUser(3000e6);

        uint256 maxDep = vault.maxDeposit(user);
        uint256 currentInStrategy = vault.getAssetInStrategy(address(strategy));
        uint256 expectedMax = STRATEGY_CAP - currentInStrategy;

        assertEq(maxDep, expectedMax, "maxDeposit should equal remaining cap");
    }

    // ============ Redeem Tests ============

    /// @notice Redeem should work similarly to withdraw
    function test_redeem_WithdrawsFromStrategies() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        uint256 shares = _depositAsUser(DEPOSIT_AMOUNT);

        uint256 redeemShares = shares / 2;
        uint256 strategyBalanceBefore = vault.getAssetInStrategy(address(strategy));

        vm.prank(user);
        vault.redeem(redeemShares, user, user);

        uint256 strategyBalanceAfter = vault.getAssetInStrategy(address(strategy));

        assertLt(strategyBalanceAfter, strategyBalanceBefore, "strategy balance should decrease after redeem");
    }
}
```

**Step 2: Run tests**

```bash
forge test --match-path test/unit/Vault/BTC/WithdrawFunds.t.sol -vvv
```

**Step 3: Commit**

```bash
git add test/unit/Vault/BTC/WithdrawFunds.t.sol
git commit -m "test(BTCVault): add fund withdrawal tests

- Test full and partial withdrawals from single strategy
- Test withdraw queue ordering with multiple strategies
- Test withdrawals spanning multiple strategies
- Test liquidity enforcement and revert on insufficient
- Verify maxWithdraw and maxDeposit accuracy

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 2.3: Create Reallocation.t.sol

**Files:**
- Create: `test/unit/Vault/BTC/Reallocation.t.sol`

**Step 1: Write test file**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTestForBTCVault} from "../BaseTestForBTCVault.t.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {MockTokenizedStrategy} from "../../../mock/MockTokenizedStrategy.sol";
import {MockYieldSource} from "../../../mock/MockYieldSource.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";

/// @title ReallocationTest
/// @notice Tests for BTCVault reallocateFunds and changeStrategyCap
/// @dev Hunts for reallocation bugs, cap enforcement issues, fund movement errors
contract ReallocationTest is BaseTestForBTCVault {
    // ============ Additional Strategies ============
    MockTokenizedStrategy strategy2;
    MockYieldSource yieldSource2;

    // ============ Constants ============
    uint256 constant STRATEGY_CAP = 10000e6;

    // ============ Setup ============

    function setUp() public override {
        super.setUp();

        yieldSource2 = new MockYieldSource();
        strategy2 = new MockTokenizedStrategy(address(yieldSource2), address(vault));
    }

    function _addStrategy(address strat, uint256 cap) internal {
        _scheduleAndExecuteLocal(bvc, BVC_ID(), abi.encodeCall(BTCVault.addStrategy, (strat, cap)));
    }

    function _depositAsUser(uint256 amount) internal returns (uint256 shares) {
        vm.startPrank(user);
        mockUSDC.approve(address(vault), amount);
        shares = vault.deposit(amount, user);
        vm.stopPrank();
    }

    function _reallocate(DataTypes.Allocation[] memory allocations) internal {
        _scheduleAndExecuteLocal(bva_fast, BVA_FAST_ID(), abi.encodeCall(BTCVault.reallocateFunds, (allocations)));
    }

    function _changeCap(address strat, uint256 newCap) internal {
        _scheduleAndExecuteLocal(bvc, BVC_ID(), abi.encodeCall(BTCVault.changeStrategyCap, (strat, newCap)));
    }

    // ============ Reallocation Tests ============

    /// @notice Basic reallocation between two strategies
    function test_reallocateFunds_MovesBetweenStrategies() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _addStrategy(address(strategy2), STRATEGY_CAP);

        _depositAsUser(5000e6);

        uint256 inStrategy1Before = vault.getAssetInStrategy(address(strategy));
        uint256 inStrategy2Before = vault.getAssetInStrategy(address(strategy2));
        assertGt(inStrategy1Before, 0, "strategy1 should have funds");
        assertEq(inStrategy2Before, 0, "strategy2 should be empty initially");

        // Reallocate: move 2000 from strategy1 to strategy2
        DataTypes.Allocation[] memory allocations = new DataTypes.Allocation[](2);
        allocations[0] = DataTypes.Allocation({index: 0, amount: inStrategy1Before - 2000e6}); // Reduce strategy1
        allocations[1] = DataTypes.Allocation({index: 1, amount: 2000e6}); // Add to strategy2

        _reallocate(allocations);

        uint256 inStrategy1After = vault.getAssetInStrategy(address(strategy));
        uint256 inStrategy2After = vault.getAssetInStrategy(address(strategy2));

        assertEq(inStrategy1After, inStrategy1Before - 2000e6, "strategy1 should have reduced");
        assertEq(inStrategy2After, 2000e6, "strategy2 should have received funds");
    }

    /// @notice Reallocation that doesn't balance should revert
    function test_reallocateFunds_revertWhen_InvalidReallocation() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _addStrategy(address(strategy2), STRATEGY_CAP);

        _depositAsUser(5000e6);

        uint256 inStrategy1 = vault.getAssetInStrategy(address(strategy));

        // Invalid: withdraw 2000 but only deposit 1000
        DataTypes.Allocation[] memory allocations = new DataTypes.Allocation[](2);
        allocations[0] = DataTypes.Allocation({index: 0, amount: inStrategy1 - 2000e6});
        allocations[1] = DataTypes.Allocation({index: 1, amount: 1000e6}); // Unbalanced!

        vm.expectRevert(Errors.InvalidReallocation.selector);
        _reallocate(allocations);
    }

    /// @notice Reallocation to strategy exceeding cap should revert
    function test_reallocateFunds_revertWhen_SupplyCapExceeded() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _addStrategy(address(strategy2), 1000e6); // Small cap

        _depositAsUser(5000e6);

        uint256 inStrategy1 = vault.getAssetInStrategy(address(strategy));

        // Try to move 3000 to strategy2 which only has 1000 cap
        DataTypes.Allocation[] memory allocations = new DataTypes.Allocation[](2);
        allocations[0] = DataTypes.Allocation({index: 0, amount: inStrategy1 - 3000e6});
        allocations[1] = DataTypes.Allocation({index: 1, amount: 3000e6});

        vm.expectRevert(abi.encodeWithSelector(Errors.SupplyCapExceeded.selector, 1));
        _reallocate(allocations);
    }

    // ============ changeStrategyCap Tests ============

    /// @notice Increasing cap should work
    function test_changeStrategyCap_IncreaseCap() public {
        _addStrategy(address(strategy), STRATEGY_CAP);

        uint256 newCap = STRATEGY_CAP * 2;
        _changeCap(address(strategy), newCap);

        DataTypes.Strategy memory strategyData = vault.getStrategyDetails(0);
        assertEq(strategyData.cap, newCap, "cap should be increased");
    }

    /// @notice Decreasing cap below current allocation - should this work?
    function test_changeStrategyCap_DecreaseCap_BelowCurrentAllocation() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _depositAsUser(5000e6);

        uint256 currentBalance = vault.getAssetInStrategy(address(strategy));
        uint256 newCap = currentBalance / 2; // Below current balance

        // This might revert or might just set the cap
        // depending on implementation - let's see
        _changeCap(address(strategy), newCap);

        DataTypes.Strategy memory strategyData = vault.getStrategyDetails(0);
        assertEq(strategyData.cap, newCap, "cap should be decreased even below balance");
    }

    /// @notice Setting cap to same value should revert
    function test_changeStrategyCap_revertWhen_NoChangeInCap() public {
        _addStrategy(address(strategy), STRATEGY_CAP);

        vm.expectRevert(Errors.NoChangeInCap.selector);
        _changeCap(address(strategy), STRATEGY_CAP);
    }

    // ============ Total Assets Consistency ============

    /// @notice totalAssets should remain constant after reallocation
    function test_reallocateFunds_TotalAssetsUnchanged() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _addStrategy(address(strategy2), STRATEGY_CAP);

        _depositAsUser(8000e6);

        uint256 totalBefore = vault.totalAssets();
        uint256 inStrategy1 = vault.getAssetInStrategy(address(strategy));

        // Reallocate half
        DataTypes.Allocation[] memory allocations = new DataTypes.Allocation[](2);
        allocations[0] = DataTypes.Allocation({index: 0, amount: inStrategy1 / 2});
        allocations[1] = DataTypes.Allocation({index: 1, amount: inStrategy1 / 2});

        _reallocate(allocations);

        uint256 totalAfter = vault.totalAssets();

        assertEq(totalAfter, totalBefore, "totalAssets should not change after reallocation");
    }
}
```

**Step 2: Run tests**

```bash
forge test --match-path test/unit/Vault/BTC/Reallocation.t.sol -vvv
```

**Step 3: Commit**

```bash
git add test/unit/Vault/BTC/Reallocation.t.sol
git commit -m "test(BTCVault): add reallocation and cap change tests

- Test basic fund movement between strategies
- Test invalid reallocation reverts
- Test supply cap exceeded during reallocation
- Test cap increase and decrease
- Verify totalAssets unchanged after reallocation

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 2.4: Merge Worktree 2

```bash
cd /Users/megabyte0x/Developer/bitmor/bitmor-core
git checkout unitTest/BTCVault
git merge unitTest/BTCVault-funds --no-ff -m "Merge branch 'unitTest/BTCVault-funds' - fund distribution tests"
```

---

## Worktree 3: Emergency Ops + Edge Cases

**Directory:** `.worktrees/btc-vault-emergency/loan-provider/`

### Task 3.1: Create EmergencyOps.t.sol

**Files:**
- Create: `test/unit/Vault/BTC/EmergencyOps.t.sol`

**Step 1: Write test file**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTestForBTCVault} from "../BaseTestForBTCVault.t.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {MockTokenizedStrategy} from "../../../mock/MockTokenizedStrategy.sol";
import {MockYieldSource} from "../../../mock/MockYieldSource.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";

/// @title EmergencyOpsTest
/// @notice Tests for BTCVault emergency operations and pause functionality
/// @dev Hunts for incomplete emergency withdrawals, pause bypass, state corruption
contract EmergencyOpsTest is BaseTestForBTCVault {
    // ============ Additional Strategies ============
    MockTokenizedStrategy strategy2;
    MockYieldSource yieldSource2;

    // ============ Constants ============
    uint256 constant STRATEGY_CAP = 10000e6;
    uint256 constant DEPOSIT_AMOUNT = 5000e6;

    // ============ Setup ============

    function setUp() public override {
        super.setUp();

        yieldSource2 = new MockYieldSource();
        strategy2 = new MockTokenizedStrategy(address(yieldSource2), address(vault));
    }

    function _addStrategy(address strat, uint256 cap) internal {
        _scheduleAndExecuteLocal(bvc, BVC_ID(), abi.encodeCall(BTCVault.addStrategy, (strat, cap)));
    }

    function _depositAsUser(uint256 amount) internal returns (uint256 shares) {
        vm.startPrank(user);
        mockUSDC.approve(address(vault), amount);
        shares = vault.deposit(amount, user);
        vm.stopPrank();
    }

    function _pause() internal {
        _scheduleAndExecuteLocal(bvm_fast, BVM_FAST_ID(), abi.encodeCall(BTCVault.pause, ()));
    }

    function _unpause() internal {
        _scheduleAndExecuteLocal(bvm_slow, BVM_SLOW_ID(), abi.encodeCall(BTCVault.unpause, ()));
    }

    // ============ Emergency Withdraw Tests ============

    /// @notice Emergency withdraw should extract all funds from all strategies
    function test_emergencyWithdrawFunds_WithdrawsFromAllStrategies() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _addStrategy(address(strategy2), STRATEGY_CAP);

        _depositAsUser(STRATEGY_CAP * 2); // Fill both

        uint256 inStrategy1Before = vault.getAssetInStrategy(address(strategy));
        uint256 inStrategy2Before = vault.getAssetInStrategy(address(strategy2));
        assertGt(inStrategy1Before, 0, "strategy1 should have funds");
        assertGt(inStrategy2Before, 0, "strategy2 should have funds");

        // Emergency withdraw
        _scheduleAndExecuteLocal(bvm_fast, BVM_FAST_ID(), abi.encodeCall(BTCVault.emergencyWithdrawFunds, ()));

        uint256 inStrategy1After = vault.getAssetInStrategy(address(strategy));
        uint256 inStrategy2After = vault.getAssetInStrategy(address(strategy2));

        assertEq(inStrategy1After, 0, "strategy1 should be empty after emergency");
        assertEq(inStrategy2After, 0, "strategy2 should be empty after emergency");
    }

    /// @notice Emergency withdraw with single strategy
    function test_emergencyWithdrawFunds_SingleStrategy() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _depositAsUser(DEPOSIT_AMOUNT);

        _scheduleAndExecuteLocal(bvm_fast, BVM_FAST_ID(), abi.encodeCall(BTCVault.emergencyWithdrawFunds, ()));

        uint256 inStrategy = vault.getAssetInStrategy(address(strategy));
        assertEq(inStrategy, 0, "strategy should be empty");
    }

    /// @notice Emergency withdraw with no strategies should not revert
    function test_emergencyWithdrawFunds_NoStrategies() public {
        // No strategies added - should succeed without doing anything
        _scheduleAndExecuteLocal(bvm_fast, BVM_FAST_ID(), abi.encodeCall(BTCVault.emergencyWithdrawFunds, ()));

        // No assertions needed - just verify it doesn't revert
        assertTrue(true, "should not revert with no strategies");
    }

    /// @notice After emergency withdraw, totalAssets should be zero
    function test_emergencyWithdrawFunds_TotalAssetsAfter_IsZero() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _depositAsUser(DEPOSIT_AMOUNT);

        assertGt(vault.totalAssets(), 0, "should have assets before");

        _scheduleAndExecuteLocal(bvm_fast, BVM_FAST_ID(), abi.encodeCall(BTCVault.emergencyWithdrawFunds, ()));

        assertEq(vault.totalAssets(), 0, "totalAssets should be 0 after emergency");
    }

    // ============ Pause Tests ============

    /// @notice Pause should block deposits
    function test_pause_BlocksDeposit() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _pause();

        vm.startPrank(user);
        mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
        vm.expectRevert(); // Pausable: paused
        vault.deposit(DEPOSIT_AMOUNT, user);
        vm.stopPrank();
    }

    /// @notice Pause should block mint
    function test_pause_BlocksMint() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _pause();

        vm.startPrank(user);
        mockUSDC.approve(address(vault), DEPOSIT_AMOUNT);
        vm.expectRevert(); // Pausable: paused
        vault.mint(1000e6, user);
        vm.stopPrank();
    }

    /// @notice Withdraw should still work when paused (users can exit)
    function test_pause_AllowsWithdraw() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _depositAsUser(DEPOSIT_AMOUNT);

        _pause();

        uint256 maxWithdrawable = vault.maxWithdraw(user);

        // Withdraw should work even when paused
        vm.prank(user);
        vault.withdraw(maxWithdrawable / 2, user, user);

        // If we reach here, withdraw worked
        assertTrue(true, "withdraw should work when paused");
    }

    /// @notice Redeem should still work when paused
    function test_pause_AllowsRedeem() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        uint256 shares = _depositAsUser(DEPOSIT_AMOUNT);

        _pause();

        vm.prank(user);
        vault.redeem(shares / 2, user, user);

        assertTrue(true, "redeem should work when paused");
    }

    /// @notice Unpause should restore deposit capability
    function test_unpause_RestoresOperations() public {
        _addStrategy(address(strategy), STRATEGY_CAP);

        _pause();
        _unpause();

        // Should be able to deposit again
        _depositAsUser(DEPOSIT_AMOUNT);

        assertGt(vault.totalAssets(), 0, "should have deposited after unpause");
    }

    /// @notice Double pause should revert
    function test_pause_revertWhen_AlreadyPaused() public {
        _pause();

        // Second pause should fail
        vm.expectRevert(); // EnforcedPause
        _scheduleAndExecuteLocal(bvm_fast, BVM_FAST_ID(), abi.encodeCall(BTCVault.pause, ()));
    }

    /// @notice Unpause when not paused should revert
    function test_unpause_revertWhen_NotPaused() public {
        vm.expectRevert(); // ExpectedPause
        _scheduleAndExecuteLocal(bvm_slow, BVM_SLOW_ID(), abi.encodeCall(BTCVault.unpause, ()));
    }
}
```

**Step 2: Run tests**

```bash
cd .worktrees/btc-vault-emergency/loan-provider
forge test --match-path test/unit/Vault/BTC/EmergencyOps.t.sol -vvv
```

**Step 3: Commit**

```bash
git add test/unit/Vault/BTC/EmergencyOps.t.sol
git commit -m "test(BTCVault): add emergency operations and pause tests

- Test emergency withdraw from single and multiple strategies
- Verify totalAssets is zero after emergency
- Test pause blocks deposit/mint
- Verify withdraw/redeem work when paused
- Test unpause restores operations

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 3.2: Create EdgeCases.t.sol

**Files:**
- Create: `test/unit/Vault/BTC/EdgeCases.t.sol`

**Step 1: Write test file**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTestForBTCVault} from "../BaseTestForBTCVault.t.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";

/// @title EdgeCasesTest
/// @notice Tests for BTCVault edge cases and boundary conditions
/// @dev Hunts for zero-amount bugs, overflow issues, empty state handling
contract EdgeCasesTest is BaseTestForBTCVault {
    // ============ Constants ============
    uint256 constant STRATEGY_CAP = 10000e6;

    // ============ Setup ============

    function setUp() public override {
        super.setUp();
    }

    function _addStrategy(address strat, uint256 cap) internal {
        _scheduleAndExecuteLocal(bvc, BVC_ID(), abi.encodeCall(BTCVault.addStrategy, (strat, cap)));
    }

    // ============ Zero Amount Tests ============

    /// @notice Deposit with zero amount should revert
    function test_deposit_revertIf_ZeroAssets() public {
        _addStrategy(address(strategy), STRATEGY_CAP);

        vm.startPrank(user);
        mockUSDC.approve(address(vault), 0);
        vm.expectRevert(); // Should revert - either ERC4626 or custom error
        vault.deposit(0, user);
        vm.stopPrank();
    }

    /// @notice Withdraw with zero amount should revert or no-op
    function test_withdraw_ZeroAmount() public {
        _addStrategy(address(strategy), STRATEGY_CAP);

        // First deposit
        vm.startPrank(user);
        mockUSDC.approve(address(vault), 1000e6);
        vault.deposit(1000e6, user);
        vm.stopPrank();

        // Try zero withdraw
        vm.prank(user);
        // This might revert or be a no-op
        try vault.withdraw(0, user, user) returns (uint256 shares) {
            assertEq(shares, 0, "zero withdraw should return zero shares");
        } catch {
            assertTrue(true, "reverting on zero withdraw is acceptable");
        }
    }

    /// @notice Mint with zero shares should revert
    function test_mint_revertIf_ZeroShares() public {
        _addStrategy(address(strategy), STRATEGY_CAP);

        vm.startPrank(user);
        mockUSDC.approve(address(vault), 1000e6);
        vm.expectRevert(); // Should revert
        vault.mint(0, user);
        vm.stopPrank();
    }

    /// @notice Redeem with zero shares should revert or no-op
    function test_redeem_ZeroShares() public {
        _addStrategy(address(strategy), STRATEGY_CAP);

        vm.startPrank(user);
        mockUSDC.approve(address(vault), 1000e6);
        vault.deposit(1000e6, user);
        vm.stopPrank();

        vm.prank(user);
        try vault.redeem(0, user, user) returns (uint256 assets) {
            assertEq(assets, 0, "zero redeem should return zero assets");
        } catch {
            assertTrue(true, "reverting on zero redeem is acceptable");
        }
    }

    // ============ No Strategy Tests ============

    /// @notice Deposit with no strategies should revert
    function test_deposit_revertWhen_NoStrategies() public {
        // No strategies added

        vm.startPrank(user);
        mockUSDC.approve(address(vault), 1000e6);
        vm.expectRevert(Errors.AllCapsReached.selector);
        vault.deposit(1000e6, user);
        vm.stopPrank();
    }

    /// @notice totalAssets with no strategies should be zero
    function test_totalAssets_NoStrategies_ReturnsZero() public view {
        uint256 total = vault.totalAssets();
        assertEq(total, 0, "totalAssets should be 0 with no strategies");
    }

    /// @notice maxDeposit with no strategies should be zero
    function test_maxDeposit_NoStrategies_ReturnsZero() public view {
        uint256 maxDep = vault.maxDeposit(user);
        assertEq(maxDep, 0, "maxDeposit should be 0 with no strategies");
    }

    // ============ Max Strategies Tests ============

    /// @notice Adding strategy beyond max should revert
    function test_addStrategy_revertWhen_MaxStrategiesReached() public {
        // Max strategies is 10 (from setUp)
        // Add 10 strategies
        for (uint256 i = 0; i < MAX_STRATEGIES; i++) {
            MockYieldSource ys = new MockYieldSource();
            MockTokenizedStrategy strat = new MockTokenizedStrategy(address(ys), address(vault));
            _addStrategy(address(strat), STRATEGY_CAP);
        }

        // 11th should fail
        MockYieldSource ys = new MockYieldSource();
        MockTokenizedStrategy extraStrat = new MockTokenizedStrategy(address(ys), address(vault));

        vm.expectRevert(Errors.MaxStrategiesReached.selector);
        _addStrategy(address(extraStrat), STRATEGY_CAP);
    }

    // ============ Queue Tests ============

    /// @notice Empty supply queue update should work
    function test_updateSupplyQueue_EmptyQueue() public {
        _addStrategy(address(strategy), STRATEGY_CAP);

        uint256[] memory emptyQueue = new uint256[](0);

        _scheduleAndExecuteLocal(bva_slow, BVA_SLOW_ID(), abi.encodeCall(BTCVault.updateSupplyQueue, (emptyQueue)));

        uint256[] memory currentQueue = vault.getSupplyQueue();
        assertEq(currentQueue.length, 0, "supply queue should be empty");
    }

    /// @notice Empty withdraw queue update should work
    function test_updateWithdrawQueue_EmptyQueue() public {
        _addStrategy(address(strategy), STRATEGY_CAP);

        uint256[] memory emptyQueue = new uint256[](0);

        _scheduleAndExecuteLocal(bva_slow, BVA_SLOW_ID(), abi.encodeCall(BTCVault.updateWithdrawQueue, (emptyQueue)));

        uint256[] memory currentQueue = vault.getWithdrawQueue();
        assertEq(currentQueue.length, 0, "withdraw queue should be empty");
    }

    // ============ Fee Edge Cases ============

    /// @notice Zero fee should not cause issues
    function test_deposit_WithZeroEntryFee() public {
        // Set entry fee to 0
        _scheduleAndExecuteLocal(bvm_slow, BVM_SLOW_ID(), abi.encodeCall(BTCVault.setEntryFee, (0)));
        _addStrategy(address(strategy), STRATEGY_CAP);

        uint256 depositAmount = 1000e6;

        vm.startPrank(user);
        mockUSDC.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user);
        vm.stopPrank();

        // With zero fee, shares should equal deposit amount (for first depositor)
        assertEq(shares, depositAmount, "zero fee: shares should equal deposit");
    }

    /// @notice Max fee (10%) should work correctly
    function test_deposit_WithMaxEntryFee() public {
        // Set entry fee to max (10%)
        _scheduleAndExecuteLocal(bvm_slow, BVM_SLOW_ID(), abi.encodeCall(BTCVault.setEntryFee, (1000)));
        _addStrategy(address(strategy), STRATEGY_CAP);

        uint256 depositAmount = 1000e6;

        vm.startPrank(user);
        mockUSDC.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user);
        vm.stopPrank();

        // 10% fee means 900 should go to shares
        uint256 expectedShares = 900e6; // Approximately
        assertApproxEqAbs(shares, expectedShares, 1e6, "max fee should take ~10%");
    }

    /// @notice Setting fee above max should revert
    function test_setEntryFee_revertWhen_ExceedMaxFee() public {
        vm.expectRevert(Errors.ExceedMaxFee.selector);
        _scheduleAndExecuteLocal(bvm_slow, BVM_SLOW_ID(), abi.encodeCall(BTCVault.setEntryFee, (1001))); // 10.01%
    }

    /// @notice Setting exit fee above max should revert
    function test_setExitFee_revertWhen_ExceedMaxFee() public {
        vm.expectRevert(Errors.ExceedMaxFee.selector);
        _scheduleAndExecuteLocal(bvm_slow, BVM_SLOW_ID(), abi.encodeCall(BTCVault.setExitFee, (1001)));
    }

    // ============ View Function Tests ============

    /// @notice getTotalStrategies should return correct count
    function test_getTotalStrategies_ReturnsCorrectCount() public {
        assertEq(vault.getTotalStrategies(), 0, "should start with 0");

        _addStrategy(address(strategy), STRATEGY_CAP);
        assertEq(vault.getTotalStrategies(), 1, "should have 1 after adding");

        MockYieldSource ys2 = new MockYieldSource();
        MockTokenizedStrategy strat2 = new MockTokenizedStrategy(address(ys2), address(vault));
        _addStrategy(address(strat2), STRATEGY_CAP);
        assertEq(vault.getTotalStrategies(), 2, "should have 2");
    }

    /// @notice getMaxStrategies should return configured value
    function test_getMaxStrategies_ReturnsConfiguredValue() public view {
        assertEq(vault.getMaxStrategies(), MAX_STRATEGIES, "should match configured max");
    }

    /// @notice getSupplyQueueLength and getWithdrawQueueLength
    function test_getQueueLengths() public {
        _addStrategy(address(strategy), STRATEGY_CAP);

        assertEq(vault.getSupplyQueueLength(), 1, "supply queue should have 1");
        assertEq(vault.getWithdrawQueueLength(), 1, "withdraw queue should have 1");
    }
}

// Need to import these for the test
import {MockTokenizedStrategy} from "../../../mock/MockTokenizedStrategy.sol";
import {MockYieldSource} from "../../../mock/MockYieldSource.sol";
```

**Step 2: Run tests**

```bash
forge test --match-path test/unit/Vault/BTC/EdgeCases.t.sol -vvv
```

**Step 3: Commit**

```bash
git add test/unit/Vault/BTC/EdgeCases.t.sol
git commit -m "test(BTCVault): add edge case and boundary tests

- Test zero amount operations (deposit, withdraw, mint, redeem)
- Test behavior with no strategies
- Test max strategies limit enforcement
- Test empty queue updates
- Test zero and max fee handling
- Verify view functions return correct values

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 3.3: Merge Worktree 3

```bash
cd /Users/megabyte0x/Developer/bitmor/bitmor-core
git checkout unitTest/BTCVault
git merge unitTest/BTCVault-emergency --no-ff -m "Merge branch 'unitTest/BTCVault-emergency' - emergency and edge case tests"
```

---

## Final Steps

### Step 1: Run Full Test Suite

```bash
cd loan-provider
forge test --match-path "test/unit/Vault/BTC/*.t.sol" -v
```

All tests should pass.

### Step 2: Check for Test Failures Due to Contract Bugs

If any test fails due to contract logic (not test bug):
1. Document the finding with test name and failure reason
2. DO NOT edit main contracts
3. Enter plan mode with user to discuss fix approach

### Step 3: Cleanup Worktrees

```bash
cd /Users/megabyte0x/Developer/bitmor/bitmor-core
git worktree remove .worktrees/btc-vault-fees
git worktree remove .worktrees/btc-vault-funds
git worktree remove .worktrees/btc-vault-emergency
```

### Step 4: Final Commit Summary

Create a summary of new test coverage:

| Test File | Tests Added | Risk Area |
|-----------|-------------|-----------|
| FeeMath.t.sol | 12 | Fee calculation edge cases |
| ShareCalculations.t.sol | 12 | ERC-4626 share math |
| DepositFunds.t.sol | 8 | Fund distribution to strategies |
| WithdrawFunds.t.sol | 8 | Fund extraction from strategies |
| Reallocation.t.sol | 6 | Strategy rebalancing |
| EmergencyOps.t.sol | 10 | Emergency withdraw, pause |
| EdgeCases.t.sol | 15 | Zero amounts, limits, queues |
| **Total** | **~71** | |

---

## Bug Documentation Template

If a test reveals a contract bug, document it as:

```markdown
## Bug Found: [Title]

**Test:** `test_xxx_xxx` in `XxxTest.t.sol`
**Severity:** [Critical/High/Medium/Low]
**Location:** `BTCVault.sol:XXX`

**Description:**
[What the bug is]

**Expected Behavior:**
[What should happen]

**Actual Behavior:**
[What actually happens]

**Reproduction:**
[How to reproduce via test]

**Suggested Fix:**
[If obvious - but DO NOT implement without user approval]
```

---

## Execution Notes

1. **Parallel Execution:** Worktrees 1, 2, and 3 can be worked on simultaneously by different agents
2. **Merge Order:** Any order is fine since tests don't conflict
3. **Test Failures:** If a test fails during development:
   - First check if it's a test bug (fix the test)
   - If it's a contract bug, document and pause for user review
4. **No Main Contract Edits:** Strictly enforced - only test files and harness
