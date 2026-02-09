// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {USDCVaultFuzzTestBase} from "../base/USDCVaultFuzzTestBase.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";

/// @title USDCVaultIlliquidityFuzzTest
/// @author Bitmor Protocol
/// @notice Fuzz tests for vault behavior under BLP illiquidity conditions
/// @dev Uses `mockBitmorPool.simulateBorrow()` to drain aToken liquidity,
///      creating a gap between `totalAssets()` (includes lent-out) and
///      `withdrawableAssets()` (only liquid). Tests maxWithdraw caps,
///      withdrawal revert behavior, and partial liquidity recovery.
///
/// ## Test Coverage
/// - USDC-45: maxWithdraw correctly caps at available liquidity during illiquidity
/// - USDC-46: Withdrawal at maxWithdraw succeeds during illiquidity
/// - USDC-47: Withdrawal exceeding maxWithdraw reverts cleanly
/// - USDC-48: totalAssets includes illiquid BLP funds (correct share pricing)
/// - USDC-49: maxWithdraw recovers after liquidity returns to BLP
///
/// @custom:audit-category Liquidity Management, BLP Illiquidity
contract USDCVaultIlliquidityFuzzTest is USDCVaultFuzzTestBase {
    function setUp() public override {
        super.setUp();
    }

    // ============ Helpers ============

    /// @notice Simulates BLP illiquidity by draining a fraction of aToken liquidity
    /// @param utilizationBps Utilization rate in basis points (e.g., 5000 = 50% borrowed)
    function _simulateBLPUtilization(uint256 utilizationBps) internal {
        // Get current BLP available liquidity (USDC on the aToken contract)
        uint256 blpAvailable = mockUSDC.balanceOf(address(mockBitmorAToken));
        if (blpAvailable == 0) return;

        uint256 amountToBorrow = (blpAvailable * utilizationBps) / 10_000;
        if (amountToBorrow == 0) return;

        mockBitmorPool.simulateBorrow(address(mockUSDC), amountToBorrow);
    }

    // ============ Tests ============

    /// @notice maxWithdraw should be capped at available liquidity, not totalAssets
    /// @dev When BLP is illiquid, maxWithdraw = min(ownerAssets, withdrawable + idle)
    /// @param depositSeed Seed for deposit amount
    /// @param utilizationSeed Seed for BLP utilization rate
    /// @custom:audit-property USDC-45: maxWithdraw caps at available liquidity
    /// @custom:audit-category Liquidity Management
    /// @custom:audit-severity Critical
    function testFuzz_MaxWithdraw_CapsAtAvailableLiquidity(uint256 depositSeed, uint256 utilizationSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);
        uint256 utilizationBps = bound(utilizationSeed, 1000, 9500); // 10% to 95%

        _depositToVault(depositor, depositAmount);

        // Simulate BLP illiquidity
        _simulateBLPUtilization(utilizationBps);

        uint256 maxWithdraw = vault.maxWithdraw(depositor);
        uint256 available = strategy.withdrawableAssets() + mockUSDC.balanceOf(address(vault));

        // maxWithdraw must not exceed actual available liquidity
        assertLe(maxWithdraw, available, "maxWithdraw must not exceed available liquidity during illiquidity");

        // maxWithdraw must not exceed owner's entitled assets
        uint256 ownerAssets = vault.convertToAssets(vault.balanceOf(depositor));
        assertLe(maxWithdraw, ownerAssets, "maxWithdraw must not exceed owner's entitled assets");
    }

    /// @notice Withdrawing exactly maxWithdraw should succeed even during illiquidity
    /// @param depositSeed Seed for deposit amount
    /// @param utilizationSeed Seed for BLP utilization rate
    /// @custom:audit-property USDC-46: Withdrawal at maxWithdraw succeeds during illiquidity
    /// @custom:audit-category Liquidity Management
    /// @custom:audit-severity Critical
    function testFuzz_Withdraw_SucceedsAtMaxWithdraw_DuringIlliquidity(uint256 depositSeed, uint256 utilizationSeed)
        public
    {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);
        uint256 utilizationBps = bound(utilizationSeed, 1000, 9000);

        _depositToVault(depositor, depositAmount);
        _simulateBLPUtilization(utilizationBps);

        uint256 maxWithdraw = vault.maxWithdraw(depositor);
        vm.assume(maxWithdraw > 0);

        uint256 balanceBefore = mockUSDC.balanceOf(depositor);

        vm.prank(depositor);
        vault.withdraw(maxWithdraw, depositor, depositor);

        uint256 balanceAfter = mockUSDC.balanceOf(depositor);
        assertEq(balanceAfter - balanceBefore, maxWithdraw, "depositor should receive exactly maxWithdraw");
    }

    /// @notice Withdrawing more than maxWithdraw should revert during illiquidity
    /// @param depositSeed Seed for deposit amount
    /// @param utilizationSeed Seed for BLP utilization rate
    /// @param excessSeed Seed for excess amount
    /// @custom:audit-property USDC-47: Withdrawal exceeding maxWithdraw reverts
    /// @custom:audit-category Liquidity Management
    /// @custom:audit-severity High
    function testFuzz_Withdraw_RevertsWhenExceedingLiquidity(
        uint256 depositSeed,
        uint256 utilizationSeed,
        uint256 excessSeed
    ) public {
        uint256 depositAmount = bound(depositSeed, 10e6, FC.MAX_USDC_AMOUNT);
        uint256 utilizationBps = bound(utilizationSeed, 5000, 9500); // High utilization

        _depositToVault(depositor, depositAmount);
        _simulateBLPUtilization(utilizationBps);

        uint256 maxWithdraw = vault.maxWithdraw(depositor);
        uint256 ownerAssets = vault.convertToAssets(vault.balanceOf(depositor));

        // Only test if illiquidity actually creates a gap
        vm.assume(maxWithdraw < ownerAssets);

        // Try to withdraw more than available but within owner's entitlement
        uint256 excess = bound(excessSeed, 1, ownerAssets - maxWithdraw);
        uint256 tooMuch = maxWithdraw + excess;

        vm.expectRevert();
        vm.prank(depositor);
        vault.withdraw(tooMuch, depositor, depositor);
    }

    /// @notice totalAssets should include illiquid BLP funds for correct share pricing
    /// @param depositSeed Seed for deposit amount
    /// @param utilizationSeed Seed for BLP utilization rate
    /// @custom:audit-property USDC-48: totalAssets includes illiquid BLP funds
    /// @custom:audit-category Vault Accounting
    /// @custom:audit-severity High
    function testFuzz_TotalAssets_IncludesIlliquidFunds(uint256 depositSeed, uint256 utilizationSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);
        uint256 utilizationBps = bound(utilizationSeed, 1000, 9500);

        _depositToVault(depositor, depositAmount);

        uint256 totalBefore = vault.totalAssets();

        // Simulate illiquidity — should NOT change totalAssets
        _simulateBLPUtilization(utilizationBps);

        uint256 totalAfter = vault.totalAssets();

        assertEq(
            totalAfter,
            totalBefore,
            "totalAssets should not change when BLP utilization changes (illiquid funds still counted)"
        );
    }

    /// @notice maxWithdraw should recover when BLP liquidity returns
    /// @param depositSeed Seed for deposit amount
    /// @custom:audit-property USDC-49: maxWithdraw recovers after liquidity returns
    /// @custom:audit-category Liquidity Management
    /// @custom:audit-severity High
    function testFuzz_MaxWithdraw_RecoversAfterRepay(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        _depositToVault(depositor, depositAmount);

        uint256 maxBefore = vault.maxWithdraw(depositor);

        // Create illiquidity
        uint256 blpAvailable = mockUSDC.balanceOf(address(mockBitmorAToken));
        vm.assume(blpAvailable > 0);
        uint256 borrowAmount = blpAvailable / 2;

        mockBitmorPool.simulateBorrow(address(mockUSDC), borrowAmount);

        uint256 maxDuring = vault.maxWithdraw(depositor);

        // Repay simulated borrow
        mockBitmorPool.simulateRepay(address(mockUSDC), borrowAmount);

        uint256 maxAfter = vault.maxWithdraw(depositor);

        assertLe(maxDuring, maxBefore, "maxWithdraw should decrease during illiquidity");
        assertEq(maxAfter, maxBefore, "maxWithdraw should recover after repay");
    }
}
