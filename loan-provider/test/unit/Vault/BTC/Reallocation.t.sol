// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTestForBTCVault} from "../BaseTestForBTCVault.t.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {MockTokenizedStrategy} from "../../../mock/MockTokenizedStrategy.sol";
import {MockYieldSource} from "../../../mock/MockYieldSource.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";

/// @title ReallocationTest
/// @author Bitmor Protocol
/// @notice Tests for BTCVault `reallocateFunds` and `changeStrategyCap`
/// @dev Hunts for reallocation bugs, cap enforcement issues, and fund movement errors
contract ReallocationTest is BaseTestForBTCVault {
    // ============ Additional Strategies ============
    MockTokenizedStrategy strategy2;
    MockYieldSource yieldSource2;

    // ============ Constants ============
    uint256 constant STRATEGY_CAP = 10000e6;

    // ============ Events for Testing ============
    event BTCVault__StrategyWithdrawFailed(uint256 indexed strategyIndex, uint256 amount, bytes reason);
    event BTCVault__EmergencyWithdrawFailed(uint256 indexed strategyIndex, bytes reason);

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

    /// @notice Helper to reallocate funds with proper access control
    function _reallocate(DataTypes.Allocation[] memory allocations) internal {
        _scheduleAndExecuteLocal(bva_fast, BVA_FAST_ID(), abi.encodeCall(BTCVault.reallocateFunds, (allocations)));
    }

    /// @notice Helper to change strategy cap with proper access control
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

        bytes memory data = abi.encodeCall(BTCVault.reallocateFunds, (allocations));
        _scheduleAndExpectRevertLocal(
            bva_fast, BVA_FAST_ID(), data, abi.encodeWithSelector(Errors.InvalidReallocation.selector)
        );
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

        bytes memory data = abi.encodeCall(BTCVault.reallocateFunds, (allocations));
        _scheduleAndExpectRevertLocal(
            bva_fast, BVA_FAST_ID(), data, abi.encodeWithSelector(Errors.SupplyCapExceeded.selector, 1)
        );
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

    /// @notice Decreasing cap below current allocation should work (cap is just a limit)
    function test_changeStrategyCap_DecreaseCap_BelowCurrentAllocation() public {
        _addStrategy(address(strategy), STRATEGY_CAP);
        _depositAsUser(5000e6);

        uint256 currentBalance = vault.getAssetInStrategy(address(strategy));
        uint256 newCap = currentBalance / 2; // Below current balance

        // This should work - cap can be lowered below current balance
        // (no new deposits allowed, but existing funds remain)
        _changeCap(address(strategy), newCap);

        DataTypes.Strategy memory strategyData = vault.getStrategyDetails(0);
        assertEq(strategyData.cap, newCap, "cap should be decreased even below balance");
    }

    /// @notice Setting cap to same value should revert
    function test_changeStrategyCap_revertWhen_NoChangeInCap() public {
        _addStrategy(address(strategy), STRATEGY_CAP);

        bytes memory data = abi.encodeCall(BTCVault.changeStrategyCap, (address(strategy), STRATEGY_CAP));
        _scheduleAndExpectRevertLocal(bvc, BVC_ID(), data, abi.encodeWithSelector(Errors.NoChangeInCap.selector));
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

    // ============ Strategy Failure Resilience Tests ============

    /// @notice When one strategy's withdraw reverts, the strategy revert is caught (not propagated),
    ///         but with explicit deposit amounts the function still fails because the vault lacks idle balance.
    ///         This proves the try/catch works: the revert is TransferFromFailed (from deposit), not
    ///         the original "MockYieldSource: paused" error.
    function test_reallocateFunds_SkipsFailingStrategy_RevertsOnDeposit() public {
        // Arrange
        _addStrategy(address(strategy), STRATEGY_CAP);
        _addStrategy(address(strategy2), STRATEGY_CAP);

        _depositAsUser(5000e6);

        uint256 inStrategy1 = vault.getAssetInStrategy(address(strategy));
        assertGt(inStrategy1, 0, "strategy1 should have funds");

        // Make strategy1's yield source revert on withdraw
        yieldSource.setShouldRevertOnWithdraw(true);

        // Reallocate: try to move 2000 from strategy1 to strategy2
        // Strategy1 withdraw is caught by try/catch (skipped), but vault has no idle balance
        // for the deposit into strategy2, so the deposit's transferFrom fails
        DataTypes.Allocation[] memory allocations = new DataTypes.Allocation[](2);
        allocations[0] = DataTypes.Allocation({index: 0, amount: inStrategy1 - 2000e6});
        allocations[1] = DataTypes.Allocation({index: 1, amount: 2000e6});

        // The revert is TransferFromFailed (from deposit), NOT the strategy's own revert
        bytes memory data = abi.encodeCall(BTCVault.reallocateFunds, (allocations));
        _scheduleAndExpectRevertLocal(
            bva_fast, BVA_FAST_ID(), data, abi.encodeWithSelector(bytes4(keccak256("TransferFromFailed()")))
        );
    }

    /// @notice When a failing strategy is skipped and allocations use type(uint256).max, partial reallocation succeeds
    function test_reallocateFunds_PartialReallocationWithMaxSentinel() public {
        // Arrange — set up 3 strategies
        MockYieldSource yieldSource3 = new MockYieldSource();
        MockTokenizedStrategy strategy3 = new MockTokenizedStrategy(address(yieldSource3), address(vault));
        _addStrategy(address(strategy), STRATEGY_CAP);
        _addStrategy(address(strategy2), STRATEGY_CAP);
        _addStrategy(address(strategy3), STRATEGY_CAP);

        _depositAsUser(6000e6);

        uint256 inStrategy1 = vault.getAssetInStrategy(address(strategy));
        assertGt(inStrategy1, 0, "strategy1 should have funds");

        // Break strategy1's withdraw
        yieldSource.setShouldRevertOnWithdraw(true);

        // Since strategy1 fails, totalWithdrawn=0.
        // strategy2 deposit uses max => totalWithdrawn - totalSupplied = 0
        // strategy3 deposit uses max => still 0
        // totalSupplied=0 == totalWithdrawn=0 => passes!
        DataTypes.Allocation[] memory allocations = new DataTypes.Allocation[](3);
        allocations[0] = DataTypes.Allocation({index: 0, amount: 0}); // withdraw all from s1
        allocations[1] = DataTypes.Allocation({index: 1, amount: type(uint256).max}); // deposit remaining
        allocations[2] = DataTypes.Allocation({index: 2, amount: type(uint256).max}); // deposit remaining

        // Act
        _reallocate(allocations);

        // Assert — strategy1 still has its funds (withdraw was skipped)
        uint256 inStrategy1After = vault.getAssetInStrategy(address(strategy));
        assertEq(inStrategy1After, inStrategy1, "strategy1 should be unchanged (withdraw skipped)");
    }

    // ============ Emergency Withdraw Resilience Tests ============

    /// @notice Emergency withdraw should skip failing strategies and continue
    function test_emergencyWithdrawFunds_SkipsFailingStrategy() public {
        // Arrange
        _addStrategy(address(strategy), STRATEGY_CAP);
        _addStrategy(address(strategy2), STRATEGY_CAP);

        _depositAsUser(5000e6);

        uint256 inStrategy1Before = vault.getAssetInStrategy(address(strategy));

        // Reallocate some funds to strategy2
        DataTypes.Allocation[] memory allocations = new DataTypes.Allocation[](2);
        allocations[0] = DataTypes.Allocation({index: 0, amount: inStrategy1Before - 2000e6});
        allocations[1] = DataTypes.Allocation({index: 1, amount: 2000e6});
        _reallocate(allocations);

        uint256 inStrategy2After = vault.getAssetInStrategy(address(strategy2));
        assertEq(inStrategy2After, 2000e6, "strategy2 should have 2000e6");

        // Break strategy1's withdraw
        yieldSource.setShouldRevertOnWithdraw(true);

        // Act — emergency withdraw should still succeed, pulling funds from strategy2
        _scheduleAndExecuteLocal(bvm_fast, BVM_FAST_ID(), abi.encodeCall(BTCVault.emergencyWithdrawFunds, ()));

        // Assert
        // Strategy1 still has its funds (withdraw was skipped)
        uint256 strategy1Final = vault.getAssetInStrategy(address(strategy));
        assertEq(strategy1Final, inStrategy1Before - 2000e6, "strategy1 should be unchanged (withdraw failed)");

        // Strategy2 should be drained
        uint256 strategy2Final = vault.getAssetInStrategy(address(strategy2));
        assertEq(strategy2Final, 0, "strategy2 should be fully drained");
    }

    /// @notice Emergency withdraw emits failure event for broken strategy
    function test_emergencyWithdrawFunds_EmitsFailureEvent() public {
        // Arrange
        _addStrategy(address(strategy), STRATEGY_CAP);
        _depositAsUser(5000e6);

        // Break strategy's withdraw
        yieldSource.setShouldRevertOnWithdraw(true);

        // Assert + Act — expect the failure event
        vm.expectEmit(true, false, false, false, address(vault));
        emit BTCVault__EmergencyWithdrawFailed(0, "");

        _scheduleAndExecuteLocal(bvm_fast, BVM_FAST_ID(), abi.encodeCall(BTCVault.emergencyWithdrawFunds, ()));
    }
}
