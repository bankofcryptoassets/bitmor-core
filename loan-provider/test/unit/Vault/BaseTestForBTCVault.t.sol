// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BitmorTestBase} from "../../base/BitmorTestBase.sol";
import {VaultUtilities} from "./VaultUtilities.t.sol";
import {BTCVault, BTCVaultHarness} from "../../harness/BTCVaultHarness.sol";
import {MockTokenizedStrategy} from "../../mock/MockTokenizedStrategy.sol";
import {MockYieldSource} from "../../mock/MockYieldSource.sol";
import {MockERC20} from "../../mock/MockERC20.sol";

import {HelperConfig} from "../../../script/HelperConfig.s.sol";

/// @title BaseTestForBTCVault
/// @author Bitmor Protocol
/// @notice Comprehensive test suite for BTCVault functionality
/// @dev Tests vault operations, fee calculations, and strategy integration using mainnet fork.
///      Inherits from BitmorTestBase for AccessManager configuration and VaultUtilities for ERC-4626 testing helpers.
contract BaseTestForBTCVault is BitmorTestBase, VaultUtilities {
    /// @notice BTCVault contract instance under test
    BTCVaultHarness vault;

    /// @notice MockTokenizedStrategy contract instance for yield generation
    MockTokenizedStrategy strategy;

    /// @notice MockYieldSource for strategy
    MockYieldSource yieldSource;

    /// @notice Mock USDC token for unit tests
    MockERC20 internal mockUSDC;

    /// @notice Compatibility struct for tests that reference networkConfig
    struct MockNetworkConfig {
        address usdc;
        uint256 entryFee;
        uint256 exitFee;
    }

    /// @notice Network configuration containing protocol addresses
    MockNetworkConfig networkConfig;

    /// @notice Address that receives vault fees
    address feeRecipient;

    /// @notice Test user address for vault operations
    address user;

    /// @notice Amount of USDC to mint for testing (100M USDC)
    uint256 public constant USDC_TO_MINT = 100_000_000e6;

    /// @notice Standard deposit amount for tests (100k USDC)
    uint256 public constant DEPOSIT_AMOUNT = 100_000e6;

    /// @notice Scale factor for basis points calculations
    uint256 public constant BASIS_POINT_SCALE = 1e4;

    /// @notice Test amount for various operations (1000 USDC)
    uint256 public constant TEST_AMOUNT = 1000e6;

    /// @notice Small test amount for edge cases (100 USDC)
    uint256 public constant SMALL_TEST_AMOUNT = 100e6;

    uint256 public constant INITIAL_DEPOSIT_AMOUNT = 347933e6;

    /// @notice Standard strategy cap for tests (200,000 USDC - 2x DEPOSIT_AMOUNT)
    uint256 public constant STANDARD_STRATEGY_CAP = DEPOSIT_AMOUNT * 2;

    /// @notice Large strategy cap for tests (300,000 USDC - 3x DEPOSIT_AMOUNT)
    uint256 public constant LARGE_STRATEGY_CAP = DEPOSIT_AMOUNT * 3;

    /// @notice Very large cap for edge case testing (1 billion USDC)
    uint256 public constant VERY_LARGE_CAP = 1_000_000_000e6;

    /// @notice Small strategy cap for multiple strategy tests (50,000 USDC)
    uint256 public constant SMALL_STRATEGY_CAP = DEPOSIT_AMOUNT / 2;

    /// @notice Max strategies configured for tests
    uint256 public constant MAX_STRATEGIES = 10;

    /// @notice Sets up test environment with vault, strategy, and test accounts
    /// @dev Creates fresh contracts with mock tokens for unit testing.
    function setUp() public virtual override {
        // Create test user first
        user = makeAddr("user");
        feeRecipient = makeAddr("FEE_RECIPIENT");

        // Initialize AccessManager and RolesData through BitmorTestBase
        _initializeAccessManager(address(this));

        // Deploy mock USDC for unit tests
        mockUSDC = new MockERC20("USD Coin", "USDC", 6);

        // Set up mock network config for compatibility
        networkConfig = MockNetworkConfig({usdc: address(mockUSDC), entryFee: 10, exitFee: 10});

        // Deploy vault with mock USDC
        vault = new BTCVaultHarness(address(mockUSDC), address(manager));

        yieldSource = new MockYieldSource();
        strategy = new MockTokenizedStrategy(address(yieldSource), address(vault));

        // Set up BTC Vault roles
        _setBTCVaultRoles(user);

        // Set up target selectors
        _setTargetSelectorsLocal();

        // Configure vault
        _setFeeConfig();
        _transferUSDC();
        _setMaxStrategies();
    }

    /// @notice Set target function selectors for BTCVault roles
    /// @dev Uses actual BTCVault selectors. Some functions not in RolesData are included here.
    function _setTargetSelectorsLocal() internal {
        address target = address(vault);

        // BVM_SLOW selectors (includes functions not in RolesData)
        bytes4[] memory bvmSlowSelectors = new bytes4[](5);
        bvmSlowSelectors[0] = BTCVault.setFeeRecipient.selector;
        bvmSlowSelectors[1] = BTCVault.setEntryFee.selector;
        bvmSlowSelectors[2] = BTCVault.setExitFee.selector;
        bvmSlowSelectors[3] = BTCVault.setMaxStrategies.selector;
        bvmSlowSelectors[4] = BTCVault.unpause.selector;
        manager.setTargetFunctionRole(target, bvmSlowSelectors, BVM_SLOW_ID());

        // BVM_FAST selectors
        bytes4[] memory bvmFastSelectors = new bytes4[](1);
        bvmFastSelectors[0] = BTCVault.pause.selector;
        manager.setTargetFunctionRole(target, bvmFastSelectors, BVM_FAST_ID());

        // BVC selectors
        bytes4[] memory bvcSelectors = new bytes4[](2);
        bvcSelectors[0] = BTCVault.addStrategy.selector;
        bvcSelectors[1] = BTCVault.changeStrategyCap.selector;
        manager.setTargetFunctionRole(target, bvcSelectors, BVC_ID());

        // BVA_SLOW selectors
        bytes4[] memory bvaSlowSelectors = new bytes4[](2);
        bvaSlowSelectors[0] = BTCVault.updateSupplyQueue.selector;
        bvaSlowSelectors[1] = BTCVault.updateWithdrawQueue.selector;
        manager.setTargetFunctionRole(target, bvaSlowSelectors, BVA_SLOW_ID());

        // BVA_FAST selectors
        bytes4[] memory bvaFastSelectors = new bytes4[](1);
        bvaFastSelectors[0] = BTCVault.reallocateFunds.selector;
        manager.setTargetFunctionRole(target, bvaFastSelectors, BVA_FAST_ID());

        // BVD selectors
        bytes4[] memory bvdSelectors = new bytes4[](1);
        bvdSelectors[0] = BTCVault.deposit.selector;
        manager.setTargetFunctionRole(target, bvdSelectors, BVD_ID());
    }

    /// @notice Configure vault with fees using delayed operations
    function _setFeeConfig() internal {
        _scheduleAndExecuteLocal(
            bvm_slow, BVM_SLOW_ID(), abi.encodeCall(BTCVault.setEntryFee, (networkConfig.entryFee))
        );
        _scheduleAndExecuteLocal(bvm_slow, BVM_SLOW_ID(), abi.encodeCall(BTCVault.setExitFee, (networkConfig.exitFee)));
        _scheduleAndExecuteLocal(bvm_slow, BVM_SLOW_ID(), abi.encodeCall(BTCVault.setFeeRecipient, (feeRecipient)));
    }

    /// @notice Mint mock USDC to test accounts
    function _transferUSDC() internal {
        mockUSDC.mint(user, USDC_TO_MINT);
        mockUSDC.mint(address(this), USDC_TO_MINT);
    }

    /// @notice Set maximum strategies for the vault
    function _setMaxStrategies() internal {
        _scheduleAndExecuteLocal(bvm_slow, BVM_SLOW_ID(), abi.encodeCall(BTCVault.setMaxStrategies, (MAX_STRATEGIES)));
    }

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

    // ============ Backward Compatible Role ID Getters ============
    // These provide the old interface expected by existing test files like AccessControl.t.sol

    /// @notice Get BVM_SLOW role ID for backward compatibility
    function bvm_slow_id() internal view returns (uint64) {
        return BVM_SLOW_ID();
    }

    /// @notice Get BVM_FAST role ID for backward compatibility
    function bvm_fast_id() internal view returns (uint64) {
        return BVM_FAST_ID();
    }

    /// @notice Get BVC role ID for backward compatibility
    function bvc_id() internal view returns (uint64) {
        return BVC_ID();
    }

    /// @notice Get BVA_SLOW role ID for backward compatibility
    function bva_slow_id() internal view returns (uint64) {
        return BVA_SLOW_ID();
    }

    /// @notice Get BVA_FAST role ID for backward compatibility
    function bva_fast_id() internal view returns (uint64) {
        return BVA_FAST_ID();
    }

    /// @notice Get BVD role ID for backward compatibility
    function bvd_id() internal view returns (uint64) {
        return BVD_ID();
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
