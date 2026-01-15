// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {VaultUtilities} from "./VaultUtilities.t.sol";
import {USDCVault} from "@bitmor/vault/usdc-vault/USDCVault.sol";
import {USDCStrategy} from "@bitmor/vault/usdc-vault/USDCStrategy.sol";
import {IERC20} from "@bitmor/dependencies/openzeppelin/IERC20.sol";
import {ERC4626, ERC20} from "@solady/tokens/ERC4626.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {ILendingPool} from "@bitmor/interfaces/ILendingPool.sol";
import {IPool} from "@bitmor/interfaces/IPool.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

/// @title BaseVaultTest
/// @notice Shared base contract for USDC Vault test suites
/// @dev Provides common state, constants, and setUp/helpers. Inherits from VaultUtilities (Test).
abstract contract BaseVaultTest is VaultUtilities {
    using FixedPointMathLib for uint256;

    // ============ Core Vault Contracts ============

    HelperConfig internal config;
    USDCVault internal vault;
    USDCStrategy internal strategy;

    // ============ Test Actors ============

    address internal deployer;
    address internal lender;
    address internal lender2;
    address internal curator;
    address internal allocator;
    address internal manager;
    address internal attacker;

    // ============ Protocol Addresses ============

    address internal usdc;
    address internal aavePool;
    address internal bitmorPool;
    address internal aaveAToken; // Aave's aUSDC token

    // ============ Role Constants ============

    bytes32 internal constant ALLOCATOR_ROLE = keccak256("ALLOCATOR");
    bytes32 internal constant MANAGER_ROLE = keccak256("MANAGER");
    bytes32 internal constant CURATOR_ROLE = keccak256("CURATOR");
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    // ============ Test Amount Constants ============

    /// @dev Standard deposit amount (10,000 USDC with 6 decimals)
    uint256 internal constant STANDARD_DEPOSIT = 10_000e6;

    /// @dev Large deposit amount (1,000,000 USDC with 6 decimals)
    uint256 internal constant LARGE_DEPOSIT = 1_000_000e6;

    /// @dev Small deposit amount for edge case testing (100 USDC)
    uint256 internal constant SMALL_DEPOSIT = 100e6;

    /// @dev Minimum deposit for dust testing (1 USDC)
    uint256 internal constant MIN_DEPOSIT = 1e6;

    // ============ Allocation Constants ============

    /// @dev Basis points denominator (10,000 = 100%)
    uint256 internal constant BASIS_POINTS = 10_000;

    /// @dev Default Aave allocation (80% = 8000 bps)
    uint256 internal constant DEFAULT_AAVE_ALLOCATION_BPS = 8000;

    /// @dev Default BLP allocation (20% = 2000 bps)
    uint256 internal constant DEFAULT_BLP_ALLOCATION_BPS = 2000;

    /// @dev 50/50 allocation for testing
    uint256 internal constant HALF_ALLOCATION_BPS = 5000;

    /// @dev 100% Aave allocation for edge case testing
    uint256 internal constant FULL_AAVE_ALLOCATION_BPS = 10_000;

    /// @dev Zero allocation for edge case testing
    uint256 internal constant ZERO_ALLOCATION_BPS = 0;

    // ============ Tolerance Constants ============

    /// @dev Default tolerance for approximate assertions (50 bps = 0.5%)
    uint256 internal constant DEFAULT_TOLERANCE_BPS = 50;

    /// @dev Strict tolerance for share price checks (10 bps = 0.1%)
    uint256 internal constant STRICT_TOLERANCE_BPS = 10;

    /// @dev Loose tolerance for yield accrual checks (100 bps = 1%)
    uint256 internal constant LOOSE_TOLERANCE_BPS = 100;

    // ============ Precision Constants ============

    /// @dev Share price precision (1e18)
    uint256 internal constant SHARE_PRICE_PRECISION = 1e18;

    /// @dev USDC decimals
    uint256 internal constant USDC_DECIMALS = 6;

    // ============ Time Constants ============

    /// @dev One day in seconds
    uint256 internal constant ONE_DAY = 1 days;

    /// @dev One week in seconds
    uint256 internal constant ONE_WEEK = 7 days;

    /// @dev One year in seconds (for yield calculations)
    uint256 internal constant ONE_YEAR = 365 days;

    // ============ State Structs ============

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
        uint256 assetValue; // shareBalance * sharePrice
    }

    /// @dev Snapshot for before/after comparison in tests
    struct TestSnapshot {
        VaultState vaultStateBefore;
        VaultState vaultStateAfter;
        UserState userStateBefore;
        UserState userStateAfter;
    }

    /// @dev Allocation check result
    struct AllocationCheck {
        uint256 aaveBalance;
        uint256 blpBalance;
        uint256 totalBalance;
        uint256 actualAaveAllocationBps;
        uint256 targetAaveAllocationBps;
        bool isWithinTolerance;
    }

    // ============ Setup ============

    /// @notice Core test setup - deploys vault and strategy, creates actors, sets up roles
    function setUp() public virtual {
        config = new HelperConfig();

        // Create test actors with labeled addresses
        deployer = makeAddr("deployer");
        lender = makeAddr("lender");
        lender2 = makeAddr("lender2");
        curator = makeAddr("curator");
        allocator = makeAddr("allocator");
        manager = makeAddr("manager");
        attacker = makeAddr("attacker");

        // Get network configuration
        (
            address bitmorPoolAddr,
            address aaveV3Pool,
            , // aaveAddressesProvider
            , // oracle
            , // collateralAsset
            address debtAssetAddr,
            , // swapAdapterWrapper
            , // zQuoter
            , // premiumCollector
            , // preClosureFeeBps
            , // gracePeriod
              // liquidationBuffer
        ) = config.networkConfig();

        // Store addresses
        usdc = debtAssetAddr;
        aavePool = aaveV3Pool;
        bitmorPool = bitmorPoolAddr;

        // Deploy contracts as deployer
        vm.startPrank(deployer);

        // Deploy USDCVault
        vault = new USDCVault(usdc, bitmorPool);

        // Deploy USDCStrategy
        strategy = new USDCStrategy(address(vault), aavePool, bitmorPool, deployer);

        // Grant roles on vault
        vault.grantRole(MANAGER_ROLE, manager);
        vault.grantRole(ALLOCATOR_ROLE, allocator);

        // Grant curator role on strategy
        strategy.grantRole(CURATOR_ROLE, curator);

        // Set strategy on vault (requires MANAGER_ROLE)
        vm.stopPrank();
        vm.prank(manager);
        vault.setStrategy(address(strategy));

        // Set default Aave allocation (80%)
        vm.prank(curator);
        strategy.setAaveAllocation(DEFAULT_AAVE_ALLOCATION_BPS);

        vm.stopPrank();

        // Cache Aave aToken address for balance checks
        aaveAToken = IPool(aavePool).getReserveAToken(usdc);
    }

    // ============ Modifiers ============

    /// @notice Modifier to fund lender with USDC and approve vault
    /// @param amount The amount to fund and approve
    modifier fundLender(uint256 amount) {
        _fundLenderWithUsdc(lender, amount);
        _;
    }

    /// @notice Modifier to fund lender and make a deposit in one step
    /// @param amount The amount to deposit
    modifier withDeposit(uint256 amount) {
        _fundLenderWithUsdc(lender, amount);
        _deposit(lender, amount);
        _;
    }

    /// @notice Modifier to fund lender2 with USDC and approve vault
    /// @param amount The amount to fund and approve
    modifier fundLender2(uint256 amount) {
        _fundLenderWithUsdc(lender2, amount);
        _;
    }

    // ============ State Capture Helpers ============

    /// @notice Capture complete vault state snapshot
    /// @return state The current vault state
    function _captureVaultState() internal view returns (VaultState memory state) {
        state.totalAssets = vault.totalAssets();
        state.totalSupply = vault.totalSupply();
        state.sharePrice = _getSharePrice();
        state.aaveBalance = _getAaveBalance();
        state.blpBalance = _getBLPBalance();
    }

    /// @notice Capture user state snapshot
    /// @param user The user address to capture state for
    /// @return state The user's current state
    function _captureUserState(address user) internal view returns (UserState memory state) {
        state.shareBalance = vault.balanceOf(user);
        state.usdcBalance = IERC20(usdc).balanceOf(user);
        uint256 sharePrice = _getSharePrice();
        state.assetValue = (state.shareBalance * sharePrice) / SHARE_PRICE_PRECISION;
    }

    /// @notice Capture full test snapshot (vault + user before state)
    /// @param user The user to capture state for
    /// @return snapshot The test snapshot with before state populated
    function _captureTestSnapshot(address user) internal view returns (TestSnapshot memory snapshot) {
        snapshot.vaultStateBefore = _captureVaultState();
        snapshot.userStateBefore = _captureUserState(user);
    }

    /// @notice Update test snapshot with after state
    /// @param snapshot The snapshot to update
    /// @param user The user to capture state for
    function _updateTestSnapshotAfter(TestSnapshot memory snapshot, address user) internal view {
        snapshot.vaultStateAfter = _captureVaultState();
        snapshot.userStateAfter = _captureUserState(user);
    }

    // ============ Action Helpers ============

    /// @notice Deposit USDC into vault for a user
    /// @param user The user depositing
    /// @param amount The amount of USDC to deposit
    /// @return shares The number of shares minted
    function _deposit(address user, uint256 amount) internal returns (uint256 shares) {
        vm.prank(user);
        shares = vault.deposit(amount, user);
    }

    /// @notice Withdraw USDC from vault for a user
    /// @param user The user withdrawing
    /// @param assets The amount of USDC to withdraw
    /// @return shares The number of shares burned
    function _withdraw(address user, uint256 assets) internal returns (uint256 shares) {
        vm.prank(user);
        shares = vault.withdraw(assets, user, user);
    }

    /// @notice Redeem shares from vault for a user
    /// @param user The user redeeming
    /// @param shares The number of shares to redeem
    /// @return assets The amount of USDC returned
    function _redeem(address user, uint256 shares) internal returns (uint256 assets) {
        vm.prank(user);
        assets = vault.redeem(shares, user, user);
    }

    /// @notice Set the Aave allocation via curator
    /// @param allocationBps The new allocation in basis points
    function _setAllocation(uint256 allocationBps) internal {
        vm.prank(curator);
        strategy.setAaveAllocation(allocationBps);
    }

    /// @notice Trigger rebalance via allocator role
    function _rebalance() internal {
        vm.prank(allocator);
        vault.reallocateAssets();
    }

    /// @notice Trigger rebalance with specific amount to withdraw (for borrower priority)
    /// @param amountToWithdraw The amount to withdraw from Aave to BLP
    function _rebalanceWithAmount(uint256 amountToWithdraw) internal {
        vm.prank(bitmorPool);
        vault.reallocateAssets(amountToWithdraw);
    }

    // ============ Attack/Donation Helpers ============

    /// @notice Donate tokens directly to a target (for donation attack testing)
    /// @param target The address to donate to (e.g., strategy, aToken)
    /// @param amount The amount of USDC to donate
    function _donate(address target, uint256 amount) internal {
        // Mint USDC to attacker
        _utilMintTokenTo(usdc, attacker, amount);

        // Transfer directly to target
        vm.prank(attacker);
        IERC20(usdc).transfer(target, amount);
    }

    /// @notice Fund and execute a front-run deposit attack
    /// @param frontRunAmount Amount attacker deposits first
    /// @param victimAmount Amount victim tries to deposit
    /// @return attackerShares Shares attacker received
    /// @return victimShares Shares victim received
    function _executeFrontRunAttack(uint256 frontRunAmount, uint256 victimAmount)
        internal
        returns (uint256 attackerShares, uint256 victimShares)
    {
        // Fund attacker
        _fundLenderWithUsdc(attacker, frontRunAmount);

        // Attacker deposits first
        attackerShares = _deposit(attacker, frontRunAmount);

        // Fund victim (lender)
        _fundLenderWithUsdc(lender, victimAmount);

        // Victim deposits after
        victimShares = _deposit(lender, victimAmount);
    }

    // ============ Balance Helpers ============

    /// @notice Get the current balance in Aave
    /// @return The USDC balance in Aave (aToken balance of strategy)
    function _getAaveBalance() internal view returns (uint256) {
        return ERC20(aaveAToken).balanceOf(address(strategy));
    }

    /// @notice Get the current balance in BLP (Bitmor Lending Pool)
    /// @return The USDC balance in BLP
    function _getBLPBalance() internal view returns (uint256) {
        DataTypes.ReserveData memory reserveData = ILendingPool(bitmorPool).getReserveData(usdc);
        address blpAToken = reserveData.aTokenAddress;
        return IERC20(usdc).balanceOf(blpAToken);
    }

    /// @notice Get the current share price
    /// @return The share price scaled to 1e18
    function _getSharePrice() internal view returns (uint256) {
        uint256 supply = vault.totalSupply();
        if (supply == 0) return SHARE_PRICE_PRECISION;
        return (vault.totalAssets() * SHARE_PRICE_PRECISION) / supply;
    }

    /// @notice Get total balance across both protocols
    /// @return The total USDC balance (Aave + BLP)
    function _getTotalBalance() internal view returns (uint256) {
        return _getAaveBalance() + _getBLPBalance();
    }

    // ============ Assertion Helpers ============

    /// @notice Assert that allocation is within tolerance of target
    function _assertAllocationCorrect() internal view {
        _assertAllocationCorrect(DEFAULT_AAVE_ALLOCATION_BPS, DEFAULT_TOLERANCE_BPS);
    }

    /// @notice Assert that allocation matches a specific target within tolerance
    /// @param targetAaveAllocationBps The target Aave allocation in basis points
    /// @param toleranceBps The acceptable tolerance in basis points
    function _assertAllocationCorrect(uint256 targetAaveAllocationBps, uint256 toleranceBps) internal view {
        uint256 aaveBalance = _getAaveBalance();
        uint256 totalBalance = _getTotalBalance();

        if (totalBalance == 0) return; // Skip check if no deposits

        uint256 actualAaveAllocationBps = (aaveBalance * BASIS_POINTS) / totalBalance;

        uint256 delta = actualAaveAllocationBps > targetAaveAllocationBps
            ? actualAaveAllocationBps - targetAaveAllocationBps
            : targetAaveAllocationBps - actualAaveAllocationBps;

        assertTrue(
            delta <= toleranceBps,
            string.concat(
                "Allocation out of tolerance. Actual: ",
                vm.toString(actualAaveAllocationBps),
                " Target: ",
                vm.toString(targetAaveAllocationBps)
            )
        );
    }

    /// @notice Assert that share price has not decreased (protects against attacks)
    /// @param previousSharePrice The share price before the action
    function _assertSharePriceNotDecreased(uint256 previousSharePrice) internal view {
        uint256 currentSharePrice = _getSharePrice();
        assertGe(currentSharePrice, previousSharePrice, "Share price decreased - potential attack detected");
    }

    /// @notice Assert that share price has not decreased significantly (allows for rounding)
    /// @param previousSharePrice The share price before the action
    /// @param toleranceBps Maximum allowed decrease in basis points
    function _assertSharePriceNotDecreasedSignificantly(uint256 previousSharePrice, uint256 toleranceBps)
        internal
        view
    {
        uint256 currentSharePrice = _getSharePrice();
        uint256 minAcceptable = (previousSharePrice * (BASIS_POINTS - toleranceBps)) / BASIS_POINTS;
        assertGe(
            currentSharePrice,
            minAcceptable,
            "Share price decreased beyond tolerance - potential attack detected"
        );
    }

    /// @notice Assert approximate equality within basis point tolerance
    /// @param actual The actual value
    /// @param expected The expected value
    /// @param toleranceBps Tolerance in basis points
    /// @param message Error message
    function _assertApproxEqBps(uint256 actual, uint256 expected, uint256 toleranceBps, string memory message)
        internal
        pure
    {
        _utilAssertApproxBps(actual, expected, toleranceBps, message);
    }

    /// @notice Get allocation check data for debugging
    /// @return check The allocation check result
    function _getAllocationCheck() internal view returns (AllocationCheck memory check) {
        check.aaveBalance = _getAaveBalance();
        check.blpBalance = _getBLPBalance();
        check.totalBalance = check.aaveBalance + check.blpBalance;
        check.targetAaveAllocationBps = DEFAULT_AAVE_ALLOCATION_BPS;

        if (check.totalBalance > 0) {
            check.actualAaveAllocationBps = (check.aaveBalance * BASIS_POINTS) / check.totalBalance;
            uint256 delta = check.actualAaveAllocationBps > check.targetAaveAllocationBps
                ? check.actualAaveAllocationBps - check.targetAaveAllocationBps
                : check.targetAaveAllocationBps - check.actualAaveAllocationBps;
            check.isWithinTolerance = delta <= DEFAULT_TOLERANCE_BPS;
        }
    }

    // ============ Funding Helpers ============

    /// @notice Fund a lender with USDC and approve vault spending
    /// @param lenderAddr The lender address to fund
    /// @param amount The amount of USDC to mint and approve
    function _fundLenderWithUsdc(address lenderAddr, uint256 amount) internal {
        _utilMintTokenAndApprove(usdc, lenderAddr, address(vault), amount);
    }

    /// @notice Fund multiple lenders with equal amounts
    /// @param amount The amount each lender should receive
    function _fundAllLenders(uint256 amount) internal {
        _fundLenderWithUsdc(lender, amount);
        _fundLenderWithUsdc(lender2, amount);
    }

    // ============ Time Helpers ============

    /// @notice Warp time forward to simulate yield accrual
    /// @param duration The duration to warp forward
    function _warpTime(uint256 duration) internal {
        vm.warp(block.timestamp + duration);
    }

    /// @notice Warp time by days
    /// @param days_ Number of days to warp
    function _warpDays(uint256 days_) internal {
        _warpTime(days_ * ONE_DAY);
    }

    // ============ Error Testing Helpers ============

    /// @dev Helper wrapper for consistent error expectations with specific selector
    function _expectRevertSelector(bytes4 selector) internal {
        vm.expectRevert(selector);
    }

    /// @dev Helper wrapper for consistent error expectations with specific error message
    function _expectRevertMessage(string memory message) internal {
        vm.expectRevert(bytes(message));
    }

    /// @dev Helper wrapper for generic revert expectation
    function _expectGenericRevert() internal {
        vm.expectRevert();
    }

    // ============ Role Helpers ============

    /// @notice Check if an address has the allocator role
    /// @param account The address to check
    /// @return True if the account has the allocator role
    function _hasAllocatorRole(address account) internal view returns (bool) {
        return vault.hasRole(ALLOCATOR_ROLE, account);
    }

    /// @notice Check if an address has the manager role
    /// @param account The address to check
    /// @return True if the account has the manager role
    function _hasManagerRole(address account) internal view returns (bool) {
        return vault.hasRole(MANAGER_ROLE, account);
    }

    /// @notice Check if an address has the curator role on strategy
    /// @param account The address to check
    /// @return True if the account has the curator role
    function _hasCuratorRole(address account) internal view returns (bool) {
        return strategy.hasRole(CURATOR_ROLE, account);
    }

    /// @notice Grant allocator role to an address
    /// @param account The address to grant the role to
    function _grantAllocatorRole(address account) internal {
        vm.prank(deployer);
        vault.grantRole(ALLOCATOR_ROLE, account);
    }

    /// @notice Grant manager role to an address
    /// @param account The address to grant the role to
    function _grantManagerRole(address account) internal {
        vm.prank(deployer);
        vault.grantRole(MANAGER_ROLE, account);
    }

    /// @notice Grant curator role to an address on strategy
    /// @param account The address to grant the role to
    function _grantCuratorRole(address account) internal {
        vm.prank(deployer);
        strategy.grantRole(CURATOR_ROLE, account);
    }

    // ============ Preview Helpers ============

    /// @notice Preview deposit to check expected shares
    /// @param assets The amount of assets to deposit
    /// @return The expected shares to receive
    function _previewDeposit(uint256 assets) internal view returns (uint256) {
        return vault.previewDeposit(assets);
    }

    /// @notice Preview withdraw to check expected shares to burn
    /// @param assets The amount of assets to withdraw
    /// @return The expected shares to burn
    function _previewWithdraw(uint256 assets) internal view returns (uint256) {
        return vault.previewWithdraw(assets);
    }

    /// @notice Preview redeem to check expected assets
    /// @param shares The amount of shares to redeem
    /// @return The expected assets to receive
    function _previewRedeem(uint256 shares) internal view returns (uint256) {
        return vault.previewRedeem(shares);
    }

    /// @notice Preview mint to check expected assets needed
    /// @param shares The amount of shares to mint
    /// @return The expected assets required
    function _previewMint(uint256 shares) internal view returns (uint256) {
        return vault.previewMint(shares);
    }

    // ============ Logging Helpers (for debugging) ============

    /// @notice Log current vault state for debugging
    function _logVaultState() internal {
        VaultState memory state = _captureVaultState();
        emit log_named_uint("Total Assets", state.totalAssets);
        emit log_named_uint("Total Supply", state.totalSupply);
        emit log_named_uint("Share Price", state.sharePrice);
        emit log_named_uint("Aave Balance", state.aaveBalance);
        emit log_named_uint("BLP Balance", state.blpBalance);
    }

    /// @notice Log allocation status for debugging
    function _logAllocation() internal {
        AllocationCheck memory check = _getAllocationCheck();
        emit log_named_uint("Aave Balance", check.aaveBalance);
        emit log_named_uint("BLP Balance", check.blpBalance);
        emit log_named_uint("Total Balance", check.totalBalance);
        emit log_named_uint("Actual Aave Allocation (bps)", check.actualAaveAllocationBps);
        emit log_named_uint("Target Aave Allocation (bps)", check.targetAaveAllocationBps);
        emit log_named_string("Within Tolerance", check.isWithinTolerance ? "Yes" : "No");
    }
}
