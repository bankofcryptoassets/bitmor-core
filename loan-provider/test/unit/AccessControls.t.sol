// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./Loan/BaseLoan.t.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {IAccessManaged} from "@openzeppelin/access/manager/IAccessManaged.sol";
import {Loan} from "@bitmor/protocol/Loan.sol";

/// @title AccessControlsTest
/// @notice Test suite for verifying access control mechanisms in the Bitmor Protocol
/// @dev Updated to use AccessManaged pattern instead of Ownable
contract AccessControlsTest is BaseLoanTest {
    address internal attacker;

    address internal constant NEW_FACTORY = address(0xF4C70);
    address internal constant NEW_SWAP_ADAPTER = address(0x5A4);
    address internal constant NEW_ZQUOTER = address(0x20073);
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
        loan.setLoanVaultFactory(NEW_FACTORY);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, attacker));
        loan.setSwapAdapter(NEW_SWAP_ADAPTER);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, attacker));
        loan.setZQuoter(NEW_ZQUOTER);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, attacker));
        loan.setLiquidationBuffer(NEW_LIQUIDATION_BUFFER);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, attacker));
        loan.setPremiumCollector(NEW_PREMIUM_COLLECTOR);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, attacker));
        loan.setGracePeriod(NEW_GRACE_PERIOD);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, attacker));
        loan.setPreClosureFee(NEW_PRE_CLOSURE_FEE);

        vm.stopPrank();
    }

    /// @notice LPM_SLOW role can call admin setters and updates are persisted
    function test_lpmSlow_adminSetters_updateState() public {
        // Use _scheduleAndExecute with lpm_slow role for each setter
        _scheduleAndExecute(
            address(loan), lpm_slow, LPM_SLOW_ID(), abi.encodeCall(Loan.setLoanVaultFactory, (NEW_FACTORY))
        );
        _scheduleAndExecute(
            address(loan), lpm_slow, LPM_SLOW_ID(), abi.encodeCall(Loan.setSwapAdapter, (NEW_SWAP_ADAPTER))
        );
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), abi.encodeCall(Loan.setZQuoter, (NEW_ZQUOTER)));
        _scheduleAndExecute(
            address(loan), lpm_slow, LPM_SLOW_ID(), abi.encodeCall(Loan.setLiquidationBuffer, (NEW_LIQUIDATION_BUFFER))
        );
        _scheduleAndExecute(
            address(loan), lpm_slow, LPM_SLOW_ID(), abi.encodeCall(Loan.setPremiumCollector, (NEW_PREMIUM_COLLECTOR))
        );
        _scheduleAndExecute(
            address(loan), lpm_slow, LPM_SLOW_ID(), abi.encodeCall(Loan.setGracePeriod, (NEW_GRACE_PERIOD))
        );
        _scheduleAndExecute(
            address(loan), lpm_slow, LPM_SLOW_ID(), abi.encodeCall(Loan.setPreClosureFee, (NEW_PRE_CLOSURE_FEE))
        );

        assertEq(loan.s_loanVaultFactory(), NEW_FACTORY);
        assertEq(loan.s_swapAdapter(), NEW_SWAP_ADAPTER);
        assertEq(loan.s_zQuoter(), NEW_ZQUOTER);
        assertEq(loan.getLiquidationBuffer(), NEW_LIQUIDATION_BUFFER);
        assertEq(loan.getPremiumCollector(), NEW_PREMIUM_COLLECTOR);
        assertEq(loan.getGracePeriod(), NEW_GRACE_PERIOD);
        assertEq(loan.getPreClosureFee(), NEW_PRE_CLOSURE_FEE);
    }

    /// @notice LPM_SLOW address setters revert on the zero address
    function test_lpmSlow_addressSetters_revertOnZeroAddress() public {
        _scheduleAndExpectRevert(
            address(loan),
            lpm_slow,
            LPM_SLOW_ID(),
            abi.encodeCall(Loan.setLoanVaultFactory, (address(0))),
            abi.encodeWithSelector(Errors.ZeroAddress.selector)
        );

        _scheduleAndExpectRevert(
            address(loan),
            lpm_slow,
            LPM_SLOW_ID(),
            abi.encodeCall(Loan.setSwapAdapter, (address(0))),
            abi.encodeWithSelector(Errors.ZeroAddress.selector)
        );

        _scheduleAndExpectRevert(
            address(loan),
            lpm_slow,
            LPM_SLOW_ID(),
            abi.encodeCall(Loan.setZQuoter, (address(0))),
            abi.encodeWithSelector(Errors.ZeroAddress.selector)
        );

        _scheduleAndExpectRevert(
            address(loan),
            lpm_slow,
            LPM_SLOW_ID(),
            abi.encodeCall(Loan.setPremiumCollector, (address(0))),
            abi.encodeWithSelector(Errors.ZeroAddress.selector)
        );
    }

    /// @notice Unauthorized callers cannot update loan status.
    function test_protocolMutators_updateLoanDataForMicroLiquidation_revertForUnauthorized() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        vm.prank(attacker);
        vm.expectRevert(Errors.UnauthorizedCaller.selector);
        loan.updateLoanDataForFullLiquidation(lsa);
    }

    /// @notice Unauthorized callers cannot update stored loan data.
    function test_protocolMutators_updateLoanData_revertForUnauthorized() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        vm.prank(attacker);
        vm.expectRevert(Errors.UnauthorizedCaller.selector);
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
