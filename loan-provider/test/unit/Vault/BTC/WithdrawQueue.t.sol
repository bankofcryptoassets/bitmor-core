// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {ERC20} from "@solady/tokens/ERC20.sol";

import {BTCVault} from "@btcVault/BTCVault.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {MockTokenizedStrategy, BaseTestForBTCVault} from "../BaseTestForBTCVault.t.sol";

/// @title WithdrawQueue
/// @author Bitmor Protocol
/// @notice Tests for BTCVault withdraw queue update, validation, and approval revocation
/// @dev Verifies queue reordering, revert conditions, and that strategy token approvals
///      are properly revoked when strategies are removed from the withdraw queue
contract WithdrawQueue is BaseTestForBTCVault {
    modifier addStrategies() {
        _addStrategies();
        _;
    }

    function test_updateWithdrawQueue() public addStrategies {
        uint256[] memory newWithdrawQueue = new uint256[](5);
        newWithdrawQueue[0] = 3;
        newWithdrawQueue[1] = 2;
        newWithdrawQueue[2] = 1;
        newWithdrawQueue[3] = 4;
        newWithdrawQueue[4] = 0;

        _scheduleAndExecute(bva_slow, bva_slow_id(), abi.encodeCall(BTCVault.updateWithdrawQueue, (newWithdrawQueue)));

        uint256[] memory withdrawQueue = vault.getWithdrawQueue();

        assertEq(withdrawQueue, newWithdrawQueue);
    }

    function test_RevertWhen_newWithdrawLengthIsGreaterThanTotalStrategies() public addStrategies {
        uint256[] memory newWithdrawQueue = new uint256[](vault.getTotalStrategies() + 1);
        bytes memory data = abi.encodeCall(BTCVault.updateWithdrawQueue, (newWithdrawQueue));

        _scheduleAndExpectRevert(bva_slow, bva_slow_id(), data, abi.encodeWithSelector(Errors.WrongLength.selector));
    }

    /// @notice Verifies that removing a strategy via updateWithdrawQueue revokes its token approval
    function test_updateWithdrawQueue_RevokesApprovalOnRemoval() public {
        // Arrange — add a single strategy
        MockTokenizedStrategy removableStrategy = new MockTokenizedStrategy(address(yieldSource), address(vault));
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(removableStrategy), STANDARD_STRATEGY_CAP))
        );

        // Verify approval was granted
        uint256 approvalBefore = ERC20(vault.asset()).allowance(address(vault), address(removableStrategy));
        assertEq(approvalBefore, type(uint256).max, "approval should be max after addStrategy");

        // Set cap to 0 (required before removal)
        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.changeStrategyCap, (address(removableStrategy), 0)));

        // Act — remove strategy by passing empty withdraw queue
        uint256[] memory emptyQueue = new uint256[](0);
        _scheduleAndExecute(bva_slow, bva_slow_id(), abi.encodeCall(BTCVault.updateWithdrawQueue, (emptyQueue)));

        // Assert — approval must be revoked
        uint256 approvalAfter = ERC20(vault.asset()).allowance(address(vault), address(removableStrategy));
        assertEq(approvalAfter, 0, "approval should be 0 after strategy removal");
    }

    /// @notice Verifies that strategies remaining in the queue retain their approval
    function test_updateWithdrawQueue_RetainedStrategiesKeepApproval() public {
        // Arrange — add two strategies
        MockTokenizedStrategy strategyA = new MockTokenizedStrategy(address(yieldSource), address(vault));
        MockTokenizedStrategy strategyB = new MockTokenizedStrategy(address(yieldSource), address(vault));

        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strategyA), STANDARD_STRATEGY_CAP))
        );
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strategyB), STANDARD_STRATEGY_CAP))
        );

        // Set cap to 0 for strategyB (index 1 in withdraw queue)
        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.changeStrategyCap, (address(strategyB), 0)));

        // Act — keep only strategyA (index 0 in current withdraw queue)
        uint256[] memory keepFirst = new uint256[](1);
        keepFirst[0] = 0;
        _scheduleAndExecute(bva_slow, bva_slow_id(), abi.encodeCall(BTCVault.updateWithdrawQueue, (keepFirst)));

        // Assert — strategyA still has max approval
        uint256 approvalA = ERC20(vault.asset()).allowance(address(vault), address(strategyA));
        assertEq(approvalA, type(uint256).max, "retained strategy should keep max approval");

        // Assert — strategyB has zero approval
        uint256 approvalB = ERC20(vault.asset()).allowance(address(vault), address(strategyB));
        assertEq(approvalB, 0, "removed strategy should have zero approval");
    }

    /// @notice Verifies that removing multiple strategies revokes all their approvals
    function test_updateWithdrawQueue_MultipleRemovalsRevokeAllApprovals() public {
        // Arrange — add three strategies
        MockTokenizedStrategy strategyA = new MockTokenizedStrategy(address(yieldSource), address(vault));
        MockTokenizedStrategy strategyB = new MockTokenizedStrategy(address(yieldSource), address(vault));
        MockTokenizedStrategy strategyC = new MockTokenizedStrategy(address(yieldSource), address(vault));

        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strategyA), STANDARD_STRATEGY_CAP))
        );
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strategyB), STANDARD_STRATEGY_CAP))
        );
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strategyC), STANDARD_STRATEGY_CAP))
        );

        // Set caps to 0 for all three
        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.changeStrategyCap, (address(strategyA), 0)));
        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.changeStrategyCap, (address(strategyB), 0)));
        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.changeStrategyCap, (address(strategyC), 0)));

        // Act — remove all strategies
        uint256[] memory emptyQueue = new uint256[](0);
        _scheduleAndExecute(bva_slow, bva_slow_id(), abi.encodeCall(BTCVault.updateWithdrawQueue, (emptyQueue)));

        // Assert — all approvals revoked
        assertEq(
            ERC20(vault.asset()).allowance(address(vault), address(strategyA)), 0, "strategyA approval should be 0"
        );
        assertEq(
            ERC20(vault.asset()).allowance(address(vault), address(strategyB)), 0, "strategyB approval should be 0"
        );
        assertEq(
            ERC20(vault.asset()).allowance(address(vault), address(strategyC)), 0, "strategyC approval should be 0"
        );
    }

    /// @notice Deploys and adds 5 strategies with `STANDARD_STRATEGY_CAP` to the vault
    function _addStrategies() public {
        for (uint256 i = 0; i < 5; i++) {
            MockTokenizedStrategy newStrategy = new MockTokenizedStrategy(address(yieldSource), address(vault));

            _scheduleAndExecute(
                bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(newStrategy), STANDARD_STRATEGY_CAP))
            );
        }
    }
}
