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
}
