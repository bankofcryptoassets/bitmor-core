// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {AccessManager} from "@openzeppelin/access/manager/AccessManager.sol";

import {VaultUtilities} from "./VaultUtilities.t.sol";
import {BTCVault, BTCVaultHarness} from "../../harness/BTCVaultHarness.sol";
import {MockTokenizedStrategy} from "../../mock/MockTokenizedStrategy.sol";
import {MockYieldSource} from "../../mock/MockYieldSource.sol";

import {HelperConfig} from "../../../script/HelperConfig.s.sol";

/// @title BaseTestForBTCVault
/// @notice Comprehensive test suite for BTCVault functionality
/// @dev Tests vault operations, fee calculations, and strategy integration using mainnet fork.
///      Inherits from VaultUtilities for generic ERC-4626 testing helpers.
/// @author Bitmor Protocol
contract BaseTestForBTCVault is VaultUtilities {
    using SafeTransferLib for address;

    /// @notice SimpleVault contract instance under test
    BTCVaultHarness vault;

    /// @notice SimpleStrategy contract instance for yield generation
    MockTokenizedStrategy strategy;

    MockYieldSource yieldSource;

    /// @notice Network configuration containing protocol addresses
    HelperConfig.NetworkConfig networkConfig;

    /// @notice Address that receives vault fees
    address feeRecipient;

    /// @notice Test user address for vault operations
    address user;

    AccessManager manager;

    uint64 bvm_slow_id = 110;
    uint32 bvm_slow_expected_delay = 1 days;
    uint64 bvm_fast_id = 11;
    uint64 bvc_id = 12;
    uint32 bvc_expected_delay = 1 days;
    uint64 bva_fast_id = 13;
    uint64 bva_slow_id = 130;
    uint32 bva_slow_expected_delay = 1 days;
    uint64 bvd_id = 14;

    address bvm_slow;
    address bvm_fast;
    address bvc;
    address bva_slow;
    address bva_fast;
    address bvd;

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
    /// @dev Creates fresh contracts and configures them with network-specific addresses
    function setUp() public virtual {
        HelperConfig config = new HelperConfig();
        networkConfig = config.getNetworkConfig();

        address initial_admin = address(this);

        manager = new AccessManager(initial_admin);

        // Deploy vault and strategy contracts
        vault = new BTCVaultHarness(networkConfig.usdc, address(manager));

        yieldSource = new MockYieldSource();

        strategy = new MockTokenizedStrategy(address(yieldSource), address(vault));

        // Create test addresses
        feeRecipient = makeAddr("FEE_RECIPIENT");
        bvm_slow = makeAddr("BVM_SLOW");
        bvm_fast = makeAddr("BVM_FAST");
        bvd = makeAddr("BVD");
        bvc = makeAddr("BVC");
        bva_fast = makeAddr("BVA_SLOW");
        bva_slow = makeAddr("BVA_FAST");

        _setRoles();

        _setTargetSelectors();

        _setFeeConfig();

        _transferUSDC();

        _setMaxStrategies();
    }

    function _setRoles() internal {
        manager.grantRole(bvm_fast_id, bvm_fast, 0);
        manager.grantRole(bvm_slow_id, bvm_slow, bvm_slow_expected_delay);
        manager.grantRole(bvc_id, bvc, bvc_expected_delay);
        manager.grantRole(bva_slow_id, bva_slow, bva_slow_expected_delay);
        manager.grantRole(bva_fast_id, bva_fast, 0);
        manager.grantRole(bvd_id, bvd, 0);
        manager.grantRole(bvd_id, user, 0);
    }

    function _setTargetSelectors() internal {
        address target = address(vault);

        bytes4[] memory bvm_slow_selectors = new bytes4[](5);
        bvm_slow_selectors[0] = BTCVault.setFeeRecipient.selector;
        bvm_slow_selectors[1] = BTCVault.setEntryFee.selector;
        bvm_slow_selectors[2] = BTCVault.setExitFee.selector;
        bvm_slow_selectors[3] = BTCVault.setMaxStrategies.selector;
        bvm_slow_selectors[4] = BTCVault.unpause.selector;
        manager.setTargetFunctionRole(target, bvm_slow_selectors, bvm_slow_id);

        bytes4[] memory bvm_fast_selectors = new bytes4[](1);
        bvm_fast_selectors[0] = BTCVault.pause.selector;
        manager.setTargetFunctionRole(target, bvm_fast_selectors, bvm_fast_id);

        bytes4[] memory bvc_selectors = new bytes4[](2);
        bvc_selectors[0] = BTCVault.addStrategy.selector;
        bvc_selectors[1] = BTCVault.changeStrategyCap.selector;
        manager.setTargetFunctionRole(target, bvc_selectors, bvc_id);

        bytes4[] memory bva_slow_selectors = new bytes4[](2);
        bva_slow_selectors[0] = BTCVault.updateSupplyQueue.selector;
        bva_slow_selectors[1] = BTCVault.updateWithdrawQueue.selector;
        manager.setTargetFunctionRole(target, bva_slow_selectors, bva_slow_id);

        bytes4[] memory bva_fast_selectors = new bytes4[](1);
        bva_fast_selectors[0] = BTCVault.reallocateFunds.selector;
        manager.setTargetFunctionRole(target, bva_fast_selectors, bva_fast_id);

        bytes4[] memory bvd_selectors = new bytes4[](1);
        bvd_selectors[0] = BTCVault.deposit.selector;
        manager.setTargetFunctionRole(target, bvd_selectors, bvd_id);
    }

    /**
     * @notice Configure vault with fees
     */
    function _setFeeConfig() internal {
        _scheduleAndExecute(bvm_slow, bvm_slow_id, abi.encodeCall(BTCVault.setEntryFee, (networkConfig.entryFee)));
        _scheduleAndExecute(bvm_slow, bvm_slow_id, abi.encodeCall(BTCVault.setExitFee, (networkConfig.exitFee)));
        _scheduleAndExecute(bvm_slow, bvm_slow_id, abi.encodeCall(BTCVault.setFeeRecipient, (feeRecipient)));
    }

    function _transferUSDC() internal {
        vm.startPrank(networkConfig.usdc_holder);
        (networkConfig.usdc).safeTransfer(user, USDC_TO_MINT);
        (networkConfig.usdc).safeTransfer(address(this), USDC_TO_MINT);
        vm.stopPrank();
    }

    function _setMaxStrategies() internal {
        _scheduleAndExecute(bvm_slow, bvm_slow_id, abi.encodeCall(BTCVault.setMaxStrategies, (MAX_STRATEGIES)));
    }

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
}
