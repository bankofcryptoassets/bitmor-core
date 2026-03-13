// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {FuzzTestBase} from "./FuzzTestBase.sol";
import {VaultUtilities} from "../../unit/Vault/VaultUtilities.t.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";
import {ProxyTestHelper} from "../../helpers/ProxyTestHelper.sol";

import {USDCVault} from "@bitmor/vaults/usdc-vault/USDCVault.sol";
import {USDCStrategy} from "@bitmor/vaults/usdc-vault/USDCStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {MockBitmorLendingPool} from "../../mock/MockBitmorLendingPool.sol";
import {MockAddressesProvider} from "../../mock/MockAddressesProvider.sol";
import {MockPriceOracle} from "../../mock/MockPriceOracle.sol";
import {MockAToken} from "../../mock/MockAToken.sol";
import {MockVariableDebtToken} from "../../mock/MockVariableDebtToken.sol";

/**
 * @title USDCVaultFuzzTestBase
 * @author Bitmor Protocol
 * @notice Shared base contract for USDC vault+strategy fuzz tests using real contracts with mock pools
 * @dev Deploys real `USDCVault` and `USDCStrategy` backed by `MockAaveV3Pool` and `MockBitmorLendingPool`.
 *      Inherits `FuzzTestBase` for bound helpers and `VaultUtilities` for ERC-4626 operation helpers.
 */
