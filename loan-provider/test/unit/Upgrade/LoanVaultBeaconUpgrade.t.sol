// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {LoanUnitTestBase} from "../../base/LoanUnitTestBase.sol";
import {Loan} from "@bitmor/protocol/Loan.sol";
import {LoanVault} from "@bitmor/protocol/LoanVault.sol";
import {LoanVaultFactory} from "@bitmor/protocol/LoanVaultFactory.sol";
import {BeaconController} from "@bitmor/protocol/BeaconController.sol";
import {IBeaconController} from "@bitmor/interfaces/IBeaconController.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {TestConstants as TC} from "../../helpers/TestConstants.sol";

/// @title LoanVaultV2
/// @notice Mock V2 implementation for beacon upgrade testing
/// @dev Extends LoanVault with a version getter to verify upgrade took effect
contract LoanVaultV2 is LoanVault {
    /// @notice Returns the version number
    function version() external pure returns (uint256) {
        return 2;
    }
}

/// @title LoanVaultBeaconUpgradeTest
/// @notice Tests beacon upgrade atomicity - upgrading the beacon upgrades all LoanVault proxies
/// @dev Deploys the full beacon proxy infrastructure (BeaconController + UpgradeableBeacon) to test access-controlled upgrades
contract LoanVaultBeaconUpgradeTest is LoanUnitTestBase {
    /// @notice BeaconController wrapping the UpgradeableBeacon with AccessManager access control
    BeaconController public beaconController;

    /// @notice The `upgradeBeacon` function selector on BeaconController
    bytes4 internal constant UPGRADE_BEACON_SELECTOR = IBeaconController.upgradeBeacon.selector;

    function setUp() public override {
        super.setUp();

        // Replace the simple beacon proxy with full beacon proxy infrastructure that uses BeaconController
        _deployFullBeaconProxyForTest();
    }

    /// @notice Deploys the full beacon proxy infrastructure with BeaconController and reconfigures the Loan contract
    /// @dev Creates new beacon proxy infrastructure, transfers beacon ownership, updates factory in AddressesProvider.
    ///      Beacon deploy/transferOwnership run unpranked (beacon owner is address(this)).
    ///      AccessManager operations use admin prank (admin holds ADMIN_ROLE).
    function _deployFullBeaconProxyForTest() internal {
        // Step 1: Deploy beacon proxy without prank -- beacon owner is address(this)
        address lvImpl;
        address beaconAddr;
        address bcAddr;
        address factoryAddr;
        (lvImpl, beaconAddr, bcAddr, factoryAddr) = _deployFullBeaconProxy(address(manager), address(loan));

        beaconController = BeaconController(bcAddr);
        loanVaultFactory = LoanVaultFactory(factoryAddr);

        // Step 2: AccessManager operations require admin role
        vm.startPrank(admin);

        // Update the BitmorAddressesProvider with the new factory (restricted function)
        bitmorAddressesProvider.setVaultFactory(factoryAddr);

        // Map upgradeBeacon selector to ADMIN role on the BeaconController for testing
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = UPGRADE_BEACON_SELECTOR;
        manager.setTargetFunctionRole(address(beaconController), selectors, 0); // ADMIN role = 0

        vm.stopPrank();
    }

    /// @notice Verifies that upgrading the beacon upgrades all existing LoanVault proxies atomically
    function test_BeaconUpgrade_UpgradesAllVaults() public {
        // Arrange: create two separate loans (two LoanVault proxies)
        address lsa1 = _createStandardLoan();

        // Warp to ensure unique CREATE2 salt (borrower + timestamp)
        vm.warp(block.timestamp + 1000);

        // Create a second loan with different parameters to get a different LSA
        address lsa2 = _createLoan(TC.STANDARD_COLLATERAL / 2, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        // Verify both are V1 (no version() function - should revert)
        vm.expectRevert();
        LoanVaultV2(payable(lsa1)).version();

        vm.expectRevert();
        LoanVaultV2(payable(lsa2)).version();

        // Act: upgrade beacon to V2
        LoanVaultV2 loanVaultV2Impl = new LoanVaultV2();
        bytes memory upgradeData = abi.encodeCall(IBeaconController.upgradeBeacon, (address(loanVaultV2Impl)));

        vm.prank(admin);
        manager.execute(address(beaconController), upgradeData);

        // Assert: both vaults now have V2 logic
        assertEq(LoanVaultV2(payable(lsa1)).version(), 2, "lsa1 should be V2 after beacon upgrade");
        assertEq(LoanVaultV2(payable(lsa2)).version(), 2, "lsa2 should be V2 after beacon upgrade");
    }

    /// @notice Verifies that LoanVault state is preserved after beacon upgrade
    function test_BeaconUpgrade_PreservesVaultState() public {
        // Arrange: create a loan
        address lsa = _createStandardLoan();

        // Capture pre-upgrade state
        address ownerBefore = LoanVault(payable(lsa)).owner();
        address borrowerBefore = LoanVault(payable(lsa)).borrower();
        bool isInitializedBefore = LoanVault(payable(lsa)).isInitialized();

        // Act: upgrade beacon
        LoanVaultV2 loanVaultV2Impl = new LoanVaultV2();
        bytes memory upgradeData = abi.encodeCall(IBeaconController.upgradeBeacon, (address(loanVaultV2Impl)));

        vm.prank(admin);
        manager.execute(address(beaconController), upgradeData);

        // Assert: state preserved
        LoanVaultV2 upgradedVault = LoanVaultV2(payable(lsa));
        assertEq(upgradedVault.owner(), ownerBefore, "owner preserved after beacon upgrade");
        assertEq(upgradedVault.borrower(), borrowerBefore, "borrower preserved after beacon upgrade");
        assertEq(upgradedVault.isInitialized(), isInitializedBefore, "initialization state preserved");
    }

    /// @notice Verifies that unauthorized beacon upgrade reverts
    function test_RevertWhen_UnauthorizedBeaconUpgrade() public {
        LoanVaultV2 loanVaultV2Impl = new LoanVaultV2();
        bytes memory upgradeData = abi.encodeCall(IBeaconController.upgradeBeacon, (address(loanVaultV2Impl)));

        // Random user cannot upgrade the beacon
        address randomUser = makeAddr("randomUser");
        vm.prank(randomUser);
        vm.expectRevert();
        manager.execute(address(beaconController), upgradeData);
    }

    /// @notice Verifies direct call to BeaconController without AccessManager reverts for unauthorized caller
    function test_RevertWhen_DirectBeaconUpgradeCallWithoutAccessManager() public {
        LoanVaultV2 loanVaultV2Impl = new LoanVaultV2();

        // Direct call from unauthorized user should revert because restricted modifier
        // requires the call to go through AccessManager.execute()
        address randomUser = makeAddr("randomUser");
        vm.prank(randomUser);
        vm.expectRevert();
        beaconController.upgradeBeacon(address(loanVaultV2Impl));
    }

    /// @notice Verifies new vaults created after upgrade also use V2 logic
    function test_BeaconUpgrade_NewVaultsUseV2() public {
        // Arrange: create a loan before upgrade
        address lsaBefore = _createStandardLoan();

        // Act: upgrade beacon
        LoanVaultV2 loanVaultV2Impl = new LoanVaultV2();
        bytes memory upgradeData = abi.encodeCall(IBeaconController.upgradeBeacon, (address(loanVaultV2Impl)));

        vm.prank(admin);
        manager.execute(address(beaconController), upgradeData);

        // Warp to ensure unique CREATE2 salt (borrower + timestamp)
        vm.warp(block.timestamp + 1000);

        // Create a new loan after upgrade
        address lsaAfter = _createLoan(TC.STANDARD_COLLATERAL / 2, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        // Assert: both old and new vaults have V2 logic
        assertEq(LoanVaultV2(payable(lsaBefore)).version(), 2, "pre-upgrade vault should be V2");
        assertEq(LoanVaultV2(payable(lsaAfter)).version(), 2, "post-upgrade vault should be V2");
    }
}
