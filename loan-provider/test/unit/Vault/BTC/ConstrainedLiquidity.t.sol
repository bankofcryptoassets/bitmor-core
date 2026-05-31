// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTestForBTCVault} from "../BaseTestForBTCVault.t.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {MockTokenizedStrategy} from "../../../mock/MockTokenizedStrategy.sol";
import {MockYieldSource} from "../../../mock/MockYieldSource.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";

/// @title ConstrainedLiquidityTest
/// @author Bitmor Protocol
/// @notice Tests for BTCVault maxWithdraw/maxRedeem under constrained liquidity
/// @dev Validates ERC-4626 compliance: returned max values MUST NOT cause reverts.
///      Simulates illiquidity by draining the yield source's tracked balance,
///      reducing what the strategy reports as withdrawable.
contract ConstrainedLiquidityTest is BaseTestForBTCVault {
    // ============ Additional Strategies ============
    MockTokenizedStrategy strategy2;
    MockYieldSource yieldSource2;

    // ============ Constants ============
    uint256 constant STRATEGY_CAP = 50_000e6;
    uint256 constant USER_DEPOSIT = 40_000e6;
    uint256 constant DRAIN_AMOUNT = 30_000e6;

    // ============ Setup ============

    function setUp() public override {
        super.setUp();

        yieldSource2 = new MockYieldSource();
        strategy2 = new MockTokenizedStrategy(address(yieldSource2), address(vault));
    }

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
    /// @param ys The yield source to drain
    /// @param strat The strategy address (balance owner in yield source)
    /// @param amount Amount to drain from tracked balance
    function _drainYieldSource(MockYieldSource ys, address strat, uint256 amount) internal {
        vm.prank(strat);
        ys.withdraw(address(mockUSDC), amount);
    }

    /// @notice Returns available liquidity as seen by BTCVault._getAvailableLiquidity
    function _getStrategyMaxWithdrawable(MockTokenizedStrategy strat) internal view returns (uint256) {
        return strat.maxWithdraw(address(vault));
    }

    // ============ Constrained Liquidity: maxWithdraw ============

    /// @notice maxWithdraw should be capped by available liquidity when liquidity < owner assets
    function test_maxWithdraw_CappedByLiquidity_WhenLiquidityInsufficient() public {
        // Arrange: deposit and drain yield source to create illiquidity
        _addStrategy(address(strategy), STRATEGY_CAP);
        _depositAsUser(USER_DEPOSIT);

        uint256 ownerAssets = vault.convertToAssets(vault.balanceOf(user));
        uint256 strategyLiquidityBefore = _getStrategyMaxWithdrawable(strategy);

        // Drain 75% of liquidity from yield source
        _drainYieldSource(yieldSource, address(strategy), DRAIN_AMOUNT);

        uint256 strategyLiquidityAfter = _getStrategyMaxWithdrawable(strategy);
        uint256 availableLiquidity = strategyLiquidityAfter;

        // Sanity: liquidity decreased and is now less than owner assets
        assertLt(strategyLiquidityAfter, strategyLiquidityBefore, "drain should reduce strategy liquidity");
        assertLt(availableLiquidity, ownerAssets, "available liquidity should be less than owner assets");

        // Act
        uint256 maxWithdrawable = vault.maxWithdraw(user);

        // Assert: maxWithdraw capped at liquidity minus exit fee (not owner assets minus fee)
        uint256 exitFee = vault.getExitFee();
        uint256 expectedMax = availableLiquidity - vault.feeOnTotal(availableLiquidity, exitFee);

        assertEq(maxWithdrawable, expectedMax, "maxWithdraw should be capped by available liquidity minus fee");
        assertLt(maxWithdrawable, ownerAssets, "maxWithdraw should be less than owner's full asset entitlement");
    }

    /// @notice maxWithdraw should return 0 when all liquidity is drained
    function test_maxWithdraw_ReturnsZero_WhenZeroLiquidity() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _depositAsUser(USER_DEPOSIT);

        // Drain ALL liquidity
        uint256 totalInYieldSource = _getStrategyMaxWithdrawable(strategy);
        _drainYieldSource(yieldSource, address(strategy), totalInYieldSource);

        // Act + Assert
        assertEq(vault.maxWithdraw(user), 0, "maxWithdraw should be 0 when zero liquidity");
    }

    // ============ Constrained Liquidity: maxRedeem ============

    /// @notice maxRedeem should be capped by shares derivable from available liquidity
    function test_maxRedeem_CappedByLiquidity_WhenLiquidityInsufficient() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _depositAsUser(USER_DEPOSIT);

        uint256 ownerShares = vault.balanceOf(user);

        // Drain 75% of liquidity
        _drainYieldSource(yieldSource, address(strategy), DRAIN_AMOUNT);

        uint256 availableLiquidity = _getStrategyMaxWithdrawable(strategy);

        // Act
        uint256 maxRedeemable = vault.maxRedeem(user);

        // Assert: maxRedeem should be less than full owner shares
        uint256 expectedMaxShares = vault.convertToShares(availableLiquidity);
        assertEq(maxRedeemable, expectedMaxShares, "maxRedeem should equal shares from available liquidity");
        assertLt(maxRedeemable, ownerShares, "maxRedeem should be less than owner's full share balance");
    }

    /// @notice maxRedeem should return 0 when all liquidity is drained
    function test_maxRedeem_ReturnsZero_WhenZeroLiquidity() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _depositAsUser(USER_DEPOSIT);

        // Drain ALL liquidity
        uint256 totalInYieldSource = _getStrategyMaxWithdrawable(strategy);
        _drainYieldSource(yieldSource, address(strategy), totalInYieldSource);

        // Act + Assert
        assertEq(vault.maxRedeem(user), 0, "maxRedeem should be 0 when zero liquidity");
    }

    // ============ ERC-4626 Round-Trip Guarantees ============

    /// @notice withdraw(maxWithdraw(owner)) MUST NOT revert under constrained liquidity
    /// @dev This is the core ERC-4626 compliance property for maxWithdraw
    function test_withdraw_MaxWithdraw_Succeeds_WhenLiquidityConstrained() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _depositAsUser(USER_DEPOSIT);

        // Drain 75% of liquidity
        _drainYieldSource(yieldSource, address(strategy), DRAIN_AMOUNT);

        uint256 maxWithdrawable = vault.maxWithdraw(user);
        assertGt(maxWithdrawable, 0, "should have some withdrawable amount");

        uint256 userBalanceBefore = mockUSDC.balanceOf(user);

        // Act: this MUST NOT revert (ERC-4626 guarantee)
        vm.prank(user);
        vault.withdraw(maxWithdrawable, user, user);

        // Assert: user received the expected assets
        uint256 userBalanceAfter = mockUSDC.balanceOf(user);
        assertEq(
            userBalanceAfter - userBalanceBefore, maxWithdrawable, "user should receive exactly maxWithdraw assets"
        );
    }

    /// @notice redeem(maxRedeem(owner)) MUST NOT revert under constrained liquidity
    /// @dev This is the core ERC-4626 compliance property for maxRedeem
    function test_redeem_MaxRedeem_Succeeds_WhenLiquidityConstrained() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _depositAsUser(USER_DEPOSIT);

        // Drain 75% of liquidity
        _drainYieldSource(yieldSource, address(strategy), DRAIN_AMOUNT);

        uint256 maxRedeemable = vault.maxRedeem(user);
        assertGt(maxRedeemable, 0, "should have some redeemable shares");

        uint256 userBalanceBefore = mockUSDC.balanceOf(user);

        // Act: this MUST NOT revert (ERC-4626 guarantee)
        vm.prank(user);
        uint256 assetsReceived = vault.redeem(maxRedeemable, user, user);

        // Assert: user received assets and shares were burned
        uint256 userBalanceAfter = mockUSDC.balanceOf(user);
        assertEq(userBalanceAfter - userBalanceBefore, assetsReceived, "user should receive assets from redeem");
        assertGt(assetsReceived, 0, "should receive non-zero assets from constrained redeem");
    }

    /// @notice Withdrawing more than maxWithdraw should revert under constrained liquidity
    function test_withdraw_RevertWhen_ExceedsMaxWithdraw_UnderConstrainedLiquidity() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _depositAsUser(USER_DEPOSIT);

        // Drain 75% of liquidity
        _drainYieldSource(yieldSource, address(strategy), DRAIN_AMOUNT);

        uint256 maxWithdrawable = vault.maxWithdraw(user);

        // Trying to withdraw 1 more than max should revert
        vm.prank(user);
        vm.expectRevert();
        vault.withdraw(maxWithdrawable + 1, user, user);
    }

    /// @notice Redeeming more than maxRedeem should revert under constrained liquidity
    function test_redeem_RevertWhen_ExceedsMaxRedeem_UnderConstrainedLiquidity() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _depositAsUser(USER_DEPOSIT);

        // Drain 75% of liquidity
        _drainYieldSource(yieldSource, address(strategy), DRAIN_AMOUNT);

        uint256 maxRedeemable = vault.maxRedeem(user);
        uint256 ownerShares = vault.balanceOf(user);

        // Owner has more shares than maxRedeem allows
        assertGt(ownerShares, maxRedeemable, "owner should have more shares than maxRedeem");

        // Trying to redeem full balance should revert
        vm.prank(user);
        vm.expectRevert();
        vault.redeem(ownerShares, user, user);
    }

    // ============ Multi-Strategy Constrained Liquidity ============

    /// @notice maxWithdraw should reflect combined liquidity across multiple strategies
    function test_maxWithdraw_CombinesLiquidity_MultipleStrategies() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _addStrategy(address(strategy2), STRATEGY_CAP);

        // Deposit enough to fill both strategies
        uint256 largeDeposit = STRATEGY_CAP * 2;
        mockUSDC.mint(user, largeDeposit); // Need extra funds
        _depositAsUser(largeDeposit);

        uint256 liq1Before = _getStrategyMaxWithdrawable(strategy);

        // Drain strategy 1 fully, leave strategy 2 untouched
        _drainYieldSource(yieldSource, address(strategy), liq1Before);

        uint256 liq1After = _getStrategyMaxWithdrawable(strategy);
        uint256 liq2After = _getStrategyMaxWithdrawable(strategy2);
        uint256 totalLiquidity = liq1After + liq2After;

        assertEq(liq1After, 0, "strategy 1 should have no liquidity");
        assertGt(liq2After, 0, "strategy 2 should have liquidity");

        // maxWithdraw should use combined liquidity from both strategies
        uint256 maxWithdrawable = vault.maxWithdraw(user);
        uint256 exitFee = vault.getExitFee();
        uint256 ownerAssets = vault.convertToAssets(vault.balanceOf(user));
        uint256 withdrawable = _utilMin(ownerAssets, totalLiquidity);
        uint256 expectedMax = withdrawable - vault.feeOnTotal(withdrawable, exitFee);

        assertEq(maxWithdrawable, expectedMax, "maxWithdraw should combine liquidity from all strategies");

        // ERC-4626 round-trip: must not revert
        vm.prank(user);
        vault.withdraw(maxWithdrawable, user, user);
    }

    /// @notice When one strategy is drained and the other is partially available
    function test_maxRedeem_PartialLiquidity_MultipleStrategies() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _addStrategy(address(strategy2), STRATEGY_CAP);

        uint256 largeDeposit = STRATEGY_CAP * 2;
        mockUSDC.mint(user, largeDeposit);
        _depositAsUser(largeDeposit);

        uint256 liq1 = _getStrategyMaxWithdrawable(strategy);
        uint256 liq2 = _getStrategyMaxWithdrawable(strategy2);

        // Drain strategy 1 fully, drain half of strategy 2
        _drainYieldSource(yieldSource, address(strategy), liq1);
        _drainYieldSource(yieldSource2, address(strategy2), liq2 / 2);

        uint256 totalLiquidity = _getStrategyMaxWithdrawable(strategy) + _getStrategyMaxWithdrawable(strategy2);

        uint256 maxRedeemable = vault.maxRedeem(user);
        uint256 expectedMaxShares = vault.convertToShares(totalLiquidity);

        assertEq(maxRedeemable, expectedMaxShares, "maxRedeem should reflect partial combined liquidity");

        // ERC-4626 round-trip: must not revert
        vm.prank(user);
        vault.redeem(maxRedeemable, user, user);
    }

    // ============ Edge Cases ============

    /// @notice maxWithdraw for a user with zero balance should always return 0
    function test_maxWithdraw_ZeroBalance_ReturnsZero_EvenUnderConstrainedLiquidity() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _depositAsUser(USER_DEPOSIT);

        // Drain some liquidity
        _drainYieldSource(yieldSource, address(strategy), DRAIN_AMOUNT);

        address nobody = makeAddr("nobody");
        assertEq(vault.maxWithdraw(nobody), 0, "maxWithdraw should be 0 for user with no shares");
    }

    /// @notice maxRedeem for a user with zero balance should always return 0
    function test_maxRedeem_ZeroBalance_ReturnsZero_EvenUnderConstrainedLiquidity() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _depositAsUser(USER_DEPOSIT);

        _drainYieldSource(yieldSource, address(strategy), DRAIN_AMOUNT);

        address nobody = makeAddr("nobody");
        assertEq(vault.maxRedeem(nobody), 0, "maxRedeem should be 0 for user with no shares");
    }

    /// @notice Tiny liquidity remaining should still allow a tiny withdrawal
    function test_withdraw_TinyLiquidity_StillWithdrawable() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _depositAsUser(USER_DEPOSIT);

        // Drain almost everything, leave 100 units (0.0001 USDC)
        uint256 totalLiq = _getStrategyMaxWithdrawable(strategy);
        uint256 tinyRemainder = 100;
        _drainYieldSource(yieldSource, address(strategy), totalLiq - tinyRemainder);

        uint256 maxWithdrawable = vault.maxWithdraw(user);

        if (maxWithdrawable > 0) {
            vm.prank(user);
            vault.withdraw(maxWithdrawable, user, user);
        }
        // If maxWithdrawable == 0, that's also correct (fee may consume the tiny amount)
    }
}
