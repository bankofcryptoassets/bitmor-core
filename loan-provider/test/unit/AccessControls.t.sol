// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./Loan/BaseLoan.t.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {Ownable} from "@bitmor/dependencies/openzeppelin/Ownable.sol";

/// @title AccessControlsTest
/// @notice Test suite for verifying access control mechanisms in the Bitmor Protocol
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

    /// @notice Non-owner cannot call admin setter functions.
    function test_onlyOwner_adminSetters_revertForNonOwner() public {
        vm.startPrank(attacker);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        loan.setLoanVaultFactory(NEW_FACTORY);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        loan.setSwapAdapter(NEW_SWAP_ADAPTER);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        loan.setZQuoter(NEW_ZQUOTER);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        loan.setLiquidationBuffer(NEW_LIQUIDATION_BUFFER);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        loan.setPremiumCollector(NEW_PREMIUM_COLLECTOR);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        loan.setGracePeriod(NEW_GRACE_PERIOD);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        loan.setPreClosureFee(NEW_PRE_CLOSURE_FEE);

        vm.stopPrank();
    }

    /// @notice Owner can call admin setters and updates are persisted.
    function test_owner_adminSetters_updateState() public {
        vm.startPrank(owner);

        loan.setLoanVaultFactory(NEW_FACTORY);
        loan.setSwapAdapter(NEW_SWAP_ADAPTER);
        loan.setZQuoter(NEW_ZQUOTER);
        loan.setLiquidationBuffer(NEW_LIQUIDATION_BUFFER);
        loan.setPremiumCollector(NEW_PREMIUM_COLLECTOR);
        loan.setGracePeriod(NEW_GRACE_PERIOD);
        loan.setPreClosureFee(NEW_PRE_CLOSURE_FEE);

        vm.stopPrank();

        assertEq(loan.s_loanVaultFactory(), NEW_FACTORY);
        assertEq(loan.s_swapAdapter(), NEW_SWAP_ADAPTER);
        assertEq(loan.s_zQuoter(), NEW_ZQUOTER);
        assertEq(loan.getLiquidationBuffer(), NEW_LIQUIDATION_BUFFER);
        assertEq(loan.getPremiumCollector(), NEW_PREMIUM_COLLECTOR);
        assertEq(loan.getGracePeriod(), NEW_GRACE_PERIOD);
        assertEq(loan.getPreClosureFee(), NEW_PRE_CLOSURE_FEE);
    }

    /// @notice Owner address setters revert on the zero address.
    function test_owner_addressSetters_revertOnZeroAddress() public {
        vm.startPrank(owner);

        vm.expectRevert(Errors.ZeroAddress.selector);
        loan.setLoanVaultFactory(address(0));

        vm.expectRevert(Errors.ZeroAddress.selector);
        loan.setSwapAdapter(address(0));

        vm.expectRevert(Errors.ZeroAddress.selector);
        loan.setZQuoter(address(0));

        vm.expectRevert(Errors.ZeroAddress.selector);
        loan.setPremiumCollector(address(0));

        vm.stopPrank();
    }

    /// @notice Unauthorized callers cannot update loan status.
    function test_protocolMutators_updateLoanStatus_revertForUnauthorized() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        vm.prank(attacker);
        vm.expectRevert(Errors.UnauthorizedCaller.selector);
        loan.updateLoanStatus(lsa, DataTypes.LoanStatus.Liquidated);
    }

    /// @notice Unauthorized callers cannot update stored loan data.
    function test_protocolMutators_updateLoanData_revertForUnauthorized() public setUpLoanForUser {
        address lsa = loan.getUserLoanAtIndex(user, 0);

        DataTypes.LoanData memory maliciousData = DataTypes.LoanData({
            borrower: attacker,
            depositAmount: 0,
            loanAmount: 0,
            collateralAmount: 0,
            estimatedMonthlyPayment: 0,
            duration: 0,
            createdAt: block.timestamp,
            insuranceID: 0,
            lastPaymentTimestamp: block.timestamp,
            status: DataTypes.LoanStatus.Completed
        });

        vm.prank(attacker);
        vm.expectRevert(Errors.UnauthorizedCaller.selector);
        loan.updateLoanData(abi.encode(maliciousData), lsa);
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
