// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BitmorTestBase} from "../../base/BitmorTestBase.sol";
import {VaultUtilities} from "./VaultUtilities.t.sol";
import {BTCVault, BTCVaultHarness} from "../../harness/BTCVaultHarness.sol";
import {MockTokenizedStrategy} from "../../mock/MockTokenizedStrategy.sol";
import {MockYieldSource} from "../../mock/MockYieldSource.sol";
import {MockERC20} from "../../mock/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {HelperConfig} from "../../../script/HelperConfig.s.sol";

/// @title BaseTestForBTCVault
/// @author Bitmor Protocol
/// @notice Base test contract for BTCVault unit tests with mock infrastructure
/// @dev Sets up `BTCVaultHarness`, `MockTokenizedStrategy`, AccessManager roles, fee configuration, and test accounts.
///      Inherits from `BitmorTestBase` for AccessManager configuration and `VaultUtilities` for ERC-4626 testing helpers.
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

    /// @notice Initial deposit amount used for specific scenario tests (347,933 USDC)
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

    /// @notice Deploys BTCVaultHarness behind ERC1967Proxy
    /// @dev Local helper — harness is test-only so it does not belong in ProxyTestHelper
    /// @param _asset The underlying asset address
    /// @param _manager AccessManager address
    /// @return The BTCVaultHarness instance cast from the proxy address
    function _deployBTCVaultHarnessProxy(address _asset, address _manager) internal returns (BTCVaultHarness) {
        BTCVaultHarness impl = new BTCVaultHarness();
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(impl), abi.encodeCall(BTCVault.initialize, (_asset, _manager, MAX_STRATEGIES)));
        return BTCVaultHarness(address(proxy));
    }

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
        vault = _deployBTCVaultHarnessProxy(address(mockUSDC), address(manager));

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
    /// @dev Delegates to BitmorTestBase._setBTCVaultTargetSelectors which reads from RolesData.sol,
    ///      then patches in test-only selectors not present in production RolesData
    function _setTargetSelectorsLocal() internal {
        _setBTCVaultTargetSelectors(address(vault));

        // Patch: RolesData.getBVM_SLOW_SELECTORS() only includes setFeeRecipient and unpause.
        // Tests also need setEntryFee, setExitFee, and setMaxStrategies under BVM_SLOW.
        bytes4[] memory testOnlySelectors = new bytes4[](3);
        testOnlySelectors[0] = BTCVault.setEntryFee.selector;
        testOnlySelectors[1] = BTCVault.setExitFee.selector;
        testOnlySelectors[2] = BTCVault.setMaxStrategies.selector;
        manager.setTargetFunctionRole(address(vault), testOnlySelectors, BVM_SLOW_ID());
    }

    /// @notice Configure vault with fees using delayed operations
    function _setFeeConfig() internal {
        _scheduleAndExecuteLocal(bvm_slow, BVM_SLOW_ID(), abi.encodeCall(BTCVault.setFeeRecipient, (feeRecipient)));
        _scheduleAndExecuteLocal(
            bvm_slow, BVM_SLOW_ID(), abi.encodeCall(BTCVault.setEntryFee, (networkConfig.entryFee))
        );
        _scheduleAndExecuteLocal(bvm_slow, BVM_SLOW_ID(), abi.encodeCall(BTCVault.setExitFee, (networkConfig.exitFee)));
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
