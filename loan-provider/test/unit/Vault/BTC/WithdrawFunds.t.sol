// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTestForBTCVault} from "../BaseTestForBTCVault.t.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {MockTokenizedStrategy} from "../../../mock/MockTokenizedStrategy.sol";
import {MockYieldSource} from "../../../mock/MockYieldSource.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";

/// @title WithdrawFundsTest
/// @author Bitmor Protocol
/// @notice Tests for BTCVault `_withdrawFunds` internal logic via `withdraw`/`redeem`
/// @dev Hunts for withdrawal ordering bugs, liquidity issues, and fund extraction problems
contract WithdrawFundsTest is BaseTestForBTCVault {
    // ============ Additional Strategies ============
    MockTokenizedStrategy strategy2;
    MockYieldSource yieldSource2;

    // ============ Constants ============
    uint256 constant STRATEGY_CAP = 10000e6;
    uint256 constant LARGE_DEPOSIT_AMOUNT = 8000e6;

    // ============ Setup ============

    function setUp() public override {
        super.setUp();

        yieldSource2 = new MockYieldSource();
        strategy2 = new MockTokenizedStrategy(address(yieldSource2), address(vault));
    }

    /// @notice Helper to add strategy via proper access control
    function _addStrategy(address strat, uint256 cap) internal {
        _scheduleAndExecuteLocal(bvc, BVC_ID(), abi.encodeCall(BTCVault.addStrategy, (strat, cap)));
    }

    /// @notice Helper to deposit as user with proper approval
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
        _depositAsUser(LARGE_DEPOSIT_AMOUNT);

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
        _depositAsUser(LARGE_DEPOSIT_AMOUNT);

        uint256 assetsBeforeWithdraw = vault.getAssetInStrategy(address(strategy));
        uint256 withdrawAmount = 1000e6;

        vm.prank(user);
        vault.withdraw(withdrawAmount, user, user);

        uint256 assetsAfterWithdraw = vault.getAssetInStrategy(address(strategy));

        // Exit fee means more assets withdrawn from strategy than user receives
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
        uint256 inStrategy2Before = vault.getAssetInStrategy(address(strategy2));

        // Withdraw more than first strategy has
        uint256 largeWithdraw = inStrategy1Before + 1000e6;

        vm.prank(user);
        vault.withdraw(largeWithdraw, user, user);

        uint256 inStrategy1After = vault.getAssetInStrategy(address(strategy));
        uint256 inStrategy2After = vault.getAssetInStrategy(address(strategy2));

        // First strategy should be drained
        assertEq(inStrategy1After, 0, "first strategy should be fully drained");
        // Second strategy should have been tapped
        assertLt(inStrategy2After, inStrategy2Before, "second strategy should be reduced");
    }

    // ============ Liquidity Tests ============

    /// @notice Withdrawing more than available should revert
    function test_withdrawFunds_revertWhen_NotEnoughLiquidity() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _depositAsUser(5000e6);

        uint256 userShares = vault.balanceOf(user);
        // Try to withdraw way more than we have
        uint256 excessWithdraw = vault.convertToAssets(userShares) * 2;

        vm.prank(user);
        vm.expectRevert(); // Should revert - either ERC4626 or custom error
        vault.withdraw(excessWithdraw, user, user);
    }

    /// @notice maxWithdraw should reflect actual liquidity
    function test_maxWithdraw_ReflectsActualLiquidity() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _depositAsUser(LARGE_DEPOSIT_AMOUNT);

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
        uint256 shares = _depositAsUser(LARGE_DEPOSIT_AMOUNT);

        uint256 redeemShares = shares / 2;
        uint256 strategyBalanceBefore = vault.getAssetInStrategy(address(strategy));

        vm.prank(user);
        vault.redeem(redeemShares, user, user);

        uint256 strategyBalanceAfter = vault.getAssetInStrategy(address(strategy));

        assertLt(strategyBalanceAfter, strategyBalanceBefore, "strategy balance should decrease after redeem");
    }
}
