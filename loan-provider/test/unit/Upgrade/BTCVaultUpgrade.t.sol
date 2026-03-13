// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTestForBTCVault} from "../Vault/BaseTestForBTCVault.t.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title BTCVaultV2
/// @notice Mock V2 implementation for upgrade testing
/// @dev Extends BTCVault with a version getter to verify upgrade took effect
contract BTCVaultV2 is BTCVault {
    /// @dev ERC-7201 storage slot for BTCVaultV2 extension
    bytes32 private constant BTCVAULT_V2_STORAGE_LOCATION =
        keccak256(abi.encode(uint256(keccak256("bitmor.storage.BTCVaultV2")) - 1)) & ~bytes32(uint256(0xff));

    /// @custom:storage-location erc7201:bitmor.storage.BTCVaultV2
    struct BTCVaultV2StorageData {
        uint256 newFeature;
    }

    function _getBTCVaultV2Storage() internal pure returns (BTCVaultV2StorageData storage $) {
        bytes32 slot = BTCVAULT_V2_STORAGE_LOCATION;
        assembly {
            $.slot := slot
        }
    }

    /// @notice Sets a new feature value added in V2
    function setNewFeature(uint256 val) external {
        _getBTCVaultV2Storage().newFeature = val;
    }

    /// @notice Returns the new feature value
    function newFeature() external view returns (uint256) {
        return _getBTCVaultV2Storage().newFeature;
    }

    /// @notice Returns the version number
    function version() external pure returns (uint256) {
        return 2;
    }
}

/// @title BTCVaultUpgradeTest
/// @notice Tests UUPS upgrade path for BTCVault contract
/// @dev Inherits BaseTestForBTCVault which deploys BTCVault behind ERC1967Proxy
contract BTCVaultUpgradeTest is BaseTestForBTCVault {
    /// @notice The `upgradeToAndCall` function selector
    bytes4 internal constant UPGRADE_SELECTOR = bytes4(keccak256("upgradeToAndCall(address,bytes)"));

    function setUp() public override {
        super.setUp();

        // Map upgradeToAndCall selector to ADMIN role on the BTCVault target for testing
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = UPGRADE_SELECTOR;
        manager.setTargetFunctionRole(address(vault), selectors, 0); // ADMIN role = 0
    }

    /// @notice Helper to add strategy via proper access control
    function _addStrategy(address strat, uint256 cap) internal {
        _scheduleAndExecuteLocal(bvc, BVC_ID(), abi.encodeCall(BTCVault.addStrategy, (strat, cap)));
    }

    /// @notice Verifies shares and balances are preserved after upgrading to V2
    function test_UpgradeToV2_PreservesShares() public {
        // Arrange: add strategy so maxDeposit > 0, then deposit tokens to create shares
        _addStrategy(address(strategy), STANDARD_STRATEGY_CAP);

        uint256 depositAmount = DEPOSIT_AMOUNT;
        vm.startPrank(user);
        mockUSDC.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        uint256 sharesBefore = vault.balanceOf(user);
        uint256 totalAssetsBefore = vault.totalAssets();
        assertGt(sharesBefore, 0, "shares should be minted after deposit");

        // Act: deploy V2 implementation and upgrade via AccessManager
        BTCVaultV2 vaultV2Impl = new BTCVaultV2();
        bytes memory upgradeData = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(vaultV2Impl), ""));

        manager.execute(address(vault), upgradeData);

        // Assert: shares and assets preserved
        BTCVaultV2 vaultV2 = BTCVaultV2(address(vault));
        assertEq(vaultV2.balanceOf(user), sharesBefore, "user shares preserved after upgrade");
        assertEq(vaultV2.totalAssets(), totalAssetsBefore, "total assets preserved after upgrade");

        // Assert: V2 features work
        assertEq(vaultV2.version(), 2, "v2 version accessible");
        vaultV2.setNewFeature(99);
        assertEq(vaultV2.newFeature(), 99, "v2 new feature works");
    }

    /// @notice Verifies re-initialization is blocked after upgrade
    function test_RevertWhen_ReinitializeAfterUpgrade() public {
        // Arrange: upgrade to V2
        BTCVaultV2 vaultV2Impl = new BTCVaultV2();
        bytes memory upgradeData = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(vaultV2Impl), ""));

        manager.execute(address(vault), upgradeData);

        // Assert + Act: re-initialization should revert
        vm.expectRevert();
        BTCVaultV2(address(vault)).initialize(address(mockUSDC), address(manager), 5);
    }

    /// @notice Verifies unauthorized upgrade reverts
    function test_RevertWhen_UnauthorizedUpgrade() public {
        BTCVaultV2 vaultV2Impl = new BTCVaultV2();
        bytes memory upgradeData = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(vaultV2Impl), ""));

        // Random user does not have the role to call upgradeToAndCall on the vault target
        address randomUser = makeAddr("randomUser");
        vm.prank(randomUser);
        vm.expectRevert();
        manager.execute(address(vault), upgradeData);
    }

    /// @notice Verifies direct upgradeToAndCall without AccessManager reverts for unauthorized caller
    function test_RevertWhen_DirectUpgradeCallWithoutAccessManager() public {
        BTCVaultV2 vaultV2Impl = new BTCVaultV2();

        // Direct call from unauthorized user should revert because restricted modifier
        // requires the call to go through AccessManager.execute()
        address randomUser = makeAddr("randomUser");
        vm.prank(randomUser);
        vm.expectRevert();
        BTCVault(address(vault)).upgradeToAndCall(address(vaultV2Impl), "");
    }

    /// @notice Verifies deposit and withdraw still work after upgrade
    function test_UpgradeToV2_DepositAndWithdrawStillWork() public {
        // Arrange: add strategy so maxDeposit > 0, then upgrade
        _addStrategy(address(strategy), STANDARD_STRATEGY_CAP);

        BTCVaultV2 vaultV2Impl = new BTCVaultV2();
        bytes memory upgradeData = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(vaultV2Impl), ""));

        manager.execute(address(vault), upgradeData);

        BTCVaultV2 vaultV2 = BTCVaultV2(address(vault));

        // Act: deposit after upgrade
        uint256 depositAmount = DEPOSIT_AMOUNT;
        vm.startPrank(user);
        mockUSDC.approve(address(vaultV2), depositAmount);
        vaultV2.deposit(depositAmount, user);
        vm.stopPrank();

        uint256 shares = vaultV2.balanceOf(user);
        assertGt(shares, 0, "shares should be minted after post-upgrade deposit");

        // Act: withdraw after upgrade
        vm.prank(user);
        vaultV2.redeem(shares, user, user);

        assertEq(vaultV2.balanceOf(user), 0, "shares should be zero after full redeem");
    }
}
