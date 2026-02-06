// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BitmorTestBase} from "./BitmorTestBase.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Loan} from "@bitmor/protocol/Loan.sol";
import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

/// @title IntegrationTestBase
/// @author Bitmor Protocol
/// @notice Base contract for integration tests using pre-deployed contracts
/// @dev Reads all addresses from deployments.json - requires make deploy-local first
abstract contract IntegrationTestBase is BitmorTestBase {
    // ============ Configuration ============

    /// @notice Helper config for reading deployed addresses
    HelperConfig public config;

    // ============ Pre-deployed Contracts ============

    /// @notice Pre-deployed Loan contract
    Loan public loanContract;

    /// @notice Pre-deployed Bitmor pool
    address public bitmorPool;

    /// @notice Pre-deployed addresses provider
    address public addressesProvider;

    // ============ Tokens ============

    /// @notice cbBTC token
    IERC20 public cbBTC;

    /// @notice USDC token
    IERC20 public usdc;

    // ============ Test Actors ============

    /// @notice Admin address loaded from deployment config (`BITMOR_OWNER`)
    address public admin;

    /// @notice Standard test user for loan operations
    address public testUser;

    /// @notice Test liquidator for liquidation scenarios
    address public testLiquidator;

    // ============ Snapshot ============

    uint256 internal _baseSnapshotId;

    // ============ Setup ============

    /// @notice Sets up integration test environment from pre-deployed contracts
    function setUp() public virtual override {
        // 1. Load configuration first (needed to get AccessManager)
        config = new HelperConfig();

        // 2. Load pre-deployed AccessManager (don't deploy new one)
        manager = BitmorAccessManager(config.getAccessManager());

        // 3. Create test actors
        admin = config.BITMOR_OWNER();
        testUser = makeAddr("testUser");
        testLiquidator = makeAddr("testLiquidator");

        // 4. Load all pre-deployed contracts
        _loadDeployedContracts();

        // 5. Snapshot
        _baseSnapshotId = vm.snapshot();
    }

    /// @notice Don't initialize a new AccessManager - use pre-deployed one
    function _initializeAccessManager(address) internal override {
        // Intentionally empty - we use the pre-deployed manager
    }

    // ============ Contract Loading ============

    /// @notice Loads all pre-deployed contract addresses
    function _loadDeployedContracts() internal virtual {
        // Core contracts
        loanContract = Loan(config.getLoan());
        bitmorPool = config.getBitmorPool();
        addressesProvider = config.getAddressesProvider();

        // Tokens
        cbBTC = IERC20(config.getCbBTC());
        usdc = IERC20(config.getUSDC());
    }

    // ============ State Management ============

    /// @notice Reverts to base snapshot
    function _resetState() internal {
        vm.revertTo(_baseSnapshotId);
        _baseSnapshotId = vm.snapshot();
    }
}
