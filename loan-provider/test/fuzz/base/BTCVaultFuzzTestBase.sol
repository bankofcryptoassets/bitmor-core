// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {FuzzTestBase} from "./FuzzTestBase.sol";
import {VaultUtilities} from "../../unit/Vault/VaultUtilities.t.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";
import {ProxyTestHelper} from "../../helpers/ProxyTestHelper.sol";

import {BTCVault} from "@btcVault/BTCVault.sol";
import {AaveTokenizedStrategy} from "@btcVault/TokenizedStrategy/AaveTokenizedStrategy.sol";
import {MockAToken} from "../../mock/MockAToken.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";

/// @title BTCVaultFuzzTestBase
/// @author Bitmor Protocol
/// @notice Shared base for BTCVault fuzz tests using real vault + real AaveTokenizedStrategy
/// @dev Deploys real BTCVault and AaveTokenizedStrategy backed by MockAaveV3Pool.
///      Inherits FuzzTestBase for bound helpers and VaultUtilities for ERC-4626 helpers.
abstract contract BTCVaultFuzzTestBase is FuzzTestBase, VaultUtilities, ProxyTestHelper {
    // ============ Core Contracts ============

    /// @notice Real BTCVault under test
    BTCVault internal vault;

    /// @notice Primary AaveTokenizedStrategy
    AaveTokenizedStrategy internal strategy1;

    /// @notice Secondary AaveTokenizedStrategy (deployed on demand)
    AaveTokenizedStrategy internal strategy2;

    // ============ Mock Infrastructure ============

    /// @notice Mock aToken for the primary cbBTC reserve
    MockAToken internal mockAToken1;

    // ============ Test Actors ============

    /// @notice Primary depositor
    address internal depositor;

    /// @notice Second depositor for multi-user tests
    address internal depositor2;

    /// @notice Third depositor for multi-user tests
    address internal depositor3;

    /// @notice Fee recipient address
    address internal feeRecipient;

    // ============ Setup ============

    /// @notice Deploys real BTCVault, real AaveTokenizedStrategy, and configures roles
    /// @dev Does NOT call super.setUp() to avoid double-deploying AccessManager and mocks
    function setUp() public virtual override {
        // Create actors BEFORE initializing AccessManager
        depositor = makeAddr("DEPOSITOR");
        depositor2 = makeAddr("DEPOSITOR2");
        depositor3 = makeAddr("DEPOSITOR3");
        feeRecipient = makeAddr("FEE_RECIPIENT");

        // Initialize AccessManager (deploys manager + rolesData + creates role actors)
        _initializeAccessManager(address(this));

        // Deploy mock externals (mockAavePool, mockCbBTC, mockUSDC)
        _deployMockExternals();

        // Deploy mock aToken for cbBTC reserve in the mock Aave pool
        mockAToken1 = new MockAToken("Aave Mock cbBTC 1", "amcbBTC1", 8, address(mockCbBTC), address(mockAavePool));
        mockAavePool.initReserve(address(mockCbBTC), address(mockAToken1));

        // Fund Aave pool with cbBTC liquidity for strategy operations
        mockCbBTC.mint(address(mockAavePool), 10_000e8);

        // Deploy real BTCVault
        vault = _deployBTCVaultProxy(address(mockCbBTC), address(manager));

        // Deploy real AaveTokenizedStrategy (strategy1)
        strategy1 = new AaveTokenizedStrategy(address(mockAavePool), address(vault));

        // Configure roles using BitmorTestBase helpers (NOT manual selectors)
        _setBTCVaultRoles(depositor);
        manager.grantRole(BVD_ID(), depositor2, 0);
        manager.grantRole(BVD_ID(), depositor3, 0);
        _setBTCVaultTargetSelectors(address(vault));

        // Patch: RolesData.getBVM_SLOW_SELECTORS() omits setEntryFee/setExitFee,
        // so we register them manually under BVM_SLOW (matching BaseTestForBTCVault pattern).
        bytes4[] memory feeSelectors = new bytes4[](2);
        feeSelectors[0] = BTCVault.setEntryFee.selector;
        feeSelectors[1] = BTCVault.setExitFee.selector;
        manager.setTargetFunctionRole(address(vault), feeSelectors, BVM_SLOW_ID());

        // Configure vault parameters (fees, max strategies)
        _configureVault();

        // Add strategy1 as the default strategy
        _addDefaultStrategy();
    }

    // ============ Vault Configuration ============

    /// @notice Configures vault with default fees and max strategies via AccessManager
    function _configureVault() internal {
        _scheduleAndExecuteLocal(bvc, BVC_ID(), abi.encodeCall(BTCVault.setMaxStrategies, (FC.MAX_STRATEGIES)));
        _scheduleAndExecuteLocal(bvm_slow, BVM_SLOW_ID(), abi.encodeCall(BTCVault.setFeeRecipient, (feeRecipient)));
        _scheduleAndExecuteLocal(bvm_slow, BVM_SLOW_ID(), abi.encodeCall(BTCVault.setEntryFee, (FC.DEFAULT_ENTRY_FEE)));
        _scheduleAndExecuteLocal(bvm_slow, BVM_SLOW_ID(), abi.encodeCall(BTCVault.setExitFee, (FC.DEFAULT_EXIT_FEE)));
    }

    /// @notice Adds strategy1 with default cap and sets up supply/withdraw queues
    function _addDefaultStrategy() internal {
        _addStrategy(address(strategy1), FC.DEFAULT_STRATEGY_CAP);

        uint256[] memory queue = new uint256[](1);
        queue[0] = 0;
        _updateSupplyQueue(queue);
        _updateWithdrawQueue(queue);
    }

    // ============ Strategy Helpers ============

    /// @notice Deploys a second AaveTokenizedStrategy backed by a separate mock aToken
    /// @return The deployed second strategy
    function _deploySecondStrategy() internal returns (AaveTokenizedStrategy) {
        MockAToken mockAToken2 =
            new MockAToken("Aave Mock cbBTC 2", "amcbBTC2", 8, address(mockCbBTC), address(mockAavePool));
        // Fund the second aToken's pool liquidity
        mockCbBTC.mint(address(mockAavePool), 10_000e8);

        strategy2 = new AaveTokenizedStrategy(address(mockAavePool), address(vault));
        return strategy2;
    }

    /// @notice Adds a strategy to the vault via AccessManager
    /// @param strategy The strategy address to add
    /// @param cap The allocation cap for the strategy
    function _addStrategy(address strategy, uint256 cap) internal {
        _scheduleAndExecuteLocal(bvc, BVC_ID(), abi.encodeCall(BTCVault.addStrategy, (strategy, cap)));
    }

    /// @notice Changes the cap of an existing strategy
    /// @param strategy The strategy address
    /// @param newCap The new allocation cap
    function _changeStrategyCap(address strategy, uint256 newCap) internal {
        _scheduleAndExecuteLocal(bvc, BVC_ID(), abi.encodeCall(BTCVault.changeStrategyCap, (strategy, newCap)));
    }

    // ============ Fee Helpers ============

    /// @notice Sets the entry fee via AccessManager
    /// @param fee The new entry fee in basis points
    function _setEntryFee(uint256 fee) internal {
        _scheduleAndExecuteLocal(bvm_slow, BVM_SLOW_ID(), abi.encodeCall(BTCVault.setEntryFee, (fee)));
    }

    /// @notice Sets the exit fee via AccessManager
    /// @param fee The new exit fee in basis points
    function _setExitFee(uint256 fee) internal {
        _scheduleAndExecuteLocal(bvm_slow, BVM_SLOW_ID(), abi.encodeCall(BTCVault.setExitFee, (fee)));
    }

    // ============ Deposit/Mint Helpers ============

    /// @notice Funds a depositor with cbBTC, approves the vault, and deposits
    /// @param user The depositor address
    /// @param assets The amount of cbBTC to deposit
    /// @return shares The number of shares minted
    function _depositToVault(address user, uint256 assets) internal returns (uint256 shares) {
        _fundCbBTCAndApprove(user, address(vault), assets);
        vm.prank(user);
        shares = vault.deposit(assets, user);
    }

    /// @notice Funds a depositor with cbBTC, approves the vault, and mints exact shares
    /// @param user The depositor address
    /// @param sharesToMint The number of shares to mint
    /// @return assets The amount of cbBTC consumed
    function _mintFromVault(address user, uint256 sharesToMint) internal returns (uint256 assets) {
        uint256 assetsNeeded = vault.previewMint(sharesToMint);
        _fundCbBTCAndApprove(user, address(vault), assetsNeeded);
        vm.prank(user);
        assets = vault.mint(sharesToMint, user);
    }

    // ============ Yield Simulation ============

    /// @notice Simulates yield by minting aTokens to strategy1 and backing cbBTC to pool
    /// @dev Increases strategy1.totalAssets() without new deposits, simulating Aave yield accrual
    /// @param yieldAmount The amount of yield to simulate (in cbBTC, 8 decimals)
    function _simulateYield(uint256 yieldAmount) internal {
        // Back the yield with real cbBTC in the pool (so withdrawals work later)
        mockCbBTC.mint(address(mockAavePool), yieldAmount);
        // Mint aTokens to strategy1 (must come from pool due to MockAToken restriction)
        vm.prank(address(mockAavePool));
        mockAToken1.mint(address(strategy1), yieldAmount);
    }

    // ============ Queue Helpers ============

    /// @notice Updates the supply queue via AccessManager
    /// @param newQueue The new supply queue array
    function _updateSupplyQueue(uint256[] memory newQueue) internal {
        _scheduleAndExecuteLocal(bva_slow, BVA_SLOW_ID(), abi.encodeCall(BTCVault.updateSupplyQueue, (newQueue)));
    }

    /// @notice Updates the withdraw queue via AccessManager
    /// @param newQueue The new withdraw queue array
    function _updateWithdrawQueue(uint256[] memory newQueue) internal {
        _scheduleAndExecuteLocal(bva_slow, BVA_SLOW_ID(), abi.encodeCall(BTCVault.updateWithdrawQueue, (newQueue)));
    }

    // ============ Reallocation Helpers ============

    /// @notice Reallocates funds across strategies via AccessManager
    /// @param allocations The reallocation instructions
    function _reallocate(DataTypes.Allocation[] memory allocations) internal {
        vm.prank(bva_fast);
        manager.execute(address(vault), abi.encodeCall(BTCVault.reallocateFunds, (allocations)));
    }

    // ============ Bound Helpers ============

    /// @notice Bounds a raw fuzz input to a valid fee in basis points
    /// @param raw The raw fuzzed input
    /// @return The bounded fee value (0 - 1000 bps)
    function _boundFee(uint256 raw) internal pure returns (uint256) {
        return bound(raw, FC.MIN_FEE_BPS, FC.MAX_FEE_BPS);
    }

    /// @notice Bounds a raw fuzz input to a valid strategy cap
    /// @param raw The raw fuzzed input
    /// @return The bounded cap value (1 sat - 10,000 BTC)
    function _boundCap(uint256 raw) internal pure returns (uint256) {
        return bound(raw, 1, 10_000e8);
    }

    // ============ Actor Selection ============

    /// @notice Selects one of three depositors based on a seed
    /// @param seed The fuzz seed for selection
    /// @return The selected depositor address
    function _selectActor(uint256 seed) internal view returns (address) {
        uint256 idx = seed % 3;
        if (idx == 0) return depositor;
        if (idx == 1) return depositor2;
        return depositor3;
    }

    // ============ AccessManager Helpers ============

    /// @notice Schedules and executes a delayed operation targeting the vault
    /// @param caller The address performing the operation
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
}
