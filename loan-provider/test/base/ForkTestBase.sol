// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BitmorTestBase} from "./BitmorTestBase.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

/// @title ForkTestBase
/// @author Bitmor Protocol
/// @notice Base contract for fork tests using real Aave V3 from forked network
/// @dev Deploys fresh Bitmor contracts against real external protocols
abstract contract ForkTestBase is BitmorTestBase {
    // ============ Configuration ============

    /// @notice Helper config for network-specific addresses
    HelperConfig public config;

    // ============ External Protocol Addresses ============

    /// @notice Real Aave V3 pool from forked network
    address public aaveV3Pool;

    /// @notice Aave V3 addresses provider
    address public aaveAddressesProvider;

    // ============ Real Tokens ============

    /// @notice Real cbBTC from forked network
    IERC20 public cbBTC;

    /// @notice Real USDC from forked network
    IERC20 public usdc;

    // ============ Test Actors ============

    /// @notice Admin address for deployments
    address public admin;

    /// @notice Test user for operations
    address public testUser;

    /// @notice Test liquidator
    address public testLiquidator;

    // ============ Bitmor Protocol (deployed fresh) ============

    /// @notice Bitmor lending pool (deployed via FFI)
    address public bitmorPool;

    /// @notice Lending pool addresses provider
    address public addressesProvider;

    // ============ Snapshot ============

    uint256 internal _baseSnapshotId;

    // ============ Setup ============

    /// @notice Sets up fork test environment
    /// @dev Loads real external protocols, deploys fresh Bitmor via FFI
    function setUp() public virtual override {
        // 1. Create test actors
        admin = makeAddr("admin");
        testUser = makeAddr("testUser");
        testLiquidator = makeAddr("testLiquidator");

        // 2. Initialize AccessManager
        _initializeAccessManager(admin);

        // 3. Load configuration
        config = new HelperConfig();

        // 4. Load external protocol addresses (real from fork)
        _loadExternalProtocols();

        // 5. Deploy lending-pool via FFI
        _deployLendingPoolViaFFI();
        _loadLendingPoolAddresses();

        // 6. Snapshot
        _baseSnapshotId = vm.snapshot();
    }

    // ============ External Protocol Loading ============

    /// @notice Loads real external protocol addresses from fork
    function _loadExternalProtocols() internal virtual {
        // Real Aave V3 from fork (only available on mainnet)
        if (block.chainid != 31337) {
            aaveV3Pool = config.getAaveV3Pool();
            aaveAddressesProvider = config.getAaveAddressesProvider();
        }

        // Real tokens from config
        cbBTC = IERC20(config.getCbBTC());
        usdc = IERC20(config.getUSDC());
    }

    // ============ FFI Deployment ============

    /// @notice Deploys lending-pool via FFI
    function _deployLendingPoolViaFFI() internal {
        string[] memory cmd = new string[](5);
        cmd[0] = "npm";
        cmd[1] = "run";
        cmd[2] = "bitmor:localhost:dev:migration";
        cmd[3] = "--prefix";
        cmd[4] = "../lending-pool";

        vm.ffi(cmd);
    }

    /// @notice Loads lending-pool addresses after FFI deployment
    function _loadLendingPoolAddresses() internal {
        bitmorPool = config.getBitmorPool();
        addressesProvider = config.getAddressesProvider();
    }

    // ============ State Management ============

    /// @notice Reverts to base snapshot
    function _resetState() internal {
        vm.revertTo(_baseSnapshotId);
        _baseSnapshotId = vm.snapshot();
    }

    // ============ Token Helpers ============

    /// @notice Deal real tokens to an address (fork only)
    /// @param token Token address
    /// @param to Recipient
    /// @param amount Amount to deal
    function _dealToken(address token, address to, uint256 amount) internal {
        deal(token, to, amount);
    }
}
