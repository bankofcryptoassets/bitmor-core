// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BitmorTestBase} from "../BitmorTestBase.sol";
import {VaultUtilities} from "./VaultUtilities.t.sol";
import {USDCVault} from "@bitmor/vaults/usdc-vault/USDCVault.sol";
import {USDCStrategy} from "@bitmor/vaults/usdc-vault/USDCStrategy.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

import {HelperConfig} from "../../../script/HelperConfig.s.sol";

/// @title BaseTestForUSDCVault
/// @author Bitmor Protocol
/// @notice Base test contract for USDCVault functionality
/// @dev Tests vault operations using AccessManager pattern.
///      Inherits from BitmorTestBase for AccessManager configuration and VaultUtilities for ERC-4626 testing helpers.
contract BaseTestForUSDCVault is BitmorTestBase, VaultUtilities {
    /// @notice USDCVault contract instance under test
    USDCVault internal vault;

    /// @notice USDCStrategy contract instance for yield allocation
    USDCStrategy internal strategy;

    /// @notice Network configuration containing protocol addresses
    HelperConfig.NetworkConfig internal networkConfig;

    // ============ Test Addresses ============

    /// @notice Primary lender address for deposit/withdraw tests
    address internal lender;

    /// @notice Secondary lender address for multi-user tests
    address internal lender2;

    /// @notice Attacker address for security tests
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
    /// @dev Creates fresh contracts and configures them with network-specific addresses.
    ///      Uses BitmorTestBase for AccessManager initialization and role management.
    ///      Note: Role IDs now use correct USDC vault IDs (21, 210, 22, 23) from RolesData.
    function setUp() public virtual {
        HelperConfig config = new HelperConfig();
        networkConfig = config.getNetworkConfig();

        // Create test addresses
        lender = makeAddr("LENDER");
        lender2 = makeAddr("LENDER2");
        attacker = makeAddr("ATTACKER");

        // Initialize AccessManager and RolesData through BitmorTestBase
        // This deploys a fresh AccessManager and creates all role actor addresses
        _initializeAccessManager(address(this));

        // Deploy vault with inherited manager
        vault = new USDCVault(address(manager), networkConfig.usdc, networkConfig.bitmorPool);

        // Deploy strategy
        strategy = new USDCStrategy(address(vault), networkConfig.aaveV3Pool, networkConfig.bitmorPool);

        // Set up USDC Vault roles using BitmorTestBase helper
        _setUSDCVaultRoles();

        // Set function permissions (using local function for complete selector coverage)
        _setTargetSelectorsLocal();

        // Configure vault with strategy
        _setStrategy();

        // Transfer USDC to test accounts
        _transferUSDC();
    }

    /// @notice Sets function permissions for each role using correct USDC vault role IDs
    /// @dev Uses actual USDCVault selectors with role IDs from RolesData
    function _setTargetSelectorsLocal() internal {
        address target = address(vault);

        // UVM_SLOW functions (require 1 day delay)
        bytes4[] memory uvmSlowSelectors = new bytes4[](3);
        uvmSlowSelectors[0] = USDCVault.setStrategy.selector;
        uvmSlowSelectors[1] = USDCVault.updateMinimumDeltaRequired.selector;
        uvmSlowSelectors[2] = USDCVault.unpause.selector;
        manager.setTargetFunctionRole(target, uvmSlowSelectors, UVM_SLOW_ID);

        // UVM_FAST functions (no delay)
        bytes4[] memory uvmFastSelectors = new bytes4[](1);
        uvmFastSelectors[0] = USDCVault.pause.selector;
        manager.setTargetFunctionRole(target, uvmFastSelectors, UVM_FAST_ID);

        // UVA functions - use function signature for overloaded function
        bytes4[] memory uvaSelectors = new bytes4[](1);
        uvaSelectors[0] = bytes4(keccak256("reallocateAssets()"));
        manager.setTargetFunctionRole(target, uvaSelectors, UVA_ID);

        // reallocateAssets(uint256) is restricted to BLP via msg.sender check, not AccessManager
    }

    /// @notice Sets the strategy on the vault using UVM_SLOW role
    function _setStrategy() internal {
        _scheduleAndExecuteLocal(uvm_slow, UVM_SLOW_ID, abi.encodeCall(USDCVault.setStrategy, (address(strategy))));
    }

    /// @notice Transfers USDC to test accounts using Foundry's deal() cheatcode
    /// @dev Uses deal() instead of safeTransfer to avoid dependency on holder balances
    function _transferUSDC() internal {
        deal(networkConfig.usdc, lender, USDC_TO_MINT);
        deal(networkConfig.usdc, lender2, USDC_TO_MINT);
        deal(networkConfig.usdc, address(this), USDC_TO_MINT);
    }

    // ============ Helper Functions ============

    /// @notice Schedule and execute a delayed operation (local helper targeting vault)
    /// @param caller The address calling the operation
    /// @param roleId The role ID of the caller
    /// @param data The encoded function call data
    function _scheduleAndExecuteLocal(address caller, uint64 roleId, bytes memory data) internal {
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

    /// @notice Schedule an operation and expect it to revert (local helper targeting vault)
    /// @param caller The address calling the operation
    /// @param roleId The role ID of the caller
    /// @param data The encoded function call data
    /// @param revertData The expected revert data
    function _scheduleAndExpectRevertLocal(address caller, uint64 roleId, bytes memory data, bytes memory revertData)
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
    /// @param depositor The user depositing
    /// @param amount The amount of USDC to deposit
    /// @return shares The number of shares minted
    function _deposit(address depositor, uint256 amount) internal returns (uint256 shares) {
        vm.startPrank(depositor);
        IERC20(networkConfig.usdc).approve(address(vault), amount);
        shares = vault.deposit(amount, depositor);
        vm.stopPrank();
    }

    /// @notice Withdraws USDC from vault for a user
    /// @param withdrawer The user withdrawing
    /// @param assets The amount of USDC to withdraw
    /// @return shares The number of shares burned
    function _withdraw(address withdrawer, uint256 assets) internal returns (uint256 shares) {
        vm.prank(withdrawer);
        shares = vault.withdraw(assets, withdrawer, withdrawer);
    }

    /// @notice Redeems shares from vault for a user
    /// @param redeemer The user redeeming
    /// @param sharesToRedeem The number of shares to redeem
    /// @return assets The amount of USDC returned
    function _redeem(address redeemer, uint256 sharesToRedeem) internal returns (uint256 assets) {
        vm.prank(redeemer);
        assets = vault.redeem(sharesToRedeem, redeemer, redeemer);
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

    // ============ Backward Compatible Schedule Helpers ============

    /// @notice Schedule and execute (backward compatible wrapper)
    /// @dev Maintains original function signature for existing tests
    function _scheduleAndExecute(address caller, uint64 roleId, bytes memory data) internal {
        _scheduleAndExecuteLocal(caller, roleId, data);
    }

    /// @notice Schedule and expect revert (backward compatible wrapper)
    function _scheduleAndExpectRevert(address caller, uint64 roleId, bytes memory data, bytes memory revertData)
        internal
    {
        _scheduleAndExpectRevertLocal(caller, roleId, data, revertData);
    }
}
