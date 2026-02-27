// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseLoanTest} from "./Loan/BaseLoan.t.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {IAccessManaged} from "@openzeppelin/access/manager/IAccessManaged.sol";
import {Loan} from "@bitmor/protocol/Loan.sol";
import {BitmorAddressesProvider} from "@bitmor/protocol/BitmorAddressesProvider.sol";

/// @title AccessControlsTest
/// @author Bitmor Protocol
/// @notice Test suite for verifying AccessManaged role-based access control mechanisms
/// @dev Focuses on: unauthorized access reverts, role assignments, and cross-cutting access control.
///      For comprehensive testing of individual setter functions (values, bounds, events),
///      see `AdminSetters.t.sol` which provides dedicated setter coverage.
contract AccessControlsTest is BaseLoanTest {
    address internal attacker;

    address internal constant NEW_FACTORY = address(0xF4C70);
    address internal constant NEW_SWAP_ADAPTER = address(0x5A4);
    address internal constant NEW_PREMIUM_COLLECTOR = address(0xC011EC7);
    uint256 internal constant NEW_LIQUIDATION_BUFFER = 500;
    uint256 internal constant NEW_GRACE_PERIOD = 7 days;
    uint256 internal constant NEW_PRE_CLOSURE_FEE = 200;

    function setUp() public override {
        super.setUp();
        attacker = makeAddr("attacker");
    }

    /// @notice Unauthorized caller cannot call admin setter functions (expects AccessManagedUnauthorized)
    function test_unauthorized_adminSetters_revert() public {
        vm.startPrank(attacker);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, attacker));
        loan.setBitmorAddressesProvider(NEW_FACTORY);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, attacker));
        loan.setGracePeriod(NEW_GRACE_PERIOD);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, attacker));
        loan.setPreClosureFee(NEW_PRE_CLOSURE_FEE);

        vm.stopPrank();
    }

    /// @notice LPM_SLOW role can call admin setters and updates are persisted
    function test_lpmSlow_adminSetters_updateState() public {
        // Deploy a new BitmorAddressesProvider to use as replacement
        vm.startPrank(admin);
        BitmorAddressesProvider newProvider = new BitmorAddressesProvider(address(manager), address(loan));
        newProvider.setVaultFactory(NEW_FACTORY);
        newProvider.setSwapper(NEW_SWAP_ADAPTER);
        newProvider.setPremiumCollector(NEW_PREMIUM_COLLECTOR);
        vm.stopPrank();

        // Use _scheduleAndExecute with lpm_slow role
        _scheduleAndExecute(
            address(loan),
            lpm_slow,
            LPM_SLOW_ID(),
            abi.encodeCall(Loan.setBitmorAddressesProvider, (address(newProvider)))
        );
        _scheduleAndExecute(
            address(loan), lpm_slow, LPM_SLOW_ID(), abi.encodeCall(Loan.setGracePeriod, (NEW_GRACE_PERIOD))
        );
        _scheduleAndExecute(
            address(loan), lpm_slow, LPM_SLOW_ID(), abi.encodeCall(Loan.setPreClosureFee, (NEW_PRE_CLOSURE_FEE))
        );

        assertEq(loan.getBitmorAddressesProvider(), address(newProvider));
        assertEq(newProvider.getLoanVaultFactory(), NEW_FACTORY);
        assertEq(newProvider.getSwapper(), NEW_SWAP_ADAPTER);
        assertEq(newProvider.getPremiumCollector(), NEW_PREMIUM_COLLECTOR);
        assertEq(loan.getGracePeriod(), NEW_GRACE_PERIOD);
        assertEq(loan.getPreClosureFee(), NEW_PRE_CLOSURE_FEE);
    }

    /// @notice LPM_SLOW address setters revert on the zero address
    function test_lpmSlow_addressSetters_revertOnZeroAddress() public {
        _scheduleAndExpectRevert(
            address(loan),
            lpm_slow,
            LPM_SLOW_ID(),
            abi.encodeCall(Loan.setBitmorAddressesProvider, (address(0))),
            abi.encodeWithSelector(Errors.ZeroAddress.selector)
        );
    }

    /// @notice Unauthorized callers cannot update loan data for micro liquidation.
    function test_protocolMutators_updateLoanDataForMicroLiquidation_revertForUnauthorized() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, attacker));
        loan.updateLoanDataForMicroLiquidation(lsa);
    }

    /// @notice Unauthorized callers cannot update stored loan data.
    function test_protocolMutators_updateLoanData_revertForUnauthorized() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, attacker));
        loan.updateLoanDataForFullLiquidation(lsa);
    }

    /// @notice Flash-loan callback reverts when caller is not the Aave pool.
    function test_flashLoanCallback_revertsForNonPoolCaller() public {
        bytes memory flData = abi.encode(address(0x1234), uint256(1e8));
        bytes memory params = abi.encode(true, flData);

        vm.prank(attacker);
        vm.expectRevert(Errors.CallerIsNotAAVEPool.selector);
        loan.executeOperation(debtAsset, 1000e6, 10e6, address(loan), params);
    }
}
