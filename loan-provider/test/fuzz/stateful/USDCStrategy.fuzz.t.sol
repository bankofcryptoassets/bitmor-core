// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { USDCVaultFuzzTestBase } from "../base/USDCVaultFuzzTestBase.sol";
import { FuzzConstants as FC } from "../helpers/FuzzConstants.sol";

/**
 * @title USDCStrategyFuzzTest
 * @author Bitmor Protocol
 * @notice Fuzz tests for USDCStrategy contract (USDC-08 through USDC-18)
 * @dev Tests supply, withdraw, withdrawAllFunds, and reallocation with fuzzed parameters.
 *      All direct strategy calls use `vm.prank(address(vault))` to satisfy the `onlyVault` modifier.
 *      Uses real `USDCVault` and `USDCStrategy` contracts backed by `MockAaveV3Pool` and `MockBitmorLendingPool`.
 *
 * ## Test Coverage
 * - Supply splits assets per configured Aave allocation ratio
 * - Supply correctly increases `totalAssets`
 * - Withdraw maintains allocation ratio and transfers exact amount to vault
 * - WithdrawAllFunds empties both markets and preserves total
 * - Reallocation moves to target ratio or skips when delta is below threshold
 * - Edge cases: 0% allocation (all to BLP) and 100% allocation (all to Aave)
 *
 * @custom:audit-category Strategy Operations, Allocation Management
 */
