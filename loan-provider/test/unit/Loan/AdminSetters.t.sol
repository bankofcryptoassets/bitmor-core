// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./BaseLoan.t.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {Loan} from "@bitmor/protocol/Loan.sol";
import {IAccessManaged} from "@openzeppelin/access/manager/IAccessManaged.sol";

/// @title AdminSettersTest
/// @notice Tests for Loan contract admin setter functions
contract AdminSettersTest is BaseLoanTest {
    address newAddress = makeAddr("newAddress");

    function setUp() public override {
        super.setUp();
    }

    // ============ Address Setters Success ============

    function test_setLoanVaultFactory_success() public {
        address originalFactory = loan.s_loanVaultFactory();

        bytes memory data = abi.encodeWithSelector(Loan.setLoanVaultFactory.selector, newAddress);
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);

        assertEq(loan.s_loanVaultFactory(), newAddress, "LoanVaultFactory should be updated");
        assertTrue(loan.s_loanVaultFactory() != originalFactory, "Should differ from original");
    }

    function test_setPremiumCollector_success() public {
        address originalCollector = loan.getPremiumCollector();

        bytes memory data = abi.encodeWithSelector(Loan.setPremiumCollector.selector, newAddress);
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);

        assertEq(loan.getPremiumCollector(), newAddress, "PremiumCollector should be updated");
        assertTrue(loan.getPremiumCollector() != originalCollector, "Should differ from original");
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

    function test_setLiquidationBuffer_success() public {
        uint256 newValue = 200;
        bytes memory data = abi.encodeWithSelector(Loan.setLiquidationBuffer.selector, newValue);
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);

        assertEq(loan.getLiquidationBuffer(), newValue, "LiquidationBuffer should be updated");
    }

    function test_setGracePeriod_success() public {
        uint256 newValue = 7 days;
        bytes memory data = abi.encodeWithSelector(Loan.setGracePeriod.selector, newValue);
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);

        assertEq(loan.getGracePeriod(), newValue, "GracePeriod should be updated");
    }

    function test_setPreClosureFee_success() public {
        uint256 newValue = 500; // 5% in bps
        bytes memory data = abi.encodeWithSelector(Loan.setPreClosureFee.selector, newValue);
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);

        assertEq(loan.getPreClosureFee(), newValue, "PreClosureFee should be updated");
    }

    function test_setSlippageForSharesToAsset_success() public {
        uint256 newValue = 100; // 1%
        bytes memory data = abi.encodeWithSelector(Loan.setSlippageForSharesToAsset.selector, newValue);
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);

        assertEq(loan.getSlippageForSharesToAsset(), newValue, "SlippageForSharesToAsset should be updated");
    }

    function test_setSlippageForSwap_success() public {
        uint256 newValue = 75;
        bytes memory data = abi.encodeWithSelector(Loan.setSlippageForSwap.selector, newValue);
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);

        assertEq(loan.getSlippageForSwap(), newValue, "SlippageForSwap should be updated");
    }

    function test_setMaxBTCAmount_success() public {
        uint256 newValue = 5e8; // 5 BTC
        bytes memory data = abi.encodeWithSelector(Loan.setMaxBTCAmount.selector, newValue);
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);

        assertEq(loan.getMaxBTCAmount(), newValue, "MaxBTCAmount should be updated");
    }

    function test_setMinBTCAmount_success() public {
        uint256 newValue = 0.005e8; // 0.005 BTC
        bytes memory data = abi.encodeWithSelector(Loan.setMinBTCAmount.selector, newValue);
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);

        assertEq(loan.getMinBTCAmount(), newValue, "MinBTCAmount should be updated");
    }

    function test_setMinDepositBps_success() public {
        uint256 newValue = 5000; // 50%
        bytes memory data = abi.encodeWithSelector(Loan.setMinDepositBps.selector, newValue);
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);

        assertEq(loan.getMinDepositBps(), newValue, "MinDepositBps should be updated");
    }

    // ============ Setters Without Role Revert ============

    function test_setters_withoutRole_reverts_tableDriven() public {
        vm.startPrank(user);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, user));
        loan.setLoanVaultFactory(newAddress);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, user));
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
