// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BTCVault} from "@btcVault/BTCVault.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {MockTokenizedStrategy, BaseTestForBTCVault} from "../BaseTestForBTCVault.t.sol";

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

    function _addStrategies() public {
        for (uint256 i = 0; i < 5; i++) {
            MockTokenizedStrategy newStrategy = new MockTokenizedStrategy(address(yieldSource), address(vault));

            _scheduleAndExecute(
                bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(newStrategy), STANDARD_STRATEGY_CAP))
            );
        }
    }
}