abstract contract USDCVaultFuzzTestBase is FuzzTestBase, VaultUtilities, ProxyTestHelper {
    // ============ Core Contracts ============

    /// @notice Real USDCVault contract under test
    USDCVault internal vault;

    /// @notice Real USDCStrategy contract under test
    USDCStrategy internal strategy;

    // ============ Mock Infrastructure ============

    /// @notice Mock Bitmor Lending Pool
    MockBitmorLendingPool internal mockBitmorPool;

    /// @notice Mock addresses provider
    MockAddressesProvider internal mockAddressesProvider;

    /// @notice Mock price oracle
    MockPriceOracle internal mockOracle;

    /// @notice Mock aToken for Aave USDC deposits
    MockAToken internal mockAaveAToken;

    /// @notice Mock aToken for Bitmor Lending Pool USDC deposits
    MockAToken internal mockBitmorAToken;

    /// @notice Mock variable debt token for BLP
    MockVariableDebtToken internal mockBitmorDebtToken;

    // ============ Test Actors ============

    /// @notice Primary depositor for fuzz tests
    address internal depositor;

    /// @notice Secondary depositor for multi-user tests
    address internal depositor2;

    /// @notice Tertiary depositor for multi-user tests
    address internal depositor3;

    // ============ Constants ============

    /// @notice Basis points denominator (10,000 = 100%)
    uint256 internal constant BASIS_POINTS = 10_000;

    /// @notice Default allocation tolerance for assertions (2%)
    uint256 internal constant DEFAULT_TOLERANCE_BPS = 200;

    // ============ Snapshot Struct ============

    /// @dev Snapshot of vault state at a point in time
    struct VaultSnapshot {
        uint256 totalAssets;
        uint256 totalSupply;
        uint256 sharePrice;
        uint256 aaveBalance;
        uint256 blpBalance;
    }

    // ============ Setup ============

    function setUp() public virtual override {
        // Create test actors
        depositor = makeAddr("DEPOSITOR");
        depositor2 = makeAddr("DEPOSITOR2");
        depositor3 = makeAddr("DEPOSITOR3");

        // Initialize AccessManager (from BitmorTestBase via UnitTestBase via FuzzTestBase)
        _initializeAccessManager(address(this));

        // Deploy base mock externals (mockAavePool, mockUSDC, mockCbBTC) from UnitTestBase
        _deployMockExternals();

        // Deploy strategy-specific mock infrastructure (extends what UnitTestBase provides)
        _deployStrategyMockInfrastructure();

        // Deploy real vault and strategy
        vault = _deployUSDCVaultProxy(address(manager), address(mockUSDC), address(mockBitmorPool));
        strategy = new USDCStrategy(address(vault), address(mockAavePool), address(mockBitmorPool));

        // Configure roles and permissions
        _setUSDCVaultRoles();
        _setTargetSelectorsLocal();

        // Set strategy on vault and configure default 80% allocation
        _setStrategyOnVault();
    }

    // ============ Internal Setup Helpers ============

    /// @notice Deploys mock infrastructure for strategy tests
    /// @dev Builds on top of UnitTestBase's mockAavePool and mockUSDC
    function _deployStrategyMockInfrastructure() internal {
        // UnitTestBase already deploys mockAavePool, mockUSDC, mockCbBTC
        // We need to deploy the remaining mocks for the strategy

        // Deploy mock oracle
        mockOracle = new MockPriceOracle(address(0), address(0));
        mockOracle.setAssetPrice(address(mockUSDC), 1e8);

        // Deploy mock addresses provider
        mockAddressesProvider = new MockAddressesProvider(address(0), address(mockOracle), address(this));

        // Deploy mock Bitmor lending pool
        mockBitmorPool = new MockBitmorLendingPool(address(mockAddressesProvider));
        mockAddressesProvider.setLendingPool(address(mockBitmorPool));

        // Deploy mock aToken and debt token for Bitmor pool
        mockBitmorAToken = new MockAToken("Bitmor Mock USDC", "bmUSDC", 6, address(mockUSDC), address(mockBitmorPool));
        mockBitmorDebtToken =
            new MockVariableDebtToken("Bitmor Mock USDC Debt", "vdUSDC", 6, address(mockUSDC), address(mockBitmorPool));
        mockBitmorPool.initReserve(address(mockUSDC), address(mockBitmorAToken), address(mockBitmorDebtToken));

        // Deploy mock aToken for Aave and initialize reserve
        mockAaveAToken = new MockAToken("Aave Mock USDC", "amUSDC", 6, address(mockUSDC), address(mockAavePool));
        mockAavePool.initReserve(address(mockUSDC), address(mockAaveAToken));

        // Fund pools with liquidity
        mockUSDC.mint(address(mockBitmorPool), FC.POOL_LIQUIDITY);
        mockUSDC.mint(address(mockAavePool), FC.POOL_LIQUIDITY);
    }

    /// @notice Sets function permissions for USDC vault roles
    /// @dev Delegates to BitmorTestBase._setUSDCVaultTargetSelectors which reads from RolesData.sol
    function _setTargetSelectorsLocal() internal {
        _setUSDCVaultTargetSelectors(address(vault));

        // Grant UVA role to BLP for reallocateAssets(uint256)
        manager.grantRole(UVA_ID(), address(mockBitmorPool), 0);
    }

    /// @notice Sets the strategy on the vault and configures default allocation
    function _setStrategyOnVault() internal {
        _scheduleAndExecuteLocal(uvc, UVC_ID(), abi.encodeCall(USDCVault.setStrategy, (address(strategy))));

        // Set default 80% Aave allocation
        vm.prank(address(vault));
        strategy.updateExternalAllocation(FC.DEFAULT_AAVE_ALLOCATION_BPS);
    }

    // ============ Bound Helpers ============

    /// @notice Bounds raw input to valid allocation range [0, 10000]
    function _boundAllocationBps(uint256 raw) internal pure returns (uint256) {
        return bound(raw, FC.MIN_ALLOCATION_BPS, FC.MAX_ALLOCATION_BPS);
    }

    /// @notice Bounds raw input to valid min delta threshold range
    function _boundMinDelta(uint256 raw) internal pure returns (uint256) {
        return bound(raw, FC.MIN_DELTA_THRESHOLD_BPS, FC.MAX_DELTA_THRESHOLD_BPS);
    }

    // ============ Deposit Helpers ============

    /// @notice Funds a depositor with USDC, approves vault, and deposits
    /// @param who The depositor address
    /// @param amount The amount of USDC to deposit
    /// @return shares The number of vault shares minted
    function _depositToVault(address who, uint256 amount) internal returns (uint256 shares) {
        _fundUSDCAndApprove(who, address(vault), amount);
        vm.prank(who);
        shares = vault.deposit(amount, who);
    }

    // ============ Balance Query Helpers ============

    /// @notice Returns strategy's Aave aToken balance
    function _getAaveBalance() internal view returns (uint256) {
        return mockAaveAToken.balanceOf(address(strategy));
    }

    /// @notice Returns strategy's BLP aToken balance
    function _getBLPBalance() internal view returns (uint256) {
        return mockBitmorAToken.balanceOf(address(strategy));
    }

    /// @notice Returns total balance across Aave + BLP
    function _getTotalBalance() internal view returns (uint256) {
        return _getAaveBalance() + _getBLPBalance();
    }

    // ============ Allocation Helpers ============

    /// @notice Sets the external allocation on the strategy (pranks as vault)
    function _setAllocation(uint256 allocationBps) internal {
        vm.prank(address(vault));
        strategy.updateExternalAllocation(allocationBps);
    }

    /// @notice Triggers reallocation via UVA role through AccessManager
    function _rebalance() internal {
        _scheduleAndExecuteLocal(uva, UVA_ID(), abi.encodeWithSignature("reallocateAssets()"));
    }

    // ============ Assertion Helpers ============

    /// @notice Asserts allocation is within tolerance of target
    /// @param targetAaveAllocationBps Target Aave allocation in bps
    /// @param toleranceBps Tolerance in basis points
    function _assertAllocationCorrect(uint256 targetAaveAllocationBps, uint256 toleranceBps) internal view {
        uint256 aaveBalance = _getAaveBalance();
        uint256 totalBalance = _getTotalBalance();

        if (totalBalance == 0) return;

        uint256 actualAaveAllocationBps = (aaveBalance * BASIS_POINTS) / totalBalance;
        uint256 delta = actualAaveAllocationBps > targetAaveAllocationBps
            ? actualAaveAllocationBps - targetAaveAllocationBps
            : targetAaveAllocationBps - actualAaveAllocationBps;

        assertLe(delta, toleranceBps, "Allocation outside tolerance");
    }

    // ============ Schedule/Execute Helpers ============

    /// @notice Schedule and execute a delayed operation targeting the vault
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

    /// @notice Schedule an operation and expect it to revert
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

    // ============ Snapshot Helpers ============

    /// @notice Captures current vault state
    function _captureVaultSnapshot() internal view returns (VaultSnapshot memory snap) {
        snap.totalAssets = vault.totalAssets();
        snap.totalSupply = vault.totalSupply();
        snap.sharePrice = snap.totalSupply == 0 ? 1e18 : (snap.totalAssets * 1e18) / snap.totalSupply;
        snap.aaveBalance = _getAaveBalance();
        snap.blpBalance = _getBLPBalance();
    }

    // ============ Pause Helpers ============

    /// @notice Pauses the vault via UVM_FAST role
    function _pauseVault() internal {
        vm.prank(uvm_fast);
        manager.execute(address(vault), abi.encodeCall(USDCVault.pause, ()));
    }
}
