// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BitmorTestBase} from "./BitmorTestBase.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";

// Mock externals
import {MockAaveV3Pool} from "../mock/MockAaveV3Pool.sol";
import {MockERC20} from "../mock/MockERC20.sol";

/// @title UnitTestBase
/// @notice Base contract for unit tests with mocks and fresh lending-pool deployment
/// @dev Deploys mock tokens, mock Aave V3, and prepares for lending-pool integration
abstract contract UnitTestBase is BitmorTestBase {
    // ============ Configuration ============
    HelperConfig public config;

    // ============ Mock Externals ============
    MockAaveV3Pool public mockAavePool;
    MockERC20 public mockCbBTC;
    MockERC20 public mockUSDC;

    // ============ Test Actors ============
    address public admin;
    address public testUser;
    address public testLiquidator;

    // ============ Snapshot ============
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

    /// @notice Funds an address with mock cbBTC
    function _fundCbBTC(address to, uint256 amount) internal {
        mockCbBTC.mint(to, amount);
    }

    /// @notice Funds an address with mock USDC
    function _fundUSDC(address to, uint256 amount) internal {
        mockUSDC.mint(to, amount);
    }

    /// @notice Funds an address with USDC and approves a spender
    function _fundUSDCAndApprove(address to, address spender, uint256 amount) internal {
        mockUSDC.mint(to, amount);
        vm.prank(to);
        mockUSDC.approve(spender, amount);
    }

    /// @notice Funds an address with cbBTC and approves a spender
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
