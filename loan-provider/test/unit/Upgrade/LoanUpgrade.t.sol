// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {LoanUnitTestBase} from "../../base/LoanUnitTestBase.sol";
import {Loan} from "@bitmor/protocol/Loan.sol";
import {ILoan} from "@bitmor/interfaces/ILoan.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {TestConstants as TC} from "../../helpers/TestConstants.sol";

/// @title LoanV2
/// @notice Mock V2 implementation for upgrade testing
/// @dev Extends Loan with a new storage variable and version getter
contract LoanV2 is Loan {
    /// @dev ERC-7201 storage slot for LoanV2 extension
    bytes32 private constant LOAN_V2_STORAGE_LOCATION =
        keccak256(abi.encode(uint256(keccak256("bitmor.storage.LoanV2")) - 1)) & ~bytes32(uint256(0xff));

    /// @custom:storage-location erc7201:bitmor.storage.LoanV2
    struct LoanV2StorageData {
        uint256 newFeature;
    }

    function _getLoanV2Storage() internal pure returns (LoanV2StorageData storage $) {
        bytes32 slot = LOAN_V2_STORAGE_LOCATION;
        assembly {
            $.slot := slot
        }
    }

    /// @notice Sets a new feature value added in V2
    function setNewFeature(uint256 val) external {
        _getLoanV2Storage().newFeature = val;
    }

    /// @notice Returns the new feature value
    function newFeature() external view returns (uint256) {
        return _getLoanV2Storage().newFeature;
    }

    /// @notice Returns the version number
    function version() external pure returns (uint256) {
        return 2;
    }
}

/// @title LoanUpgradeTest
/// @notice Tests UUPS upgrade path for Loan contract
/// @dev Inherits LoanUnitTestBase for full loan infrastructure with mocks
contract LoanUpgradeTest is LoanUnitTestBase {
    /// @notice Address acting as the upgrader in tests
    address internal upgrader;

    /// @notice The `upgradeToAndCall` function selector
    bytes4 internal constant UPGRADE_SELECTOR = bytes4(keccak256("upgradeToAndCall(address,bytes)"));

    function setUp() public override {
        super.setUp();

        upgrader = makeAddr("upgrader");

        // Map upgradeToAndCall selector to ADMIN role on the Loan target for testing
        vm.startPrank(admin);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = UPGRADE_SELECTOR;
        manager.setTargetFunctionRole(address(loan), selectors, 0); // ADMIN role = 0
        vm.stopPrank();
    }

    /// @notice Verifies V1 state is preserved after upgrading to V2
    function test_UpgradeToV2_PreservesState() public {
        // Arrange: create a loan in V1
        address lsa = _createStandardLoan();
        DataTypes.LoanData memory loanDataBefore = loan.getLoanByLSA(lsa);

        // Act: deploy V2 implementation and upgrade via AccessManager
        LoanV2 loanV2Impl = new LoanV2();
        bytes memory upgradeData = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(loanV2Impl), ""));

        vm.prank(admin);
        manager.execute(address(loan), upgradeData);

        // Assert: V1 state preserved
        LoanV2 loanV2 = LoanV2(address(loan));
        DataTypes.LoanData memory loanDataAfter = loanV2.getLoanByLSA(lsa);
        assertEq(loanDataAfter.borrower, loanDataBefore.borrower, "borrower preserved after upgrade");
        assertEq(uint256(loanDataAfter.status), uint256(loanDataBefore.status), "status preserved after upgrade");
        assertEq(loanDataAfter.btcAmount, loanDataBefore.btcAmount, "btc amount preserved after upgrade");
        assertEq(
            loanDataAfter.estimatedMonthlyPayment,
            loanDataBefore.estimatedMonthlyPayment,
            "monthly payment preserved after upgrade"
        );

        // Assert: V2 features work
        assertEq(loanV2.version(), 2, "v2 version accessible");
        loanV2.setNewFeature(42);
        assertEq(loanV2.newFeature(), 42, "v2 new feature works");
    }

    /// @notice Verifies re-initialization is blocked after upgrade
    function test_RevertWhen_ReinitializeAfterUpgrade() public {
        // Arrange: upgrade to V2
        LoanV2 loanV2Impl = new LoanV2();
        bytes memory upgradeData = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(loanV2Impl), ""));

        vm.prank(admin);
        manager.execute(address(loan), upgradeData);

        // Assert + Act: re-initialization should revert
        vm.expectRevert();
        LoanV2(address(loan))
            .initialize(
                ILoan.InitParams({
                    manager: address(manager),
                    aaveV3Pool: address(mockAavePool),
                    aaveAddressesProvider: address(mockAddressesProvider),
                    bitmorPool: address(mockBitmorPool),
                    oracle: address(mockOracle),
                    collateralAsset: address(mockBTCVault),
                    debtAsset: address(mockUSDC),
                    btc: address(mockCbBTC),
                    bitmorAddressesProvider: address(bitmorAddressesProvider),
                    preClosureFeeBps: 0,
                    gracePeriod: 0,
                    slippageSwap: 50,
                    slippageSharesToAsset: 100,
                    maxBTCAmt: 10e8,
                    minBTCAmt: 0.01e8,
                    minDeposit: 30_00,
                    maxDuration: 60,
                    liquidationFee: 0
                })
            );
    }

    /// @notice Verifies unauthorized upgrade reverts
    function test_RevertWhen_UnauthorizedUpgrade() public {
        LoanV2 loanV2Impl = new LoanV2();
        bytes memory upgradeData = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(loanV2Impl), ""));

        // User does not have the role to call upgradeToAndCall on the Loan target
        vm.prank(user);
        vm.expectRevert();
        manager.execute(address(loan), upgradeData);
    }

    /// @notice Verifies direct upgradeToAndCall without going through AccessManager reverts for unauthorized caller
    function test_RevertWhen_DirectUpgradeCallWithoutAccessManager() public {
        LoanV2 loanV2Impl = new LoanV2();

        // Direct call from unauthorized user should revert because restricted modifier
        // requires the call to go through AccessManager.execute()
        address randomUser = makeAddr("randomUser");
        vm.prank(randomUser);
        vm.expectRevert();
        loan.upgradeToAndCall(address(loanV2Impl), "");
    }

    /// @notice Verifies implementation address changes after upgrade
    function test_UpgradeToV2_ChangesImplementation() public {
        // Arrange: get V1 implementation
        address implBefore = _getImplAddress(address(loan));

        // Act: upgrade to V2
        LoanV2 loanV2Impl = new LoanV2();
        bytes memory upgradeData = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(loanV2Impl), ""));

        vm.prank(admin);
        manager.execute(address(loan), upgradeData);

        // Assert: implementation changed
        address implAfter = _getImplAddress(address(loan));
        assertTrue(implAfter != implBefore, "implementation address should change after upgrade");
        assertEq(implAfter, address(loanV2Impl), "implementation should point to V2");
    }
}
