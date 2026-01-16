// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {AccessManager} from "@openzeppelin/access/manager/AccessManager.sol";

import {VaultUtilities} from "./VaultUtilities.t.sol";
import {USDCVault} from "@bitmor/vaults/usdc-vault/USDCVault.sol";
import {USDCStrategy} from "@bitmor/vaults/usdc-vault/USDCStrategy.sol";
import {IERC20} from "@bitmor/dependencies/openzeppelin/IERC20.sol";

import {HelperConfig} from "../../../script/HelperConfig.s.sol";

/// @title BaseTestForUSDCVault
/// @notice Base test contract for USDCVault functionality
/// @dev Tests vault operations using AccessManager pattern.
///      Inherits from VaultUtilities for generic ERC-4626 testing helpers.
/// @author Bitmor Protocol
contract BaseTestForUSDCVault is VaultUtilities {
    using SafeTransferLib for address;

    /// @notice USDCVault contract instance under test
    USDCVault internal vault;

    /// @notice USDCStrategy contract instance for yield allocation
    USDCStrategy internal strategy;

    /// @notice AccessManager contract for role-based access control
    AccessManager internal manager;

    /// @notice Network configuration containing protocol addresses
    HelperConfig.NetworkConfig internal networkConfig;

    // ============ Role IDs ============

    /// @notice Manager slow role ID (requires delay for sensitive operations)
    uint64 internal constant MANAGER_SLOW_ID = 110;
    /// @notice Manager slow role delay (1 day)
    uint32 internal constant MANAGER_SLOW_DELAY = 1 days;

    /// @notice Manager fast role ID (no delay for emergency operations)
    uint64 internal constant MANAGER_FAST_ID = 11;

    /// @notice Allocator role ID (can call reallocateAssets)
    uint64 internal constant ALLOCATOR_ID = 12;

    // ============ Role Addresses ============

    address internal manager_slow;
    address internal manager_fast;
    address internal allocator;
    address internal lender;
    address internal lender2;
    address internal attacker;

    // ============ Test Amount Constants ============

    /// @notice Standard deposit amount (10,000 USDC with 6 decimals)
    uint256 internal constant STANDARD_DEPOSIT = 10_000e6;

    /// @notice Large deposit amount (1,000,000 USDC with 6 decimals)
    uint256 internal constant LARGE_DEPOSIT = 1_000_000e6;

    /// @notice Small deposit amount for edge case testing (100 USDC)
    uint256 internal constant SMALL_DEPOSIT = 100e6;

    /// @notice Amount of USDC to mint for testing
    uint256 internal constant USDC_TO_MINT = 100_000_000e6;

    // ============ Allocation Constants ============

    /// @notice Basis points denominator (10,000 = 100%)
    uint256 internal constant BASIS_POINTS = 10_000;

    /// @notice Default Aave allocation (80% = 8000 bps)
    uint256 internal constant DEFAULT_AAVE_ALLOCATION_BPS = 8000;

    // ============ Setup ============

    /// @notice Core test setup - deploys vault, strategy, and configures access roles
    /// @dev Creates fresh contracts and configures them with network-specific addresses
    function setUp() public virtual {
        HelperConfig config = new HelperConfig();
        networkConfig = config.getNetworkConfig();

        address initial_admin = address(this);

        // Deploy AccessManager
        manager = new AccessManager(initial_admin);

        // Deploy vault with AccessManager
        vault = new USDCVault(address(manager), networkConfig.usdc, networkConfig.bitmorPool);

        // Deploy strategy
        strategy = new USDCStrategy(address(vault), networkConfig.aaveV3Pool, networkConfig.bitmorPool);

        // Create test addresses
        manager_slow = makeAddr("MANAGER_SLOW");
        manager_fast = makeAddr("MANAGER_FAST");
        allocator = makeAddr("ALLOCATOR");
        lender = makeAddr("LENDER");
        lender2 = makeAddr("LENDER2");
        attacker = makeAddr("ATTACKER");

        // Grant roles
        _setRoles();

        // Set function permissions
        _setTargetSelectors();

        // Configure vault with strategy
        _setStrategy();

        // Transfer USDC to test accounts
        _transferUSDC();
    }

    /// @notice Grants roles to test addresses via AccessManager
    function _setRoles() internal {
        manager.grantRole(MANAGER_FAST_ID, manager_fast, 0);
        manager.grantRole(MANAGER_SLOW_ID, manager_slow, MANAGER_SLOW_DELAY);
        manager.grantRole(ALLOCATOR_ID, allocator, 0);
    }

    /// @notice Sets function permissions for each role
    function _setTargetSelectors() internal {
        address target = address(vault);

        // Manager slow functions (require delay)
        bytes4[] memory manager_slow_selectors = new bytes4[](3);
        manager_slow_selectors[0] = USDCVault.setStrategy.selector;
        manager_slow_selectors[1] = USDCVault.updateMinimumDeltaRequired.selector;
        manager_slow_selectors[2] = USDCVault.unpause.selector;
        manager.setTargetFunctionRole(target, manager_slow_selectors, MANAGER_SLOW_ID);

        // Manager fast functions (no delay)
        bytes4[] memory manager_fast_selectors = new bytes4[](1);
        manager_fast_selectors[0] = USDCVault.pause.selector;
        manager.setTargetFunctionRole(target, manager_fast_selectors, MANAGER_FAST_ID);

        // Allocator functions - use function signature for overloaded function
        bytes4[] memory allocator_selectors = new bytes4[](1);
        allocator_selectors[0] = bytes4(keccak256("reallocateAssets()"));
        manager.setTargetFunctionRole(target, allocator_selectors, ALLOCATOR_ID);

        // reallocateAssets(uint256) is restricted to BLP via msg.sender check, not AccessManager
    }

    /// @notice Sets the strategy on the vault
    function _setStrategy() internal {
        _scheduleAndExecute(manager_slow, MANAGER_SLOW_ID, abi.encodeCall(USDCVault.setStrategy, (address(strategy))));
    }

    /// @notice Transfers USDC to test accounts
    function _transferUSDC() internal {
        vm.startPrank(networkConfig.usdc_holder);
        (networkConfig.usdc).safeTransfer(lender, USDC_TO_MINT);
        (networkConfig.usdc).safeTransfer(lender2, USDC_TO_MINT);
        (networkConfig.usdc).safeTransfer(address(this), USDC_TO_MINT);
        vm.stopPrank();
    }

    // ============ Helper Functions ============

    /// @notice Schedules and executes an operation through AccessManager
    /// @param caller The address calling the operation
    /// @param roleId The role ID of the caller
    /// @param data The encoded function call data
    function _scheduleAndExecute(address caller, uint64 roleId, bytes memory data) internal {
        (, uint32 delay,,) = manager.getAccess(roleId, caller);
        uint48 when = uint48(block.timestamp + delay);

        vm.startPrank(caller);
        if (delay > 0) {
            manager.schedule(address(vault), data, when);
            vm.warp(when);
        }
        manager.execute(address(vault), data);
        vm.stopPrank();
    }

    /// @notice Schedules an operation and expects it to revert
    /// @param caller The address calling the operation
    /// @param roleId The role ID of the caller
    /// @param data The encoded function call data
    /// @param revertData The expected revert data
    function _scheduleAndExpectRevert(address caller, uint64 roleId, bytes memory data, bytes memory revertData)
        internal
    {
        (, uint32 delay,,) = manager.getAccess(roleId, caller);
        uint48 when = uint48(block.timestamp + delay);

        vm.startPrank(caller);
        if (delay > 0) {
            manager.schedule(address(vault), data, when);
            vm.warp(when);
        }
        vm.expectRevert(revertData);
        manager.execute(address(vault), data);
        vm.stopPrank();
    }

    /// @notice Deposits USDC into vault for a user
    /// @param user The user depositing
    /// @param amount The amount of USDC to deposit
    /// @return shares The number of shares minted
    function _deposit(address user, uint256 amount) internal returns (uint256 shares) {
        vm.startPrank(user);
        IERC20(networkConfig.usdc).approve(address(vault), amount);
        shares = vault.deposit(amount, user);
        vm.stopPrank();
    }

    /// @notice Withdraws USDC from vault for a user
    /// @param user The user withdrawing
    /// @param assets The amount of USDC to withdraw
    /// @return shares The number of shares burned
    function _withdraw(address user, uint256 assets) internal returns (uint256 shares) {
        vm.prank(user);
        shares = vault.withdraw(assets, user, user);
    }

    /// @notice Redeems shares from vault for a user
    /// @param user The user redeeming
    /// @param shares The number of shares to redeem
    /// @return assets The amount of USDC returned
    function _redeem(address user, uint256 shares) internal returns (uint256 assets) {
        vm.prank(user);
        assets = vault.redeem(shares, user, user);
    }

    /// @notice Gets the current share price
    /// @return The share price scaled to 1e18
    function _getSharePrice() internal view returns (uint256) {
        uint256 supply = vault.totalSupply();
        if (supply == 0) return 1e18;
        return (vault.totalAssets() * 1e18) / supply;
    }

    /// @notice Funds a lender with USDC and approves vault spending
    /// @param lenderAddr The lender address to fund
    /// @param amount The amount of USDC to approve
    function _fundLenderWithUsdc(address lenderAddr, uint256 amount) internal {
        vm.prank(lenderAddr);
        IERC20(networkConfig.usdc).approve(address(vault), amount);
    }
}
