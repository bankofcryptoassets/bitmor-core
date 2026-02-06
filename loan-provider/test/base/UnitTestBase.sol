// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BitmorTestBase} from "./BitmorTestBase.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";

// Mock externals
import {MockAaveV3Pool} from "../mock/MockAaveV3Pool.sol";
import {MockERC20} from "../mock/MockERC20.sol";

/// @title UnitTestBase
/// @author Bitmor Protocol
/// @notice Tier 1 test base providing mock tokens, mock Aave V3, and common test actors
/// @dev Inherits BitmorTestBase (Tier 0) and adds mock externals for unit testing without a fork
abstract contract UnitTestBase is BitmorTestBase {
    // ============ Configuration ============

    /// @notice Helper config for network-specific addresses and protocol parameters
    HelperConfig public config;

    // ============ Mock Externals ============

    /// @notice Mock Aave V3 pool for flash loan testing
    MockAaveV3Pool public mockAavePool;

    /// @notice Mock cbBTC token (8 decimals)
    MockERC20 public mockCbBTC;

    /// @notice Mock USDC token (6 decimals)
    MockERC20 public mockUSDC;

    // ============ Test Actors ============

    /// @notice Admin address for deployments and role grants
    address public admin;

    /// @notice Standard test user for loan operations
    address public testUser;

    /// @notice Test liquidator for liquidation scenarios
    address public testLiquidator;

    // ============ Snapshot ============

    /// @dev Snapshot ID for reverting state between tests
    uint256 internal _baseSnapshotId;

    function setUp() public virtual override {
        admin = makeAddr("admin");
        testUser = makeAddr("testUser");
        testLiquidator = makeAddr("testLiquidator");

        _initializeAccessManager(admin);

        config = new HelperConfig();

        vm.startPrank(admin);
        _deployMockExternals();
        vm.stopPrank();

        _baseSnapshotId = vm.snapshot();
    }

    /// @notice Deploys mock external protocols (Aave V3, tokens)
    function _deployMockExternals() internal virtual {
        mockAavePool = new MockAaveV3Pool();
        mockCbBTC = new MockERC20("Coinbase BTC", "cbBTC", 8);
        mockUSDC = new MockERC20("USD Coin", "USDC", 6);

        // Fund mock Aave pool for flash loans
        mockUSDC.mint(address(mockAavePool), TC.POOL_USDC_LIQUIDITY);
    }

    // ============ Token Helpers ============

    /// @notice Mints mock cbBTC to `to`
    /// @param to Recipient address
    /// @param amount Amount of cbBTC to mint (8 decimals)
    function _fundCbBTC(address to, uint256 amount) internal {
        mockCbBTC.mint(to, amount);
    }

    /// @notice Mints mock USDC to `to`
    /// @param to Recipient address
    /// @param amount Amount of USDC to mint (6 decimals)
    function _fundUSDC(address to, uint256 amount) internal {
        mockUSDC.mint(to, amount);
    }

    /// @notice Mints mock USDC to `to` and approves `spender` for `amount`
    /// @param to Recipient address
    /// @param spender Address to approve for spending
    /// @param amount Amount of USDC to mint and approve (6 decimals)
    function _fundUSDCAndApprove(address to, address spender, uint256 amount) internal {
        mockUSDC.mint(to, amount);
        vm.prank(to);
        mockUSDC.approve(spender, amount);
    }

    /// @notice Mints mock cbBTC to `to` and approves `spender` for `amount`
    /// @param to Recipient address
    /// @param spender Address to approve for spending
    /// @param amount Amount of cbBTC to mint and approve (8 decimals)
    function _fundCbBTCAndApprove(address to, address spender, uint256 amount) internal {
        mockCbBTC.mint(to, amount);
        vm.prank(to);
        mockCbBTC.approve(spender, amount);
    }

    // ============ State Management ============

    /// @notice Reverts to base snapshot and re-snapshots for test isolation
    function _resetState() internal {
        vm.revertTo(_baseSnapshotId);
        _baseSnapshotId = vm.snapshot();
    }
}
