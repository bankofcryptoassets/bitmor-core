// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BitmorTestBase} from "../../base/BitmorTestBase.sol";
import {VaultUtilities} from "./VaultUtilities.t.sol";
import {USDCVault} from "@bitmor/vaults/usdc-vault/USDCVault.sol";
import {USDCStrategy} from "@bitmor/vaults/usdc-vault/USDCStrategy.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {MockERC20} from "../../mock/MockERC20.sol";
import {MockBitmorLendingPool} from "../../mock/MockBitmorLendingPool.sol";
import {MockAddressesProvider} from "../../mock/MockAddressesProvider.sol";
import {MockPriceOracle} from "../../mock/MockPriceOracle.sol";
import {MockAaveV3Pool} from "../../mock/MockAaveV3Pool.sol";
import {MockAToken} from "../../mock/MockAToken.sol";
import {MockVariableDebtToken} from "../../mock/MockVariableDebtToken.sol";

import {HelperConfig} from "../../../script/HelperConfig.s.sol";

/// @title BaseTestForUSDCVault
/// @author Bitmor Protocol
/// @notice Base test contract for USDCVault functionality
/// @dev Tests vault operations using AccessManager pattern.
///      Inherits from BitmorTestBase for AccessManager configuration and VaultUtilities for ERC-4626 testing helpers.
contract BaseTestForUSDCVault is BitmorTestBase, VaultUtilities {
    /// @notice USDCVault contract instance under test
    USDCVault internal vault;

    /// @notice USDCStrategy contract instance for yield allocation
    USDCStrategy internal strategy;

    /// @notice Network configuration containing protocol addresses
    MockNetworkConfig internal networkConfig;

    // ============ Test Addresses ============

    /// @notice Primary lender address for deposit/withdraw tests
    address internal lender;

    /// @notice Secondary lender address for multi-user tests
    address internal lender2;

    /// @notice Attacker address for security tests
    address internal attacker;

    // ============ Mock Infrastructure ============
    MockERC20 internal mockUSDC;
    MockBitmorLendingPool internal mockBitmorPool;
    MockAddressesProvider internal mockAddressesProvider;
    MockPriceOracle internal mockOracle;
    MockAaveV3Pool internal mockAavePool;
    MockAToken internal mockAaveAToken;
    MockAToken internal mockBitmorAToken;
    MockVariableDebtToken internal mockBitmorDebtToken;

    /// @notice Compatibility struct for tests that reference networkConfig
    struct MockNetworkConfig {
        address usdc;
        address bitmorPool;
        address aaveV3Pool;
    }

    /// @dev Snapshot of vault state at a point in time
    struct VaultState {
        uint256 totalAssets;
        uint256 totalSupply;
        uint256 sharePrice;
        uint256 aaveBalance;
        uint256 blpBalance;
    }

    /// @dev Snapshot of a user's vault position
    struct UserState {
        uint256 shareBalance;
        uint256 usdcBalance;
        uint256 assetValue;
    }

    // ============ Test Amount Constants ============

    /// @notice Standard deposit amount (10,000 USDC with 6 decimals)
    uint256 internal constant STANDARD_DEPOSIT = 10_000e6;

    /// @notice Large deposit amount (1,000,000 USDC with 6 decimals)
    uint256 internal constant LARGE_DEPOSIT = 1_000_000e6;

    /// @notice Small deposit amount for edge case testing (100 USDC)
    uint256 internal constant SMALL_DEPOSIT = 100e6;

    /// @notice Amount of USDC to mint for testing
    uint256 internal constant USDC_TO_MINT = 100_000_000e6;

    // ============ Allocation Constants ============

    /// @notice Basis points denominator (10,000 = 100%)
    uint256 internal constant BASIS_POINTS = 10_000;

    /// @notice Default Aave allocation (80% = 8000 bps)
    uint256 internal constant DEFAULT_AAVE_ALLOCATION_BPS = 8000;

    /// @notice Half allocation for custom allocation tests (50% = 5000 bps)
    uint256 internal constant HALF_ALLOCATION_BPS = 5000;

    /// @notice Default tolerance for allocation checks (1% = 100 bps)
    uint256 internal constant DEFAULT_TOLERANCE_BPS = 100;

    /// @notice Loose tolerance for allocation checks after withdrawals (5% = 500 bps)
    uint256 internal constant LOOSE_TOLERANCE_BPS = 500;

    // ============ Setup ============

    /// @notice Core test setup - deploys vault and strategy with mock infrastructure
    function setUp() public virtual override {
        // Create test addresses
        lender = makeAddr("LENDER");
        lender2 = makeAddr("LENDER2");
        attacker = makeAddr("ATTACKER");

        // Initialize AccessManager and RolesData
        _initializeAccessManager(address(this));

        // Deploy mock infrastructure
        _deployMockInfrastructure();

        // Set up mock network config for compatibility
        networkConfig = MockNetworkConfig({
            usdc: address(mockUSDC), bitmorPool: address(mockBitmorPool), aaveV3Pool: address(mockAavePool)
        });

        // Deploy vault with mock dependencies
        vault = new USDCVault(address(manager), address(mockUSDC), address(mockBitmorPool));

        // Deploy strategy with mock Aave pool
        strategy = new USDCStrategy(address(vault), address(mockAavePool), address(mockBitmorPool));

        // Set up USDC Vault roles
        _setUSDCVaultRoles();

        // Set function permissions
        _setTargetSelectorsLocal();

        // Configure vault with strategy
        _setStrategy();

        // Mint mock USDC to test accounts
        _mintUSDC();
    }

    /// @notice Deploys mock infrastructure for unit tests
    function _deployMockInfrastructure() internal {
        // Deploy mock USDC
        mockUSDC = new MockERC20("USD Coin", "USDC", 6);

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

        // Deploy mock Aave V3 pool
        mockAavePool = new MockAaveV3Pool();

        // Deploy mock aToken for Aave and initialize reserve
        mockAaveAToken = new MockAToken("Aave Mock USDC", "amUSDC", 6, address(mockUSDC), address(mockAavePool));
        mockAavePool.initReserve(address(mockUSDC), address(mockAaveAToken));

        // Fund pools with liquidity
        mockUSDC.mint(address(mockBitmorPool), 100_000_000e6);
        mockUSDC.mint(address(mockAavePool), 100_000_000e6);
    }

    /// @notice Mint mock USDC to test accounts
    function _mintUSDC() internal {
        mockUSDC.mint(lender, USDC_TO_MINT);
        mockUSDC.mint(lender2, USDC_TO_MINT);
        mockUSDC.mint(address(this), USDC_TO_MINT);
    }

    /// @notice Sets function permissions for each role using correct USDC vault role IDs
    /// @dev Uses actual USDCVault selectors with role IDs from RolesData
    function _setTargetSelectorsLocal() internal {
        address target = address(vault);

        // UVM_SLOW functions (require 1 day delay)
        bytes4[] memory uvmSlowSelectors = new bytes4[](3);
        uvmSlowSelectors[0] = USDCVault.setStrategy.selector;
        uvmSlowSelectors[1] = USDCVault.updateMinimumDeltaRequired.selector;
        uvmSlowSelectors[2] = USDCVault.unpause.selector;
        manager.setTargetFunctionRole(target, uvmSlowSelectors, UVM_SLOW_ID());

        // UVM_FAST functions (no delay)
        bytes4[] memory uvmFastSelectors = new bytes4[](1);
        uvmFastSelectors[0] = USDCVault.pause.selector;
        manager.setTargetFunctionRole(target, uvmFastSelectors, UVM_FAST_ID());

        // UVA functions - use function signature for overloaded function
        bytes4[] memory uvaSelectors = new bytes4[](2);
        uvaSelectors[0] = bytes4(keccak256("reallocateAssets()"));
        uvaSelectors[1] = bytes4(keccak256("reallocateAssets(uint256)"));
        manager.setTargetFunctionRole(target, uvaSelectors, UVA_ID());

        // Grant UVA role to BLP for reallocateAssets(uint256) - the function also checks msg.sender == i_blp
        manager.grantRole(UVA_ID(), address(mockBitmorPool), 0);
    }

    /// @notice Sets the strategy on the vault using UVM_SLOW role
    /// @dev Also initializes the default Aave allocation (80%)
    function _setStrategy() internal {
        _scheduleAndExecuteLocal(uvm_slow, UVM_SLOW_ID(), abi.encodeCall(USDCVault.setStrategy, (address(strategy))));

        // Initialize the default Aave allocation to 80%
        vm.prank(address(vault));
        strategy.setAaveAllocation(DEFAULT_AAVE_ALLOCATION_BPS);
    }

    // ============ Helper Functions ============

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

    /// @notice Deposits USDC into vault for a user
    /// @param depositor The user depositing
    /// @param amount The amount of USDC to deposit
    /// @return shares The number of shares minted
    function _deposit(address depositor, uint256 amount) internal returns (uint256 shares) {
        vm.startPrank(depositor);
        IERC20(networkConfig.usdc).approve(address(vault), amount);
        shares = vault.deposit(amount, depositor);
        vm.stopPrank();
    }

    /// @notice Withdraws USDC from vault for a user
    /// @param withdrawer The user withdrawing
    /// @param assets The amount of USDC to withdraw
    /// @return shares The number of shares burned
    function _withdraw(address withdrawer, uint256 assets) internal returns (uint256 shares) {
        vm.prank(withdrawer);
        shares = vault.withdraw(assets, withdrawer, withdrawer);
    }

    /// @notice Redeems shares from vault for a user
    /// @param redeemer The user redeeming
    /// @param sharesToRedeem The number of shares to redeem
    /// @return assets The amount of USDC returned
    function _redeem(address redeemer, uint256 sharesToRedeem) internal returns (uint256 assets) {
        vm.prank(redeemer);
        assets = vault.redeem(sharesToRedeem, redeemer, redeemer);
    }

    /// @notice Gets the current share price
    /// @return The share price scaled to 1e18
    function _getSharePrice() internal view returns (uint256) {
        uint256 supply = vault.totalSupply();
        if (supply == 0) return 1e18;
        return (vault.totalAssets() * 1e18) / supply;
    }

    /// @notice Gets the current Aave balance from strategy
    /// @return The USDC balance held in Aave via strategy
    function _getAaveBalance() internal view returns (uint256) {
        // Strategy deposits to MockAavePool which mints aTokens
        // The aToken balance represents Aave position
        return mockAaveAToken.balanceOf(address(strategy));
    }

    /// @notice Gets the current Bitmor Lending Pool balance from strategy
    /// @return The USDC balance held in BLP via strategy
    function _getBLPBalance() internal view returns (uint256) {
        // Strategy deposits to MockBitmorPool which mints aTokens
        return mockBitmorAToken.balanceOf(address(strategy));
    }

    /// @notice Gets total balance across all markets
    /// @return The total USDC managed by strategy
    function _getTotalBalance() internal view returns (uint256) {
        return _getAaveBalance() + _getBLPBalance();
    }

    /// @notice Captures current vault state
    /// @return state The vault state snapshot
    function _captureVaultState() internal view returns (VaultState memory state) {
        state.totalAssets = vault.totalAssets();
        state.totalSupply = vault.totalSupply();
        state.sharePrice = _getSharePrice();
        state.aaveBalance = _getAaveBalance();
        state.blpBalance = _getBLPBalance();
    }

    /// @notice Captures current user state
    /// @param user The user address
    /// @return state The user state snapshot
    function _captureUserState(address user) internal view returns (UserState memory state) {
        state.shareBalance = vault.balanceOf(user);
        state.usdcBalance = IERC20(networkConfig.usdc).balanceOf(user);
        state.assetValue = vault.convertToAssets(state.shareBalance);
    }

    // ============ Allocation and Rebalance Helpers ============

    /// @notice Sets the Aave allocation on the strategy
    /// @param allocationBps The new allocation in basis points (e.g., 8000 = 80%)
    /// @dev Pranks as the vault since only the vault can call setAaveAllocation
    function _setAllocation(uint256 allocationBps) internal {
        vm.prank(address(vault));
        strategy.setAaveAllocation(allocationBps);
    }

    /// @notice Triggers reallocation via the vault
    function _rebalance() internal {
        // reallocateAssets() requires UVA role, use schedule/execute
        // Using encodeWithSignature to handle overloaded function
        _scheduleAndExecuteLocal(uva, UVA_ID(), abi.encodeWithSignature("reallocateAssets()"));
    }

    /// @notice Triggers reallocation with specific amount (BLP priority)
    /// @param amountToWithdraw Amount to reallocate from Aave to BLP
    function _rebalanceWithAmount(uint256 amountToWithdraw) internal {
        // reallocateAssets(uint256) is restricted to BLP via msg.sender check
        vm.prank(networkConfig.bitmorPool);
        vault.reallocateAssets(amountToWithdraw);
    }

    /// @notice Donates USDC directly to an address (for security tests)
    /// @param target The address to donate to
    /// @param amount The amount of USDC to donate
    function _donate(address target, uint256 amount) internal {
        address donor = makeAddr("DONOR");
        mockUSDC.mint(donor, amount);
        vm.prank(donor);
        IERC20(networkConfig.usdc).transfer(target, amount);
    }

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

    /// @notice Asserts default 80/20 allocation is correct
    function _assertAllocationCorrect() internal view {
        _assertAllocationCorrect(DEFAULT_AAVE_ALLOCATION_BPS, 100); // 1% tolerance
    }

    /// @notice Funds a lender with USDC and approves vault spending
    /// @param lenderAddr The lender address to fund
    /// @param amount The amount of USDC to approve
    function _fundLenderWithUsdc(address lenderAddr, uint256 amount) internal {
        vm.prank(lenderAddr);
        IERC20(networkConfig.usdc).approve(address(vault), amount);
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
