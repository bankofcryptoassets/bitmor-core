// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IAccessManaged} from "@openzeppelin/access/manager/IAccessManaged.sol";
import {ERC20} from "@solady/tokens/ERC20.sol";

import {BTCVault} from "@btcVault/BTCVault.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {MockTokenizedStrategy, BaseTestForBTCVault} from "../BaseTestForBTCVault.t.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";

/**
 * @title AccessManager Test Suite for BTCVault
 * @author Bitmor Protocol
 * @notice Tests restricted access enforced by AccessManager roles
 * @dev Validates that each BTCVault function is correctly gated by its corresponding role (BVM_SLOW, BVM_FAST, BVC, BVA_SLOW, BVA_FAST, BVD)
 */
contract AccessControl__BTCVaultHarness is BaseTestForBTCVault {
    address unauthorized;
    MockTokenizedStrategy strategy2;

    function setUp() public override {
        super.setUp();
        unauthorized = makeAddr("UNAUTHORIZED");
        strategy2 = new MockTokenizedStrategy(address(yieldSource), address(vault));
    }

    function test_SetEntryFee_AsBvmSlow() public {
        uint256 newFee = 100;

        _scheduleAndExecute(bvm_slow, bvm_slow_id(), abi.encodeCall(BTCVault.setEntryFee, (newFee)));

        assertEq(vault.getEntryFee(), newFee);
    }

    function test_RevertWhen_SetEntryFee_AsUnauthorized() public {
        uint256 newFee = 100;

        vm.prank(unauthorized);
        _expectUnauthorized(unauthorized);
        vault.setEntryFee(newFee);
    }

    function test_SetExitFee_AsBvmSlow() public {
        uint256 newFee = 200;

        _scheduleAndExecute(bvm_slow, bvm_slow_id(), abi.encodeCall(BTCVault.setExitFee, (newFee)));

        assertEq(vault.getExitFee(), newFee);
    }

    function test_RevertWhen_SetExitFee_AsUnauthorized() public {
        uint256 newFee = 200;

        vm.prank(unauthorized);
        _expectUnauthorized(unauthorized);
        vault.setExitFee(newFee);
    }

    function test_SetFeeRecipient_AsBvmSlow() public {
        address newRecipient = makeAddr("NEW_RECIPIENT");

        _scheduleAndExecute(bvm_slow, bvm_slow_id(), abi.encodeCall(BTCVault.setFeeRecipient, (newRecipient)));

        assertEq(vault.getFeeRecipient(), newRecipient);
    }

    function test_RevertWhen_SetFeeRecipient_AsUnauthorized() public {
        address newRecipient = makeAddr("NEW_RECIPIENT");

        vm.prank(unauthorized);
        _expectUnauthorized(unauthorized);
        vault.setFeeRecipient(newRecipient);
    }

    function test_RevertWhen_SetFeeRecipient_ZeroAddress() public {
        bytes memory data = abi.encodeCall(BTCVault.setFeeRecipient, (address(0)));
        uint48 when = _scheduleOperation(bvm_slow, bvm_slow_id(), data);

        vm.warp(when);
        vm.prank(bvm_slow);
        vm.expectRevert(Errors.ZeroAddress.selector);
        manager.execute(address(vault), data);
    }

    function test_SetMaxStrategies_AsBvmSlow() public {
        uint256 newMax = 12;

        _scheduleAndExecute(bvm_slow, bvm_slow_id(), abi.encodeCall(BTCVault.setMaxStrategies, (newMax)));

        assertEq(vault.getMaxStrategies(), newMax);
    }

    function test_RevertWhen_SetMaxStrategies_AsUnauthorized() public {
        vm.prank(unauthorized);
        _expectUnauthorized(unauthorized);
        vault.setMaxStrategies(12);
    }

    function test_Pause_AsBvmFast() public {
        vm.prank(bvm_fast);
        vault.pause();

        assertTrue(vault.paused());
    }

    function test_RevertWhen_Pause_AsUnauthorized() public {
        vm.prank(unauthorized);
        _expectUnauthorized(unauthorized);
        vault.pause();
    }

    function test_Unpause_AsBvmSlow() public {
        vm.prank(bvm_fast);
        vault.pause();

        _scheduleAndExecute(bvm_slow, bvm_slow_id(), abi.encodeCall(BTCVault.unpause, ()));

        assertFalse(vault.paused());
    }

    function test_RevertWhen_Unpause_AsUnauthorized() public {
        vm.prank(bvm_fast);
        vault.pause();

        vm.prank(unauthorized);
        _expectUnauthorized(unauthorized);
        vault.unpause();
    }

    function test_AddStrategy_AsBvc() public {
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strategy), STANDARD_STRATEGY_CAP))
        );

        assertEq(vault.getNextStrategyIndex(), 1);
    }

    function test_RevertWhen_AddStrategy_AsUnauthorized() public {
        vm.prank(unauthorized);
        _expectUnauthorized(unauthorized);
        vault.addStrategy(address(strategy), STANDARD_STRATEGY_CAP);
    }

    function test_ChangeStrategyCap_AsBvc() public {
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strategy), STANDARD_STRATEGY_CAP))
        );

        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.changeStrategyCap, (address(strategy), LARGE_STRATEGY_CAP))
        );

        assertEq(vault.getStrategyDetails(0).cap, LARGE_STRATEGY_CAP);
    }

    function test_RevertWhen_ChangeStrategyCap_AsUnauthorized() public {
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strategy), STANDARD_STRATEGY_CAP))
        );

        vm.prank(unauthorized);
        _expectUnauthorized(unauthorized);
        vault.changeStrategyCap(address(strategy), LARGE_STRATEGY_CAP);
    }

    function test_UpdateSupplyQueue_AsBvaSlow() public {
        _addStrategies();

        uint256[] memory supplyQueue = new uint256[](2);
        supplyQueue[0] = 0;
        supplyQueue[1] = 1;

        _scheduleAndExecute(bva_slow, bva_slow_id(), abi.encodeCall(BTCVault.updateSupplyQueue, (supplyQueue)));

        assertEq(vault.getSupplyQueueLength(), 2);
    }

    function test_RevertWhen_UpdateSupplyQueue_AsUnauthorized() public {
        _addStrategies();

        uint256[] memory supplyQueue = new uint256[](2);
        supplyQueue[0] = 0;
        supplyQueue[1] = 1;

        vm.prank(unauthorized);
        _expectUnauthorized(unauthorized);
        vault.updateSupplyQueue(supplyQueue);
    }

    function test_UpdateWithdrawQueue_AsBvaSlow() public {
        _addStrategies();

        uint256[] memory withdrawQueue = new uint256[](2);
        withdrawQueue[0] = 0;
        withdrawQueue[1] = 1;

        _scheduleAndExecute(bva_slow, bva_slow_id(), abi.encodeCall(BTCVault.updateWithdrawQueue, (withdrawQueue)));

        assertEq(vault.getWithdrawQueueLength(), 2);
    }

    function test_RevertWhen_UpdateWithdrawQueue_AsUnauthorized() public {
        _addStrategies();

        uint256[] memory withdrawQueue = new uint256[](2);
        withdrawQueue[0] = 0;
        withdrawQueue[1] = 1;

        vm.prank(unauthorized);
        _expectUnauthorized(unauthorized);
        vault.updateWithdrawQueue(withdrawQueue);
    }

    function test_ReallocateFunds_AsBvaFast() public {
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strategy), STANDARD_STRATEGY_CAP))
        );

        _depositAsUser(DEPOSIT_AMOUNT);

        DataTypes.Allocation[] memory newAllocations = new DataTypes.Allocation[](0);

        vm.prank(bva_fast);
        vault.reallocateFunds(newAllocations);

        assertTrue(vault.getAssetInStrategy(address(strategy)) > 0);
    }

    function test_RevertWhen_ReallocateFunds_AsUnauthorized() public {
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strategy), STANDARD_STRATEGY_CAP))
        );

        _depositAsUser(DEPOSIT_AMOUNT);

        DataTypes.Allocation[] memory newAllocations = new DataTypes.Allocation[](0);

        vm.prank(unauthorized);
        _expectUnauthorized(unauthorized);
        vault.reallocateFunds(newAllocations);
    }

    function test_Deposit_AsUserRole() public {
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strategy), STANDARD_STRATEGY_CAP))
        );

        _depositAsUser(DEPOSIT_AMOUNT);

        assertTrue(vault.balanceOf(user) > 0);
    }

    function test_RevertWhen_Deposit_AsUnauthorized() public {
        vm.prank(unauthorized);
        _expectUnauthorized(unauthorized);
        vault.deposit(DEPOSIT_AMOUNT, unauthorized);
    }

    /// @notice Helper to add two strategies (`strategy` and `strategy2`) with standard caps
    function _addStrategies() internal {
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strategy), STANDARD_STRATEGY_CAP))
        );
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strategy2), STANDARD_STRATEGY_CAP))
        );
    }

    /// @notice Helper to approve and deposit as `user`
    /// @param depositAmount Amount of USDC to deposit
    function _depositAsUser(uint256 depositAmount) internal {
        vm.startPrank(user);
        ERC20(networkConfig.usdc).approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();
    }

    /// @notice Expects the next call to revert with `AccessManagedUnauthorized` for `caller`
    /// @param caller The unauthorized address expected in the revert
    function _expectUnauthorized(address caller) internal {
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
    }

    /// @notice Schedules a delayed operation via AccessManager without executing it
    /// @param caller The address scheduling the operation
    /// @param roleId The role ID used to determine the execution delay
    /// @param data The encoded function call data
    /// @return when The timestamp at which the operation can be executed
    function _scheduleOperation(address caller, uint64 roleId, bytes memory data) internal returns (uint48 when) {
        (, uint32 delay,,) = manager.getAccess(roleId, caller);
        when = uint48(block.timestamp + delay);

        vm.prank(caller);
        manager.schedule(address(vault), data, when);
    }
}
