// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTestForBTCVault} from "../../unit/Vault/BaseTestForBTCVault.t.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {MockTokenizedStrategy} from "../../mock/MockTokenizedStrategy.sol";
import {MockYieldSource} from "../../mock/MockYieldSource.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";

/// @title BTCVaultIlliquidityFuzzTest
/// @author Bitmor Protocol
/// @notice Fuzz tests for BTCVault maxWithdraw/maxRedeem under constrained liquidity
/// @dev Simulates illiquidity by draining the MockYieldSource's tracked balance,
///      reducing what the strategy reports as withdrawable. Validates that ERC-4626
///      max* return values NEVER cause reverts when passed to withdraw/redeem.
///
/// ## Test Coverage
/// - BTC-LIQ-01: withdraw(maxWithdraw(owner)) never reverts under any drain %
/// - BTC-LIQ-02: redeem(maxRedeem(owner)) never reverts under any drain %
/// - BTC-LIQ-03: maxWithdraw never exceeds owner's asset entitlement
/// - BTC-LIQ-04: maxRedeem never exceeds owner's share balance
/// - BTC-LIQ-05: maxWithdraw caps at available liquidity minus exit fee
/// - BTC-LIQ-06: maxRedeem caps at shares derivable from available liquidity
///
/// @custom:audit-category Liquidity Management, ERC-4626 Compliance
contract BTCVaultIlliquidityFuzzTest is BaseTestForBTCVault {
    // ============ Helpers ============

    /// @notice Add strategy via proper access control
    function _addStrategy(address strat, uint256 cap) internal {
        _scheduleAndExecuteLocal(bvc, BVC_ID(), abi.encodeCall(BTCVault.addStrategy, (strat, cap)));
    }

    /// @notice Deposit as user with proper approval
    function _depositAsUser(uint256 amount) internal returns (uint256 shares) {
        vm.startPrank(user);
        mockUSDC.approve(address(vault), amount);
        shares = vault.deposit(amount, user);
        vm.stopPrank();
    }

    /// @notice Drain yield source balance to simulate illiquidity
    /// @dev Reduces the yield source's tracked balance without moving actual tokens,
    ///      making the strategy report less totalAssets and thus less maxWithdraw.
    function _drainYieldSource(uint256 amount) internal {
        vm.prank(address(strategy));
        yieldSource.withdraw(address(mockUSDC), amount);
    }

    /// @notice Returns the strategy's max withdrawable as seen by the vault
    function _getStrategyMaxWithdrawable() internal view returns (uint256) {
        return strategy.maxWithdraw(address(vault));
    }

    /// @notice Bounds deposit to a valid range for MockTokenizedStrategy (USDC 6 decimals)
    /// @param raw Raw fuzz input
    /// @return Bounded deposit amount (1k to 10M USDC)
    function _boundDeposit(uint256 raw) internal pure returns (uint256) {
        return bound(raw, 1000e6, FC.MAX_USDC_AMOUNT);
    }

    /// @notice Bounds drain percentage to 0-100% in basis points
    /// @param raw Raw fuzz input
    /// @return Bounded drain BPS (0 to 10000)
    function _boundDrainBps(uint256 raw) internal pure returns (uint256) {
        return bound(raw, 0, FC.BPS_DENOMINATOR);
    }

    /// @notice Standard setup: add strategy, mint funds, deposit, drain by percentage
    /// @return totalLiq The strategy liquidity before drain
    /// @return drainAmount The amount drained
    function _setupAndDrain(uint256 depositAmount, uint256 drainBps)
        internal
        returns (uint256 totalLiq, uint256 drainAmount)
    {
        _addStrategy(address(strategy), depositAmount * 2);
        mockUSDC.mint(user, depositAmount);
        _depositAsUser(depositAmount);

        totalLiq = _getStrategyMaxWithdrawable();
        drainAmount = (totalLiq * drainBps) / FC.BPS_DENOMINATOR;
        if (drainAmount > 0) {
            _drainYieldSource(drainAmount);
        }
    }

    // ============ ERC-4626 Round-Trip Compliance ============

    /// @notice withdraw(maxWithdraw(owner)) MUST NOT revert for any drain percentage
    /// @param depositSeed Seed for deposit amount
    /// @param drainSeed Seed for drain percentage
    /// @custom:audit-property BTC-LIQ-01: maxWithdraw is always safe to withdraw
    /// @custom:audit-severity Critical
    function testFuzz_withdraw_MaxWithdraw_NeverReverts(uint256 depositSeed, uint256 drainSeed) public {
        uint256 depositAmount = _boundDeposit(depositSeed);
        uint256 drainBps = _boundDrainBps(drainSeed);

        _setupAndDrain(depositAmount, drainBps);

        uint256 maxWithdrawable = vault.maxWithdraw(user);

        if (maxWithdrawable > 0) {
            uint256 balanceBefore = mockUSDC.balanceOf(user);

            vm.prank(user);
            vault.withdraw(maxWithdrawable, user, user);

            uint256 balanceAfter = mockUSDC.balanceOf(user);
            assertEq(balanceAfter - balanceBefore, maxWithdrawable, "user should receive exactly maxWithdraw assets");
        }
    }

    /// @notice redeem(maxRedeem(owner)) MUST NOT revert for any drain percentage
    /// @param depositSeed Seed for deposit amount
    /// @param drainSeed Seed for drain percentage
    /// @custom:audit-property BTC-LIQ-02: maxRedeem is always safe to redeem
    /// @custom:audit-severity Critical
    function testFuzz_redeem_MaxRedeem_NeverReverts(uint256 depositSeed, uint256 drainSeed) public {
        uint256 depositAmount = _boundDeposit(depositSeed);
        uint256 drainBps = _boundDrainBps(drainSeed);

        _setupAndDrain(depositAmount, drainBps);

        uint256 maxRedeemable = vault.maxRedeem(user);

        if (maxRedeemable > 0) {
            uint256 balanceBefore = mockUSDC.balanceOf(user);

            vm.prank(user);
            uint256 assetsReceived = vault.redeem(maxRedeemable, user, user);

            uint256 balanceAfter = mockUSDC.balanceOf(user);
            assertEq(balanceAfter - balanceBefore, assetsReceived, "user should receive redeem assets");
            assertGt(assetsReceived, 0, "should receive non-zero assets");
        }
    }

    // ============ Bound Invariants ============

    /// @notice maxWithdraw MUST never exceed owner's asset entitlement
    /// @param depositSeed Seed for deposit amount
    /// @param drainSeed Seed for drain percentage
    /// @custom:audit-property BTC-LIQ-03: maxWithdraw <= convertToAssets(balanceOf(owner))
    /// @custom:audit-severity Critical
    function testFuzz_maxWithdraw_NeverExceedsOwnerAssets(uint256 depositSeed, uint256 drainSeed) public {
        uint256 depositAmount = _boundDeposit(depositSeed);
        uint256 drainBps = _boundDrainBps(drainSeed);

        _setupAndDrain(depositAmount, drainBps);

        uint256 maxWithdrawable = vault.maxWithdraw(user);
        uint256 ownerAssets = vault.convertToAssets(vault.balanceOf(user));

        assertLe(maxWithdrawable, ownerAssets, "maxWithdraw must never exceed owner's asset entitlement");
    }

    /// @notice maxRedeem MUST never exceed owner's share balance
    /// @param depositSeed Seed for deposit amount
    /// @param drainSeed Seed for drain percentage
    /// @custom:audit-property BTC-LIQ-04: maxRedeem <= balanceOf(owner)
    /// @custom:audit-severity Critical
    function testFuzz_maxRedeem_NeverExceedsOwnerShares(uint256 depositSeed, uint256 drainSeed) public {
        uint256 depositAmount = _boundDeposit(depositSeed);
        uint256 drainBps = _boundDrainBps(drainSeed);

        _setupAndDrain(depositAmount, drainBps);

        uint256 maxRedeemable = vault.maxRedeem(user);
        uint256 ownerShares = vault.balanceOf(user);

        assertLe(maxRedeemable, ownerShares, "maxRedeem must never exceed owner's share balance");
    }

    // ============ Liquidity Cap Verification ============

    /// @notice maxWithdraw should cap at available liquidity minus exit fee under illiquidity
    /// @dev Uses a high drain range (80-99.9%) to guarantee illiquidity without vm.assume.
    ///      Entry fee reduces deposited assets to ~99.9% of input, so draining >~0.1% creates
    ///      the constraint `availableLiquidity < ownerAssets`.
    /// @param depositSeed Seed for deposit amount
    /// @param drainSeed Seed for drain percentage
    /// @custom:audit-property BTC-LIQ-05: maxWithdraw caps at liquidity minus fee
    /// @custom:audit-severity High
    function testFuzz_maxWithdraw_CapsAtLiquidityMinusFee(uint256 depositSeed, uint256 drainSeed) public {
        uint256 depositAmount = _boundDeposit(depositSeed);
        uint256 drainBps = bound(drainSeed, 8000, 9990); // 80-99.9% drain guarantees illiquidity

        _setupAndDrain(depositAmount, drainBps);

        uint256 availableLiquidity = _getStrategyMaxWithdrawable();
        uint256 ownerAssets = vault.convertToAssets(vault.balanceOf(user));

        // Skip if not actually constrained (entry fee rounding edge)
        if (availableLiquidity >= ownerAssets) return;

        uint256 maxWithdrawable = vault.maxWithdraw(user);
        uint256 exitFee = vault.getExitFee();
        uint256 expectedMax = availableLiquidity - vault.feeOnTotal(availableLiquidity, exitFee);

        assertEq(maxWithdrawable, expectedMax, "maxWithdraw should equal liquidity minus fee when constrained");
    }

    /// @notice maxRedeem should cap at shares from available liquidity under illiquidity
    /// @dev Uses a high drain range (80-99.9%) to guarantee illiquidity without vm.assume.
    /// @param depositSeed Seed for deposit amount
    /// @param drainSeed Seed for drain percentage
    /// @custom:audit-property BTC-LIQ-06: maxRedeem caps at convertToShares(liquidity)
    /// @custom:audit-severity High
    function testFuzz_maxRedeem_CapsAtSharesFromLiquidity(uint256 depositSeed, uint256 drainSeed) public {
        uint256 depositAmount = _boundDeposit(depositSeed);
        uint256 drainBps = bound(drainSeed, 8000, 9990);

        _setupAndDrain(depositAmount, drainBps);

        uint256 availableLiquidity = _getStrategyMaxWithdrawable();
        uint256 ownerAssets = vault.convertToAssets(vault.balanceOf(user));

        if (availableLiquidity >= ownerAssets) return;

        uint256 maxRedeemable = vault.maxRedeem(user);
        uint256 expectedMaxShares = vault.convertToShares(availableLiquidity);

        assertEq(maxRedeemable, expectedMaxShares, "maxRedeem should equal shares from liquidity when constrained");
    }
}
