// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./BaseLoan.t.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {Loan} from "@bitmor/protocol/Loan.sol";

/// @title AdminSettersTest
/// @notice Tests for Loan contract admin setter functions
contract AdminSettersTest is BaseLoanTest {
    address newAddress = makeAddr("newAddress");

    function setUp() public override {
        super.setUp();
    }

    // ============ Address Setters Success ============

    function test_addressSetters_success_tableDriven() public {
        // Only test setters that are assigned to LPM_SLOW role
        // setSwapAdapter and setZQuoter are NOT in LPM_SLOW_SELECTORS
        bytes4[2] memory selectors = [Loan.setLoanVaultFactory.selector, Loan.setPremiumCollector.selector];

        for (uint256 i = 0; i < selectors.length; i++) {
            bytes memory data = abi.encodeWithSelector(selectors[i], newAddress);
            _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);
        }
    }

    // ============ Address Setters Zero Address Reverts ============

    function test_addressSetters_zeroAddress_reverts_tableDriven() public {
        // Only test setters that are assigned to LPM_SLOW role
        bytes4[2] memory selectors = [Loan.setLoanVaultFactory.selector, Loan.setPremiumCollector.selector];

        for (uint256 i = 0; i < selectors.length; i++) {
            bytes memory data = abi.encodeWithSelector(selectors[i], address(0));
            _scheduleAndExpectRevert(
                address(loan),
                lpm_slow,
                LPM_SLOW_ID(),
                data,
                abi.encodeWithSelector(Errors.ZeroAddress.selector)
            );
        }
    }

    // ============ Uint256 Setters Success ============

    function test_uint256Setters_success_tableDriven() public {
        bytes4[8] memory selectors = [
            Loan.setLiquidationBuffer.selector,
            Loan.setGracePeriod.selector,
            Loan.setPreClosureFee.selector,
            Loan.setSlippageForSharesToAsset.selector,
            Loan.setSlippageForSwap.selector,
            Loan.setMaxBTCAmount.selector,
            Loan.setMinBTCAmount.selector,
            Loan.setMinDepositBps.selector
        ];

        uint256 newValue = 100;

        for (uint256 i = 0; i < selectors.length; i++) {
            bytes memory data = abi.encodeWithSelector(selectors[i], newValue);
            _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);
        }
    }

    // ============ Setters Without Role Revert ============

    function test_setters_withoutRole_reverts_tableDriven() public {
        vm.startPrank(user);

        vm.expectRevert();
        loan.setLoanVaultFactory(newAddress);

        vm.expectRevert();
        loan.setMinBTCAmount(100);

        vm.stopPrank();
    }

    // ============ Setters When Paused Revert ============

    function test_setters_whenPaused_reverts_tableDriven() public {
        _pauseContract();

        bytes memory data = abi.encodeCall(loan.setMinBTCAmount, (100));

        // Schedule and execute through AccessManager - expect EnforcedPause error
        (, uint32 delay,,) = manager.getAccess(LPM_SLOW_ID(), lpm_slow);
        uint48 when = uint48(block.timestamp + delay);

        vm.startPrank(lpm_slow);
        if (delay > 0) {
            manager.schedule(address(loan), data, when);
            vm.warp(when);
        }
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        manager.execute(address(loan), data);
        vm.stopPrank();
    }

    // ============ Integration Tests ============

    function test_setMinBTCAmount_affectsLoanCreation() public {
        uint256 originalMin = loan.getMinBTCAmount();
        uint256 newMin = originalMin / 2;

        _setMinBTCAmount(newMin);

        // Smaller collateral should now work
        (uint256 loanAmt,,) = loan.getLoanDetails(newMin, 12);
        assertGt(loanAmt, 0, "Smaller collateral should now be valid");
    }

    function test_setMaxBTCAmount_affectsLoanCreation() public {
        uint256 originalMax = loan.getMaxBTCAmount();
        uint256 newMax = originalMax * 2;

        _setMaxBTCAmount(newMax);

        // Larger collateral should now work
        (uint256 loanAmt,,) = loan.getLoanDetails(originalMax + 1, 12);
        assertGt(loanAmt, 0, "Larger collateral should now be valid");
    }

    function test_setMinDepositBps_affectsLoanCreation() public {
        uint256 newBps = 5000; // 50%

        _setMinDepositBps(newBps);

        assertEq(loan.getMinDepositBps(), newBps, "Min deposit BPS should be updated");
    }
}
