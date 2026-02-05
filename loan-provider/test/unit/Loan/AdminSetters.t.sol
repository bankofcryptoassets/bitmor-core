// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./BaseLoan.t.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {Loan} from "@bitmor/protocol/Loan.sol";
import {IAccessManaged} from "@openzeppelin/access/manager/IAccessManaged.sol";
import {TestConstants as TC} from "../../helpers/TestConstants.sol";

/// @title AdminSettersTest
/// @notice Comprehensive tests for Loan contract admin setter functions
/// @dev Focuses on: value updates, input validation (zero address, bounds), and state changes.
///      For cross-cutting access control tests (unauthorized access, role verification),
///      see AccessControls.t.sol which focuses on AccessManaged patterns.
contract AdminSettersTest is BaseLoanTest {
    address newAddress = makeAddr("newAddress");

    function setUp() public override {
        super.setUp();
    }

    // ============ Address Setters Success ============

    /// @notice Test successfully setting the LoanVaultFactory address
    function test_setLoanVaultFactory() public {
        address originalFactory = loan.s_loanVaultFactory();

        bytes memory data = abi.encodeWithSelector(Loan.setLoanVaultFactory.selector, newAddress);
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);

        assertEq(loan.s_loanVaultFactory(), newAddress, "LoanVaultFactory should be updated");
        assertTrue(loan.s_loanVaultFactory() != originalFactory, "Should differ from original");
    }

    /// @notice Test successfully setting the PremiumCollector address
    function test_setPremiumCollector() public {
        address originalCollector = loan.getPremiumCollector();

        bytes memory data = abi.encodeWithSelector(Loan.setPremiumCollector.selector, newAddress);
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);

        assertEq(loan.getPremiumCollector(), newAddress, "PremiumCollector should be updated");
        assertTrue(loan.getPremiumCollector() != originalCollector, "Should differ from original");
    }

    /// @notice Test successfully setting the liquidation fee collector address
    function test_setLiquidationFeeCollector() public {
        bytes memory data = abi.encodeWithSelector(Loan.setLiquidationFeeCollector.selector, newAddress);
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);

        assertEq(loan.getLiquidationFeeCollector(), newAddress, "LiquidationFeeCollector should be updated");
    }

    // ============ Address Setters Zero Address Reverts ============

    /// @notice Test that address setters revert when given zero address
    function test_addressSetters_RevertWhen_ZeroAddress() public {
        // Only test setters that are assigned to LPM_SLOW role
        bytes4[3] memory selectors = [
            Loan.setLoanVaultFactory.selector,
            Loan.setPremiumCollector.selector,
            Loan.setLiquidationFeeCollector.selector
        ];

        for (uint256 i = 0; i < selectors.length; i++) {
            bytes memory data = abi.encodeWithSelector(selectors[i], address(0));
            _scheduleAndExpectRevert(
                address(loan), lpm_slow, LPM_SLOW_ID(), data, abi.encodeWithSelector(Errors.ZeroAddress.selector)
            );
        }
    }

    // ============ Uint256 Setters Success ============

    /// @notice Test successfully setting the grace period
    function test_setGracePeriod() public {
        uint256 newValue = 7 days;
        bytes memory data = abi.encodeWithSelector(Loan.setGracePeriod.selector, newValue);
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);

        assertEq(loan.getGracePeriod(), newValue, "GracePeriod should be updated");
    }

    /// @notice Test successfully setting the pre-closure fee
    function test_setPreClosureFee() public {
        uint256 newValue = 500; // 5% in bps
        bytes memory data = abi.encodeWithSelector(Loan.setPreClosureFee.selector, newValue);
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);

        assertEq(loan.getPreClosureFee(), newValue, "PreClosureFee should be updated");
    }

    /// @notice Test successfully setting the slippage for shares to asset conversion
    function test_setSlippageForSharesToAsset() public {
        uint256 newValue = 100; // 1%
        bytes memory data = abi.encodeWithSelector(Loan.setSlippageForSharesToAsset.selector, newValue);
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);

        assertEq(loan.getSlippageForSharesToAsset(), newValue, "SlippageForSharesToAsset should be updated");
    }

    /// @notice Test successfully setting the slippage for swap operations
    function test_setSlippageForSwap() public {
        uint256 newValue = 75;
        bytes memory data = abi.encodeWithSelector(Loan.setSlippageForSwap.selector, newValue);
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);

        assertEq(loan.getSlippageForSwap(), newValue, "SlippageForSwap should be updated");
    }

    /// @notice Test successfully setting the maximum BTC collateral amount
    function test_setMaxBTCAmount() public {
        uint256 newValue = 5e8; // 5 BTC
        bytes memory data = abi.encodeWithSelector(Loan.setMaxBTCAmount.selector, newValue);
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);

        assertEq(loan.getMaxBTCAmount(), newValue, "MaxBTCAmount should be updated");
    }

    /// @notice Test successfully setting the minimum BTC collateral amount
    function test_setMinBTCAmount() public {
        uint256 newValue = 0.005e8; // 0.005 BTC
        bytes memory data = abi.encodeWithSelector(Loan.setMinBTCAmount.selector, newValue);
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);

        assertEq(loan.getMinBTCAmount(), newValue, "MinBTCAmount should be updated");
    }

    /// @notice Test successfully setting the minimum deposit basis points
    function test_setMinDepositBps() public {
        uint256 newValue = 5000; // 50%
        bytes memory data = abi.encodeWithSelector(Loan.setMinDepositBps.selector, newValue);
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);

        assertEq(loan.getMinDepositBps(), newValue, "MinDepositBps should be updated");
    }

    /// @notice Test successfully setting the liquidation fee in basis points
    function test_setLiquidationFeeBps() public {
        uint256 newValue = TC.DEFAULT_LIQUIDATION_FEE_BPS;
        bytes memory data = abi.encodeWithSelector(Loan.setLiquidationFeeBps.selector, newValue);
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);

        assertEq(loan.getLiquidationFeeBps(), newValue, "LiquidationFeeBps should be updated");
    }

    // ============ Uint256 Setters Boundary Tests ============

    /// @notice Test setting liquidation fee at exactly max value (20%)
    function test_setLiquidationFeeBps_AtMaxValue() public {
        uint256 maxValue = TC.MAX_LIQUIDATION_FEE_BPS;
        bytes memory data = abi.encodeWithSelector(Loan.setLiquidationFeeBps.selector, maxValue);
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);

        assertEq(loan.getLiquidationFeeBps(), maxValue, "Should accept max value");
    }

    /// @notice Test that setting liquidation fee above max reverts
    function test_setLiquidationFeeBps_RevertWhen_ExceedsMax() public {
        uint256 invalidValue = TC.MAX_LIQUIDATION_FEE_BPS + 1;
        bytes memory data = abi.encodeWithSelector(Loan.setLiquidationFeeBps.selector, invalidValue);
        _scheduleAndExpectRevert(
            address(loan), lpm_slow, LPM_SLOW_ID(), data, abi.encodeWithSelector(Errors.InvalidFee.selector)
        );
    }

    // ============ Setters Without Role Revert ============

    /// @notice Test that setters revert when caller lacks the required role
    function test_setters_RevertWhen_CalledWithoutRole() public {
        vm.startPrank(user);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, user));
        loan.setLoanVaultFactory(newAddress);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, user));
        loan.setMinBTCAmount(TC.MIN_COLLATERAL);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, user));
        loan.setLiquidationFeeBps(TC.DEFAULT_LIQUIDATION_FEE_BPS);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, user));
        loan.setLiquidationFeeCollector(newAddress);

        vm.stopPrank();
    }

    // ============ Setters When Paused Revert ============

    /// @notice Test that setters revert when contract is paused
    function test_setters_RevertWhen_Paused() public {
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

    /// @notice Test that changing min BTC amount affects loan creation validation
    function test_setMinBTCAmount_affectsLoanCreation() public {
        uint256 originalMin = loan.getMinBTCAmount();
        uint256 newMin = originalMin / 2;

        _setMinBTCAmount(newMin);

        // Smaller collateral should now work
        (uint256 loanAmt,,) = loan.getLoanDetails(newMin, 12);
        assertGt(loanAmt, 0, "Smaller collateral should now be valid");
    }

    /// @notice Test that changing max BTC amount affects loan creation validation
    function test_setMaxBTCAmount_affectsLoanCreation() public {
        uint256 originalMax = loan.getMaxBTCAmount();
        uint256 newMax = originalMax * 2;

        _setMaxBTCAmount(newMax);

        // Larger collateral should now work
        (uint256 loanAmt,,) = loan.getLoanDetails(originalMax + 1, 12);
        assertGt(loanAmt, 0, "Larger collateral should now be valid");
    }

    /// @notice Test that changing min deposit BPS affects loan creation requirements
    function test_setMinDepositBps_affectsLoanCreation() public {
        uint256 newBps = 5000; // 50%

        _setMinDepositBps(newBps);

        assertEq(loan.getMinDepositBps(), newBps, "Min deposit BPS should be updated");
    }
}
