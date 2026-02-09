// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {USDCVaultFuzzTestBase} from "../base/USDCVaultFuzzTestBase.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";
import {USDCVault} from "@bitmor/vaults/usdc-vault/USDCVault.sol";

/// @title USDCVaultSequencesFuzzTest
/// @author Bitmor Protocol
/// @notice Multi-step sequence fuzz tests for USDC Vault and Strategy
/// @dev Each test exercises a sequence of operations that single-action tests miss.
///      These catch cumulative rounding errors, ordering-dependent bugs, and state
///      corruption from interleaved deposit/withdraw/rebalance/pause operations.
///
/// ## Test Coverage
/// - USDC-50: Deposit→partial withdraw→deposit→full redeem preserves solvency
/// - USDC-51: Allocation change mid-lifecycle does not corrupt accounting
/// - USDC-52: Multiple deposit/withdraw cycles accumulate <= 1% total rounding loss
/// - USDC-53: Pause during lifecycle does not corrupt share pricing
/// - USDC-54: Multi-user interleaved deposits and withdrawals maintain total consistency
///
/// @custom:audit-category Multi-Step Sequences, State Consistency
contract USDCVaultSequencesFuzzTest is USDCVaultFuzzTestBase {
    function setUp() public override {
        super.setUp();
    }

    /// @notice deposit → partial withdraw → deposit again → full redeem → verify dust is minimal
    /// @dev Tests that repeated deposit/withdraw cycles don't leave significant dust in the vault.
    ///      The final redeem should return close to net deposits.
    /// @param deposit1Seed First deposit amount seed
    /// @param withdrawSeed Partial withdraw amount seed
    /// @param deposit2Seed Second deposit amount seed
    /// @custom:audit-property USDC-50: Multi-step deposit/withdraw cycle preserves solvency
    /// @custom:audit-category Multi-Step Sequences
    /// @custom:audit-severity Critical
    function testFuzz_Sequence_DepositWithdrawDepositRedeem(
        uint256 deposit1Seed,
        uint256 withdrawSeed,
        uint256 deposit2Seed
    ) public {
        uint256 deposit1 = bound(deposit1Seed, 10e6, FC.MAX_USDC_AMOUNT / 2);
        uint256 deposit2 = bound(deposit2Seed, FC.MIN_USDC_AMOUNT, FC.MAX_USDC_AMOUNT / 2);

        // Step 1: First deposit
        uint256 shares1 = _depositToVault(depositor, deposit1);
        assertGt(shares1, 0, "first deposit should mint shares");

        // Step 2: Partial withdraw
        uint256 maxWithdraw = vault.maxWithdraw(depositor);
        uint256 withdrawAmount = bound(withdrawSeed, 1, maxWithdraw / 2);

        vm.prank(depositor);
        vault.withdraw(withdrawAmount, depositor, depositor);

        // Step 3: Second deposit
        uint256 shares2 = _depositToVault(depositor, deposit2);
        assertGt(shares2, 0, "second deposit should mint shares");

        // Step 4: Full redeem of all shares
        uint256 totalShares = vault.balanceOf(depositor);
        vm.prank(depositor);
        uint256 totalReturned = vault.redeem(totalShares, depositor, depositor);

        // Net expected: deposit1 - withdrawAmount + deposit2
        uint256 netDeposited = deposit1 - withdrawAmount + deposit2;

        // Returned should be close to net deposits (within 1% for rounding)
        assertApproxEqRel(
            totalReturned,
            netDeposited,
            FC.MAX_ROUNDTRIP_SLIPPAGE,
            "multi-step sequence should preserve value within slippage"
        );

        // Vault should be empty after full redeem
        assertEq(vault.totalSupply(), 0, "vault should be empty after full redeem");
    }

    /// @notice Allocation change between deposit and withdraw should not break accounting
    /// @dev deposit → change allocation → rebalance → withdraw → verify totalAssets consistency
    /// @param depositSeed Deposit amount seed
    /// @param newAllocSeed New allocation seed
    /// @custom:audit-property USDC-51: Allocation change mid-lifecycle preserves accounting
    /// @custom:audit-category Multi-Step Sequences
    /// @custom:audit-severity High
    function testFuzz_Sequence_AllocationChangePreservesAccounting(uint256 depositSeed, uint256 newAllocSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);
        uint256 newAllocationBps = bound(newAllocSeed, 1, FC.MAX_ALLOCATION_BPS);

        vm.assume(
            newAllocationBps > FC.DEFAULT_AAVE_ALLOCATION_BPS
                ? newAllocationBps - FC.DEFAULT_AAVE_ALLOCATION_BPS > FC.DEFAULT_MIN_DELTA_BPS
                : FC.DEFAULT_AAVE_ALLOCATION_BPS - newAllocationBps > FC.DEFAULT_MIN_DELTA_BPS
        );

        // Step 1: Deposit with default 80% allocation
        _depositToVault(depositor, depositAmount);

        uint256 totalAssetsBefore = vault.totalAssets();

        // Step 2: Change allocation
        _setAllocation(newAllocationBps);

        // Step 3: Rebalance
        _rebalance();

        // Step 4: Verify totalAssets unchanged (rebalance moves funds, doesn't create/destroy)
        uint256 totalAssetsAfter = vault.totalAssets();
        assertEq(
            totalAssetsAfter, totalAssetsBefore, "totalAssets should be unchanged after allocation change + rebalance"
        );

        // Step 5: Withdraw all and verify solvency
        uint256 maxWithdraw = vault.maxWithdraw(depositor);
        vm.assume(maxWithdraw > 0);

        vm.prank(depositor);
        vault.withdraw(maxWithdraw, depositor, depositor);

        assertApproxEqRel(
            maxWithdraw, depositAmount, FC.MAX_ROUNDTRIP_SLIPPAGE, "should recover full deposit after allocation change"
        );
    }

    /// @notice Multiple deposit/withdraw cycles should not accumulate excessive rounding loss
    /// @dev Repeats deposit→withdraw N times and checks total loss is bounded
    /// @param amountSeed Base amount seed
    /// @param cyclesSeed Number of cycles seed (2-5)
    /// @custom:audit-property USDC-52: Cumulative rounding loss bounded across cycles
    /// @custom:audit-category Multi-Step Sequences
    /// @custom:audit-severity High
    function testFuzz_Sequence_CumulativeRoundingBounded(uint256 amountSeed, uint256 cyclesSeed) public {
        uint256 amount = bound(amountSeed, 100e6, 1_000_000e6);
        uint256 cycles = bound(cyclesSeed, 2, 5);

        uint256 totalLoss;

        for (uint256 i = 0; i < cycles; i++) {
            // Deposit
            uint256 shares = _depositToVault(depositor, amount);

            // Redeem all
            vm.prank(depositor);
            uint256 returned = vault.redeem(shares, depositor, depositor);

            // Track loss per cycle
            if (returned < amount) {
                totalLoss += amount - returned;
            }
        }

        // Total loss across all cycles should be bounded
        uint256 maxTotalLoss = (amount * cycles * 10) / 10_000; // 0.1% per cycle
        assertLe(totalLoss, maxTotalLoss, "cumulative rounding loss should be bounded across multiple cycles");
    }

    /// @notice Pause between deposit and withdraw should not corrupt share pricing
    /// @dev deposit → pause → unpause → withdraw → verify amounts
    /// @param depositSeed Deposit amount seed
    /// @custom:audit-property USDC-53: Pause/unpause cycle preserves share pricing
    /// @custom:audit-category Multi-Step Sequences
    /// @custom:audit-severity High
    function testFuzz_Sequence_PauseUnpausePreservesShares(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        // Step 1: Deposit
        uint256 shares = _depositToVault(depositor, depositAmount);
        uint256 sharePriceBefore = vault.convertToAssets(1e6); // Price per 1 share

        // Step 2: Pause
        _pauseVault();

        // Verify maxWithdraw is 0 when paused
        assertEq(vault.maxWithdraw(depositor), 0, "maxWithdraw should be 0 when paused");
        assertEq(vault.maxRedeem(depositor), 0, "maxRedeem should be 0 when paused");

        // Step 3: Unpause via UVM_SLOW (delayed)
        _scheduleAndExecuteLocal(uvm_slow, UVM_SLOW_ID(), abi.encodeCall(USDCVault.unpause, ()));

        // Step 4: Verify share price is unchanged
        uint256 sharePriceAfter = vault.convertToAssets(1e6);
        assertEq(sharePriceAfter, sharePriceBefore, "share price should be unchanged after pause/unpause");

        // Step 5: Redeem
        vm.prank(depositor);
        uint256 returned = vault.redeem(shares, depositor, depositor);

        assertApproxEqRel(
            returned, depositAmount, FC.MAX_ROUNDTRIP_SLIPPAGE, "should recover deposit after pause/unpause cycle"
        );
    }

    /// @notice Multi-user interleaved deposits and withdrawals maintain total consistency
    /// @dev User1 deposits, User2 deposits, User1 withdraws partially, User2 redeems all,
    ///      User1 redeems all. Sum of returned should approximate sum of deposited.
    /// @param amount1Seed User1 deposit seed
    /// @param amount2Seed User2 deposit seed
    /// @param withdrawFractionSeed Fraction of User1's balance to withdraw
    /// @custom:audit-property USDC-54: Multi-user interleaved operations maintain consistency
    /// @custom:audit-category Multi-Step Sequences
    /// @custom:audit-severity Critical
    function testFuzz_Sequence_MultiUserInterleaved(
        uint256 amount1Seed,
        uint256 amount2Seed,
        uint256 withdrawFractionSeed
    ) public {
        uint256 amount1 = _boundUsdcAmount(amount1Seed);
        uint256 amount2 = _boundUsdcAmount(amount2Seed);

        // User1 deposits
        _depositToVault(depositor, amount1);

        // User2 deposits
        uint256 shares2 = _depositToVault(depositor2, amount2);

        // User1 partially withdraws
        uint256 maxW1 = vault.maxWithdraw(depositor);
        vm.assume(maxW1 > 1);
        uint256 partialWithdraw = bound(withdrawFractionSeed, 1, maxW1 / 2);

        vm.prank(depositor);
        vault.withdraw(partialWithdraw, depositor, depositor);

        // User2 redeems all
        vm.prank(depositor2);
        uint256 returned2 = vault.redeem(shares2, depositor2, depositor2);

        // User1 redeems remaining
        uint256 remainingShares1 = vault.balanceOf(depositor);
        vm.prank(depositor);
        uint256 returned1 = vault.redeem(remainingShares1, depositor, depositor);

        // Total returned should approximate total deposited
        uint256 totalReturned = returned1 + partialWithdraw + returned2;
        uint256 totalDeposited = amount1 + amount2;

        assertApproxEqRel(
            totalReturned,
            totalDeposited,
            FC.MAX_ROUNDTRIP_SLIPPAGE,
            "total returned across all users should approximate total deposited"
        );

        // Vault should be empty
        assertEq(vault.totalSupply(), 0, "vault should be empty after all users redeem");
    }
}
