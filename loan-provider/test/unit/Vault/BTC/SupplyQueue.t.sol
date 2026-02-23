// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BTCVault} from "@btcVault/BTCVault.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {MockTokenizedStrategy, BaseTestForBTCVault} from "../BaseTestForBTCVault.t.sol";

/// @title SupplyQueueTest__BTCVaultHarness
/// @author Bitmor Protocol
/// @notice Tests for BTCVault supply queue update and validation
/// @dev Verifies queue ordering, length constraints, and revert on exceeding `maxStrategies`
contract SupplyQueueTest__BTCVaultHarness is BaseTestForBTCVault {
    modifier addStrategies() {
        _addStrategies();
        _;
    }

    /**
     * @notice verifies if the supply queue is updated successfully.
     */
    function test_updateSupplyQueue() public addStrategies {
        uint256[] memory newSupplyQueue = new uint256[](5);
        newSupplyQueue[0] = 4;
        newSupplyQueue[1] = 3;
        newSupplyQueue[2] = 1;
        newSupplyQueue[4] = 0;
        newSupplyQueue[3] = 2;

        _scheduleAndExecute(bva_slow, bva_slow_id(), abi.encodeCall(BTCVault.updateSupplyQueue, (newSupplyQueue)));

        uint256[] memory supplyQueue = vault.getSupplyQueue();

        assertEq(supplyQueue, newSupplyQueue);
    }

    function test_RevertWhen_newSupplyQueueLengthIsGreaterThanMaxStrategies() public addStrategies {
        uint256[] memory newSupplyQueue = new uint256[](vault.getMaxStrategies() + 1);
        bytes memory data = abi.encodeCall(BTCVault.updateSupplyQueue, (newSupplyQueue));

        _scheduleAndExpectRevert(
            bva_slow, bva_slow_id(), data, abi.encodeWithSelector(Errors.MaxStrategiesReached.selector)
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