contract USDCStrategyFuzzTest is USDCVaultFuzzTestBase {
    // ============ Constants ============

    /// @dev Allocation tolerance for ratio assertions (2% in basis points)
    uint256 internal constant ALLOCATION_TOLERANCE_BPS = FC.ALLOCATION_TOLERANCE_BPS;

    // ============ Setup ============

    function setUp() public override {
        super.setUp();
    }

    // ============ Supply Tests ============

    /**
     * @notice Verifies that `supply` splits deposited USDC between Aave and BLP per the configured allocation
     * @dev Sets a fuzzed allocation, funds the vault with USDC, then calls `strategy.supply`.
     *      Asserts that Aave received `amount * allocation / 10000` and BLP received the remainder.
     * @param amountSeed Seed for bounded USDC deposit amount
     * @param allocationSeed Seed for bounded Aave allocation in basis points
     * @custom:audit-property USDC-08: Supply splits assets per configured Aave allocation ratio
     * @custom:audit-category Strategy Operations
     * @custom:audit-severity Critical
     */
    function testFuzz_Supply_SplitsPerAllocation(
        uint256 amountSeed,
        uint256 allocationSeed
    ) public {
        uint256 amount = _boundUsdcAmount(amountSeed);
        uint256 allocationBps = _boundAllocationBps(allocationSeed);

        // Configure allocation before supplying
        _setAllocation(allocationBps);

        // Fund the vault with USDC (strategy does transferFrom from vault)
        mockUSDC.mint(address(vault), amount);

        // Record balances before supply
        uint256 aaveBefore = _getAaveBalance();
        uint256 blpBefore = _getBLPBalance();

        // Supply via strategy (onlyVault)
        vm.prank(address(vault));
        strategy.supply(amount);

        // Calculate expected split
        uint256 expectedAaveIncrease = (amount * allocationBps) / BASIS_POINTS;
        uint256 expectedBlpIncrease = amount - expectedAaveIncrease;

        // Assert Aave received the correct portion
        uint256 aaveAfter = _getAaveBalance();
        assertEq(
            aaveAfter - aaveBefore,
            expectedAaveIncrease,
            "Aave should receive amount * allocation / 10000"
        );

        // Assert BLP received the remainder
        uint256 blpAfter = _getBLPBalance();
        assertEq(
            blpAfter - blpBefore,
            expectedBlpIncrease,
            "BLP should receive the remainder after Aave allocation"
        );
    }

    /**
     * @notice Verifies that `supply` increases `totalAssets` by exactly the supplied amount
     * @dev Records `totalAssets` before, funds and supplies, then asserts exact increase.
     * @param amountSeed Seed for bounded USDC deposit amount
     * @custom:audit-property USDC-09: Supply increases totalAssets by exactly the supplied amount
     * @custom:audit-category Strategy Operations
     * @custom:audit-severity Critical
     */
    function testFuzz_Supply_TotalAssetsIncreasesByAmount(uint256 amountSeed) public {
        uint256 amount = _boundUsdcAmount(amountSeed);

        // Record totalAssets before supply
        uint256 totalAssetsBefore = strategy.totalAssets();

        // Fund vault and supply
        mockUSDC.mint(address(vault), amount);
        vm.prank(address(vault));
        strategy.supply(amount);

        // Assert totalAssets increased by exactly `amount`
        uint256 totalAssetsAfter = strategy.totalAssets();
        assertEq(
            totalAssetsAfter - totalAssetsBefore,
            amount,
            "totalAssets should increase by exactly the supplied amount"
        );
    }

    // ============ Withdraw Tests ============

    /**
     * @notice Verifies that `withdraw` maintains the configured allocation ratio within tolerance
     * @dev Deposits to vault (auto-supplies via `_afterDeposit`), then withdraws a partial amount
     *      directly from the strategy, asserting the remaining allocation matches the target.
     * @param depositSeed Seed for bounded deposit amount
     * @param withdrawFractionSeed Seed for bounded withdrawal amount (partial)
     * @custom:audit-property USDC-10: Withdraw maintains allocation ratio within tolerance
     * @custom:audit-category Strategy Operations
     * @custom:audit-severity High
     */
    function testFuzz_Withdraw_MaintainsAllocationRatio(
        uint256 depositSeed,
        uint256 withdrawFractionSeed
    ) public {
        // Ensure deposit is large enough to allow a partial withdrawal with meaningful remainder
        uint256 minDepositForPartialWithdraw = FC.MIN_USDC_AMOUNT * 3;
        uint256 depositAmount = bound(
            depositSeed,
            minDepositForPartialWithdraw,
            FC.MAX_USDC_AMOUNT
        );

        // Deposit to vault (auto-supplies to strategy via _afterDeposit)
        _depositToVault(depositor, depositAmount);

        // Bound withdraw to a partial amount: [MIN_USDC, depositAmount - MIN_USDC]
        uint256 withdrawAmount = bound(
            withdrawFractionSeed,
            FC.MIN_USDC_AMOUNT,
            depositAmount - FC.MIN_USDC_AMOUNT
        );

        // Withdraw directly from strategy (onlyVault)
        vm.prank(address(vault));
        strategy.withdraw(withdrawAmount);

        // Assert remaining allocation is within tolerance of configured ratio
        _assertAllocationCorrect(FC.DEFAULT_AAVE_ALLOCATION_BPS, ALLOCATION_TOLERANCE_BPS);
    }

    /**
     * @notice Verifies that `withdraw` decreases `totalAssets` by exactly the withdrawn amount
     * @dev Deposits to vault, records `totalAssets`, withdraws a partial amount, and asserts exact decrease.
     * @param depositSeed Seed for bounded deposit amount
     * @param withdrawFractionSeed Seed for bounded withdrawal amount
     * @custom:audit-property USDC-11: Withdraw decreases totalAssets by exactly the withdrawn amount
     * @custom:audit-category Strategy Operations
     * @custom:audit-severity Critical
     */
    function testFuzz_Withdraw_TotalAssetsDecreasesByAmount(
        uint256 depositSeed,
        uint256 withdrawFractionSeed
    ) public {
        // Ensure deposit is large enough for a meaningful partial withdrawal
        uint256 minDepositForPartialWithdraw = FC.MIN_USDC_AMOUNT * 3;
        uint256 depositAmount = bound(
            depositSeed,
            minDepositForPartialWithdraw,
            FC.MAX_USDC_AMOUNT
        );

        // Deposit to vault (auto-supplies)
        _depositToVault(depositor, depositAmount);

        // Record totalAssets before withdrawal
        uint256 totalAssetsBefore = strategy.totalAssets();

        // Bound withdraw amount: [MIN_USDC, depositAmount - MIN_USDC]
        uint256 withdrawAmount = bound(
            withdrawFractionSeed,
            FC.MIN_USDC_AMOUNT,
            depositAmount - FC.MIN_USDC_AMOUNT
        );

        // Withdraw directly from strategy (onlyVault)
        vm.prank(address(vault));
        strategy.withdraw(withdrawAmount);

        // Assert totalAssets decreased by exactly `withdrawAmount`
        uint256 totalAssetsAfter = strategy.totalAssets();
        assertEq(
            totalAssetsBefore - totalAssetsAfter,
            withdrawAmount,
            "totalAssets should decrease by exactly the withdrawn amount"
        );
    }

    /**
     * @notice Verifies that `withdraw` transfers the exact requested amount to the vault
     * @dev This validates the bug fix where `safeTransfer(msg.sender, amount)` was added
     *      after `_withdrawFunds()` to ensure the vault actually receives the withdrawn USDC.
     * @param depositSeed Seed for bounded deposit amount
     * @param withdrawFractionSeed Seed for bounded withdrawal amount
     * @custom:audit-property USDC-12: Withdraw transfers exact amount to vault (validates bug fix)
     * @custom:audit-category Strategy Operations
     * @custom:audit-severity Critical
     */
    function testFuzz_Withdraw_TransfersExactAmountToVault(
        uint256 depositSeed,
        uint256 withdrawFractionSeed
    ) public {
        // Ensure deposit is large enough for a meaningful partial withdrawal
        uint256 minDepositForPartialWithdraw = FC.MIN_USDC_AMOUNT * 3;
        uint256 depositAmount = bound(
            depositSeed,
            minDepositForPartialWithdraw,
            FC.MAX_USDC_AMOUNT
        );

        // Deposit to vault (auto-supplies to strategy)
        _depositToVault(depositor, depositAmount);

        // Record vault's USDC balance before withdrawal
        uint256 vaultUsdcBefore = mockUSDC.balanceOf(address(vault));

        // Bound withdraw amount: [MIN_USDC, depositAmount - MIN_USDC]
        uint256 withdrawAmount = bound(
            withdrawFractionSeed,
            FC.MIN_USDC_AMOUNT,
            depositAmount - FC.MIN_USDC_AMOUNT
        );

        // Withdraw directly from strategy (onlyVault)
        vm.prank(address(vault));
        strategy.withdraw(withdrawAmount);

        // Assert vault USDC balance increased by exactly the withdraw amount
        uint256 vaultUsdcAfter = mockUSDC.balanceOf(address(vault));
        assertEq(
            vaultUsdcAfter - vaultUsdcBefore,
            withdrawAmount,
            "vault USDC balance should increase by exactly the withdrawn amount"
        );
    }

    // ============ WithdrawAllFunds Tests ============

    /**
     * @notice Verifies that `withdrawAllFunds` empties both Aave and BLP markets
     * @dev Deposits to vault, then calls `withdrawAllFunds` and asserts both pool balances are zero.
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property USDC-13: WithdrawAllFunds empties both Aave and BLP markets
     * @custom:audit-category Strategy Operations
     * @custom:audit-severity Critical
     */
    function testFuzz_WithdrawAllFunds_EmptiesBothMarkets(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        // Deposit to vault (auto-supplies to both pools)
        _depositToVault(depositor, depositAmount);

        // Verify funds are deployed before withdrawal
        assertGt(_getTotalBalance(), 0, "funds should be deployed before withdrawAllFunds");

        // WithdrawAllFunds (onlyVault)
        vm.prank(address(vault));
        strategy.withdrawAllFunds();

        // Assert both markets are empty
        assertEq(_getAaveBalance(), 0, "Aave balance should be zero after withdrawAllFunds");
        assertEq(_getBLPBalance(), 0, "BLP balance should be zero after withdrawAllFunds");
    }

    /**
     * @notice Verifies that `withdrawAllFunds` preserves the total value on the strategy contract
     * @dev The withdrawn funds should be held as USDC on the strategy contract itself,
     *      matching the original total deployed across both markets.
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property USDC-14: WithdrawAllFunds preserves total value on strategy contract
     * @custom:audit-category Strategy Operations
     * @custom:audit-severity High
     */
    function testFuzz_WithdrawAllFunds_PreservesTotal(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        // Deposit to vault (auto-supplies)
        _depositToVault(depositor, depositAmount);

        // Record total balance across both markets
        uint256 totalBefore = _getTotalBalance();

        // WithdrawAllFunds (onlyVault)
        vm.prank(address(vault));
        strategy.withdrawAllFunds();

        // Assert strategy's USDC balance equals the original total deployed
        uint256 strategyUsdcBalance = mockUSDC.balanceOf(address(strategy));
        assertEq(
            strategyUsdcBalance,
            totalBefore,
            "strategy USDC balance should equal original total deployed after withdrawAllFunds"
        );
    }

    // ============ Reallocation Tests ============

    /**
     * @notice Verifies that reallocation moves assets to match the new target ratio
     * @dev Sets an initial allocation, deposits, then changes the allocation and rebalances.
     *      Asserts the resulting allocation matches the new target within tolerance.
     * @param depositSeed Seed for bounded deposit amount
     * @param initialAlloc Seed for bounded initial Aave allocation
     * @param newAlloc Seed for bounded new Aave allocation
     * @custom:audit-property USDC-15: Reallocation moves assets to match new target ratio
     * @custom:audit-category Allocation Management
     * @custom:audit-severity High
     */
    function testFuzz_Reallocation_MovesToTargetRatio(
        uint256 depositSeed,
        uint256 initialAlloc,
        uint256 newAlloc
    ) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);
        // Bound allocations to [1, 10000] since _reallocateAssets skips when targetAave == 0
        uint256 initialAllocationBps = bound(initialAlloc, 1, FC.MAX_ALLOCATION_BPS);
        uint256 newAllocationBps = bound(newAlloc, 1, FC.MAX_ALLOCATION_BPS);

        // Ensure allocations are meaningfully different to avoid skip due to min delta
        vm.assume(
            initialAllocationBps > newAllocationBps
                ? initialAllocationBps - newAllocationBps > FC.DEFAULT_MIN_DELTA_BPS
                : newAllocationBps - initialAllocationBps > FC.DEFAULT_MIN_DELTA_BPS
        );

        // Set initial allocation and deposit
        _setAllocation(initialAllocationBps);
        _depositToVault(depositor, depositAmount);

        // Change allocation to new target
        _setAllocation(newAllocationBps);

        // Trigger reallocation via UVA role
        _rebalance();

        // Assert allocation matches new target within tolerance
        _assertAllocationCorrect(newAllocationBps, ALLOCATION_TOLERANCE_BPS);
    }

    /**
     * @notice Verifies that reallocation skips when the delta is below the minimum threshold
     * @dev Sets a high `minimumDeltaRequired`, makes a small allocation change, and rebalances.
     *      Asserts that balances remain unchanged because the delta percentage is below threshold.
     * @param depositSeed Seed for bounded deposit amount
     * @param deltaThreshold Seed for high delta threshold in basis points
     * @custom:audit-property USDC-16: Reallocation skips when delta is below minimum threshold
     * @custom:audit-category Allocation Management
     * @custom:audit-severity Medium
     */
    function testFuzz_Reallocation_SkipsWhenBelowMinDelta(
        uint256 depositSeed,
        uint256 deltaThreshold
    ) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        // Use the default allocation (80%) for initial deposit
        _depositToVault(depositor, depositAmount);

        // Set a high minimum delta threshold (50-100% of target balance)
        uint256 highThreshold = bound(
            deltaThreshold,
            FC.MAX_DELTA_THRESHOLD_BPS,
            FC.MAX_ALLOCATION_BPS
        );

        // Update minimum delta required via UVM_SLOW role (delayed operation)
        _scheduleAndExecuteLocal(
            uvm_slow,
            UVM_SLOW_ID(),
            abi.encodeCall(vault.updateMinimumDeltaRequired, (highThreshold))
        );

        // Record balances before reallocation attempt
        uint256 aaveBefore = _getAaveBalance();
        uint256 blpBefore = _getBLPBalance();

        // Make a small allocation change (80% -> 79%) - delta is only ~1.25% of target
        uint256 smallAdjustment = FC.DEFAULT_AAVE_ALLOCATION_BPS - 100;
        _setAllocation(smallAdjustment);

        // Attempt reallocation - should skip because delta < threshold
        _rebalance();

        // Assert balances unchanged (reallocation was skipped)
        assertEq(
            _getAaveBalance(),
            aaveBefore,
            "Aave balance should be unchanged when delta is below threshold"
        );
        assertEq(
            _getBLPBalance(),
            blpBefore,
            "BLP balance should be unchanged when delta is below threshold"
        );
    }

    // ============ Edge Case: Zero Allocation ============

    /**
     * @notice Verifies that supply sends all assets to BLP when Aave allocation is 0%
     * @dev Sets allocation to 0 (all to BLP), funds the vault, and supplies.
     *      Asserts Aave balance is zero and BLP received the full amount.
     * @param amountSeed Seed for bounded USDC amount
     * @custom:audit-property USDC-17: Supply sends all assets to BLP when allocation is 0%
     * @custom:audit-category Strategy Operations
     * @custom:audit-severity Medium
     */
    function testFuzz_Supply_AllToBlp_WhenZeroAllocation(uint256 amountSeed) public {
        uint256 amount = _boundUsdcAmount(amountSeed);

        // Set allocation to 0% Aave (all to BLP)
        _setAllocation(FC.MIN_ALLOCATION_BPS);

        // Record BLP balance before
        uint256 blpBefore = _getBLPBalance();

        // Fund vault and supply
        mockUSDC.mint(address(vault), amount);
        vm.prank(address(vault));
        strategy.supply(amount);

        // Assert Aave received nothing
        assertEq(_getAaveBalance(), 0, "Aave balance should be zero with 0% allocation");

        // Assert BLP received the full amount
        uint256 blpAfter = _getBLPBalance();
        assertEq(
            blpAfter - blpBefore,
            amount,
            "BLP should receive the full amount with 0% allocation"
        );
    }

    // ============ Edge Case: Full Allocation ============

    /**
     * @notice Verifies that supply sends all assets to Aave when Aave allocation is 100%
     * @dev Sets allocation to 10000 (all to Aave), funds the vault, and supplies.
     *      Asserts BLP balance is zero and Aave received the full amount.
     * @param amountSeed Seed for bounded USDC amount
     * @custom:audit-property USDC-18: Supply sends all assets to Aave when allocation is 100%
     * @custom:audit-category Strategy Operations
     * @custom:audit-severity Medium
     */
    function testFuzz_Supply_AllToAave_WhenFullAllocation(uint256 amountSeed) public {
        uint256 amount = _boundUsdcAmount(amountSeed);

        // Set allocation to 100% Aave (none to BLP)
        _setAllocation(FC.MAX_ALLOCATION_BPS);

        // Record Aave balance before
        uint256 aaveBefore = _getAaveBalance();

        // Fund vault and supply
        mockUSDC.mint(address(vault), amount);
        vm.prank(address(vault));
        strategy.supply(amount);

        // Assert BLP received nothing
        assertEq(_getBLPBalance(), 0, "BLP balance should be zero with 100% allocation");

        // Assert Aave received the full amount
        uint256 aaveAfter = _getAaveBalance();
        assertEq(
            aaveAfter - aaveBefore,
            amount,
            "Aave should receive the full amount with 100% allocation"
        );
    }
}
