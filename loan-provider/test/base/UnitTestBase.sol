// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BitmorTestBase} from "./BitmorTestBase.sol";
import {MockAaveV3Pool} from "../mock/MockAaveV3Pool.sol";
import {MockERC20} from "../mock/MockERC20.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

/// @title UnitTestBase
/// @author Bitmor Protocol
/// @notice Base contract for unit tests using mocks instead of real protocols
/// @dev Deploys fresh mock contracts for each test, optionally deploys lending-pool via FFI
abstract contract UnitTestBase is BitmorTestBase {
    // ============ Mock Contracts ============

    /// @notice Mock Aave V3 pool for flash loans
    MockAaveV3Pool public mockAavePool;

    /// @notice Mock cbBTC token (8 decimals)
    MockERC20 public mockCbBTC;

    /// @notice Mock USDC token (6 decimals)
    MockERC20 public mockUSDC;

    // ============ Test Actors ============

    /// @notice Admin address for deployments and configuration
    address public admin;

    /// @notice Test user for loan operations
    address public testUser;

    /// @notice Test liquidator for liquidation tests
    address public testLiquidator;

    // ============ Protocol Addresses (from lending-pool) ============

    /// @notice Bitmor lending pool address (deployed via FFI or loaded from JSON)
    address public bitmorPool;

    /// @notice Lending pool addresses provider
    address public addressesProvider;

    // ============ Configuration ============

    /// @notice Helper config for reading deployed addresses
    HelperConfig public config;

    /// @notice Whether to deploy lending-pool via FFI (expensive, disabled by default)
    bool public deployLendingPoolViaFFI = false;

    // ============ Snapshot ============

    /// @notice Snapshot ID for reverting state between tests
    uint256 internal _baseSnapshotId;

    // ============ Setup ============

    /// @notice Sets up the unit test environment
    /// @dev Order: actors -> config -> mocks -> (optional FFI) -> roles
    function setUp() public virtual override {
        // 1. Create test actors
        admin = makeAddr("admin");
        testUser = makeAddr("testUser");
        testLiquidator = makeAddr("testLiquidator");

        // 2. Initialize AccessManager through BitmorTestBase
        _initializeAccessManager(admin);

        // 3. Load configuration
        config = new HelperConfig();

        // 4. Deploy mock external protocols
        vm.startPrank(admin);
        _deployMockExternals();
        vm.stopPrank();

        // 5. Optionally deploy lending-pool via FFI
        if (deployLendingPoolViaFFI) {
            _deployLendingPoolViaFFI();
            _loadLendingPoolAddresses();
        }

        // 6. Snapshot for test isolation
        _baseSnapshotId = vm.snapshot();
    }

    // ============ Mock Deployment ============

    /// @notice Deploys mock external protocols (Aave, tokens)
    /// @dev Called during setUp, can be overridden for custom mocks
    function _deployMockExternals() internal virtual {
        // Deploy mock Aave V3 pool
        mockAavePool = new MockAaveV3Pool();

        // Deploy mock tokens
        mockCbBTC = new MockERC20("Coinbase Wrapped BTC", "cbBTC", 8);
        mockUSDC = new MockERC20("USD Coin", "USDC", 6);

        // Fund mock Aave pool with USDC for flash loans
        uint256 flashLoanLiquidity = 10_000_000e6; // 10M USDC
        mockUSDC.mint(address(mockAavePool), flashLoanLiquidity);
    }

    // ============ FFI Deployment ============

    /// @notice Deploys lending-pool via FFI to Hardhat
    /// @dev Requires Anvil running on localhost:8545
    function _deployLendingPoolViaFFI() internal {
        string[] memory cmd = new string[](5);
        cmd[0] = "npm";
        cmd[1] = "run";
        cmd[2] = "bitmor:localhost:dev:migration";
        cmd[3] = "--prefix";
        cmd[4] = "../lending-pool";

        vm.ffi(cmd);
    }

    /// @notice Loads lending-pool addresses from deployed-contracts.json
    function _loadLendingPoolAddresses() internal {
        bitmorPool = config.getBitmorPool();
        addressesProvider = config.getAddressesProvider();
    }

    // ============ State Management ============

    /// @notice Reverts to base snapshot and re-snapshots for test isolation
    function _resetState() internal {
        vm.revertTo(_baseSnapshotId);
        _baseSnapshotId = vm.snapshot();
    }

    // ============ Token Helpers ============

    /// @notice Funds an address with mock cbBTC
    /// @param to Recipient address
    /// @param amount Amount to mint (8 decimals)
    function _fundCbBTC(address to, uint256 amount) internal {
        mockCbBTC.mint(to, amount);
    }

    /// @notice Funds an address with mock USDC
    /// @param to Recipient address
    /// @param amount Amount to mint (6 decimals)
    function _fundUSDC(address to, uint256 amount) internal {
        mockUSDC.mint(to, amount);
    }

    /// @notice Funds an address with USDC and approves a spender
    /// @param to Recipient address
    /// @param spender Address to approve
    /// @param amount Amount to mint and approve
    function _fundUSDCAndApprove(address to, address spender, uint256 amount) internal {
        mockUSDC.mint(to, amount);
        vm.prank(to);
        mockUSDC.approve(spender, amount);
    }
}
