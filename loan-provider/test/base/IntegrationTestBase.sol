// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BitmorTestBase} from "./BitmorTestBase.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";

// Protocol contracts
import {Loan} from "@bitmor/protocol/Loan.sol";
import {LoanVaultFactory} from "@bitmor/protocol/LoanVaultFactory.sol";
import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";
import {RolesData} from "@bitmor/accessManager/RolesData.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {USDCVault} from "@usdcVault/USDCVault.sol";

// Interfaces
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
// Mocks (for minting and oracle manipulation on deployed mock contracts)
import {MintableERC20} from "../mock/MintableERC20.sol";
import {MockChainlinkOracle} from "../mock/MockChainlinkOracle.sol";

/// @title IntegrationTestBase
/// @author Bitmor Protocol
/// @notice Base contract for integration tests using pre-deployed contracts
/// @dev Reads all addresses from deployments.json - requires `make deploy-local` first.
///      Tests must run with `--fork-url http://127.0.0.1:8545` to connect to live Anvil.
abstract contract IntegrationTestBase is BitmorTestBase {
    // ============ Configuration ============

    HelperConfig public config;

    // ============ Pre-deployed Contracts ============

    Loan public loanContract;
    BTCVault public btcVault;
    USDCVault public usdcVault;
    LoanVaultFactory public loanVaultFactory;
    address public bitmorPool;
    address public addressesProvider;
    address public swapper;

    // ============ Tokens ============

    IERC20 public cbBTC;
    IERC20 public usdc;

    // ============ Oracles ============

    MockChainlinkOracle public btcOracle;
    MockChainlinkOracle public usdcOracle;
    address public aaveV3Pool;

    // ============ Test Actors ============

    address public admin;
    address public testUser;
    address public testLiquidator;

    // ============ Snapshot ============

    uint256 internal _baseSnapshotId;
    uint256 internal constant DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    // ============ Setup ============

    function setUp() public virtual override {
        // 1. Load configuration (reads from deployments.json on disk)
        config = new HelperConfig();

        // 2. Load pre-deployed AccessManager (don't deploy new one)
        manager = BitmorAccessManager(config.getAccessManager());

        // 3. Deploy RolesData so role ID helpers (EXECUTOR_ID, etc.) work
        rolesData = new RolesData();

        // 4. Resolve deployer/admin from PRIVATE_KEY (defaults to Anvil account 0)
        admin = _resolveAdmin();
        testUser = makeAddr("integrationTestUser");
        testLiquidator = makeAddr("integrationTestLiquidator");

        // 5. Load all pre-deployed contracts
        _loadDeployedContracts();

        // 6. Snapshot
        _baseSnapshotId = vm.snapshot();
    }

    /// @notice Skip AccessManager deployment - use pre-deployed one
    function _initializeAccessManager(address) internal override {
        // Intentionally empty - manager and rolesData set in setUp()
    }

    // ============ Contract Loading ============

    /// @notice Resolves the deployer/admin address used by make deploy-local
    function _resolveAdmin() internal view returns (address) {
        uint256 deployerPk = vm.envOr("PRIVATE_KEY", DEFAULT_ANVIL_PRIVATE_KEY);
        return vm.addr(deployerPk);
    }

    function _loadDeployedContracts() internal virtual {
        // Core protocol
        loanContract = Loan(config.getLoan());
        bitmorPool = config.getBitmorPool();
        addressesProvider = config.getAddressesProvider();
        loanVaultFactory = LoanVaultFactory(config.getLoanVaultFactory());
        swapper = config.getSwapper();

        // Vaults
        btcVault = BTCVault(config.getBTCVault());
        usdcVault = USDCVault(config.getUSDCVault());

        // Tokens
        cbBTC = IERC20(config.getCbBTC());
        usdc = IERC20(config.getUSDC());

        // Oracles (mock - for price manipulation in tests)
        btcOracle = MockChainlinkOracle(config.getBtcUsdOracle());
        usdcOracle = MockChainlinkOracle(config.getUsdcUsdOracle());
        aaveV3Pool = config.getAaveV3Pool();
    }

    // ============ Loan Creation Helpers ============

    /// @notice Creates a standard loan: 1 BTC collateral, 12 months
    function _createStandardLoan() internal returns (address lsa) {
        lsa = _createLoan(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);
    }

    /// @notice Creates a loan with custom parameters using the minimum required deposit
    function _createLoan(uint256 collateral, uint256 duration, uint256 premium) internal returns (address lsa) {
        (,, uint256 minDeposit) = loanContract.getLoanDetails(collateral, duration);
        vm.prank(testUser);
        lsa = loanContract.initializeLoan(minDeposit, premium, collateral, duration, "");
    }

    /// @notice Creates a loan and returns both LSA address and stored LoanData
    function _createLoanWithData(uint256 collateral, uint256 duration, uint256 premium)
        internal
        returns (address lsa, DataTypes.LoanData memory loanData)
    {
        lsa = _createLoan(collateral, duration, premium);
        loanData = loanContract.getLoanByLSA(lsa);
    }

    // ============ Funding Helpers ============

    /// @notice Mints mock USDC to `to` (MintableERC20.mint is public)
    /// @dev DEPRECATED: Use `_setupTestUser()` for standard user funding or `_seedBLPLiquidity()` for pool liquidity.
    ///      Direct token minting should only occur inside setUp helpers, not in individual test bodies.
    ///      Will be removed after all integration tests are migrated to use setUp helpers exclusively.
    function _fundUSDC(address to, uint256 amount) internal {
        MintableERC20(address(usdc)).mint(to, amount);
    }

    /// @notice Mints mock cbBTC to `to` (MintableERC20.mint is public)
    /// @dev DEPRECATED: Use `_setupTestUser()` for standard user funding.
    ///      Direct token minting should only occur inside setUp helpers, not in individual test bodies.
    ///      Will be removed after all integration tests are migrated to use setUp helpers exclusively.
    function _fundCbBTC(address to, uint256 amount) internal {
        MintableERC20(address(cbBTC)).mint(to, amount);
    }

    // ============ Oracle Helpers ============

    /// @notice Drops BTC price by `dropPercent`% via MockChainlinkOracle
    /// @dev Oracle manipulation is acceptable in integration tests because MockChainlinkOracle
    ///      is a mock of an EXTERNAL dependency (Chainlink). The mocking boundary permits mocking
    ///      external infrastructure that our protocol does not control. This is distinct from mocking
    ///      our own protocol contracts (e.g., LendingPool, Loan), which should use real deployments.
    function _dropOraclePrice(uint256 dropPercent) internal {
        (, int256 currentPrice,,,) = btcOracle.latestRoundData();
        int256 newPrice = currentPrice * int256(100 - dropPercent) / 100;
        btcOracle.updateAnswer(newPrice);
    }

    /// @notice Sets BTC price directly via MockChainlinkOracle
    /// @dev Acceptable external dependency mock. See `_dropOraclePrice` for rationale.
    function _setBtcPrice(int256 price) internal {
        btcOracle.updateAnswer(price);
    }

    // ============ Time Helpers ============

    /// @notice Warps forward by `days_` days
    function _advanceDays(uint256 days_) internal {
        vm.warp(block.timestamp + days_ * 1 days);
    }

    /// @notice Advances time past the grace period to make loan overdue
    function _makeOverdue() internal {
        vm.warp(block.timestamp + config.getGracePeriod() + 1);
    }

    // ============ Balance Helpers ============

    /// @notice Queries user account data from Bitmor Lending Pool via low-level staticcall
    /// @dev Uses low-level call because Bitmor LP is Solidity 0.6.12 (interface incompatible with 0.8.30)
    /// @return totalCollateralETH Total collateral in ETH units
    /// @return totalDebtETH Total debt in ETH units
    /// @return healthFactor Health factor (1e18 = healthy)
    function _getUserAccountData(address user)
        internal
        view
        returns (uint256 totalCollateralETH, uint256 totalDebtETH, uint256 healthFactor)
    {
        (bool ok, bytes memory data) =
            bitmorPool.staticcall(abi.encodeWithSignature("getUserAccountData(address)", user));
        require(ok, "getUserAccountData failed");
        (totalCollateralETH, totalDebtETH,,,, healthFactor) =
            abi.decode(data, (uint256, uint256, uint256, uint256, uint256, uint256));
    }

    // ============ Setup Helpers ============

    /// @notice Seeds the BLP with USDC liquidity by depositing into USDCVault
    /// @dev Must be called before any loan creation (loans borrow USDC from BLP)
    function _seedBLPLiquidity() internal {
        address seeder = makeAddr("blpSeeder");
        _fundUSDC(seeder, TC.LENDING_POOL_USDC_BALANCE);
        vm.prank(seeder);
        IERC20(address(usdc)).approve(address(usdcVault), TC.LENDING_POOL_USDC_BALANCE);
        vm.prank(seeder);
        usdcVault.deposit(TC.LENDING_POOL_USDC_BALANCE, seeder);
    }

    /// @notice Seeds BTCVault with initial cbBTC so oracle price is computable
    /// @dev BTCVault.deposit() requires BVD role - only the Loan contract has it.
    ///      We prank as the Loan contract to bootstrap the vault.
    function _seedBTCVault() internal {
        uint256 seedAmount = 1e8; // 1 BTC
        _fundCbBTC(address(loanContract), seedAmount);
        vm.startPrank(address(loanContract));
        cbBTC.approve(address(btcVault), seedAmount);
        btcVault.deposit(seedAmount, address(loanContract));
        vm.stopPrank();
    }

    /// @notice Funds testUser with tokens, approves Loan, grants EXECUTOR role
    function _setupTestUser() internal {
        _seedBLPLiquidity();
        _seedBTCVault();
        _fundUSDC(testUser, TC.USER_USDC_BALANCE);
        _fundCbBTC(testUser, TC.USER_CBBTC_BALANCE);

        vm.prank(testUser);
        usdc.approve(address(loanContract), type(uint256).max);

        vm.prank(testUser);
        cbBTC.approve(address(loanContract), type(uint256).max);

        // Grant EXECUTOR role to testUser so they can create loans
        // Cache role ID before prank to avoid consuming it
        uint64 executorRoleId = EXECUTOR_ID();
        vm.prank(admin);
        manager.grantRole(executorRoleId, testUser, 0);
    }

    /// @notice Funds testLiquidator with tokens, approves lending pool
    function _setupLiquidator() internal {
        _fundUSDC(testLiquidator, TC.USER_USDC_BALANCE);

        vm.prank(testLiquidator);
        usdc.approve(bitmorPool, type(uint256).max);
    }

    // ============ Multi-User Helpers ============

    /// @notice Creates a second test user with EXECUTOR role and funding
    function _setupSecondUser() internal returns (address user2) {
        user2 = makeAddr("integrationTestUser2");
        _fundUSDC(user2, TC.USER_USDC_BALANCE);
        _fundCbBTC(user2, TC.USER_CBBTC_BALANCE);
        vm.prank(user2);
        usdc.approve(address(loanContract), type(uint256).max);
        vm.prank(user2);
        cbBTC.approve(address(loanContract), type(uint256).max);
        uint64 executorRoleId = EXECUTOR_ID();
        vm.prank(admin);
        manager.grantRole(executorRoleId, user2, 0);
    }

    /// @notice Funds a user with tokens and grants EXECUTOR role, WITHOUT seeding BLP liquidity
    /// @dev Use when test needs to control BLP liquidity separately
    function _setupUserWithoutBLP(address user) internal {
        _fundUSDC(user, TC.USER_USDC_BALANCE);
        _fundCbBTC(user, TC.USER_CBBTC_BALANCE);
        vm.prank(user);
        usdc.approve(address(loanContract), type(uint256).max);
        vm.prank(user);
        cbBTC.approve(address(loanContract), type(uint256).max);
        uint64 executorRoleId = EXECUTOR_ID();
        vm.prank(admin);
        manager.grantRole(executorRoleId, user, 0);
    }

    // ============ Oracle Helpers (Extended) ============

    /// @notice Queries the Bitmor Lending Pool oracle price for an asset
    function _getOraclePrice(address asset) internal view returns (uint256) {
        address oracle = config.getOracle();
        (bool ok, bytes memory data) =
            oracle.staticcall(abi.encodeWithSignature("getAssetPrice(address)", asset));
        require(ok, "getAssetPrice failed");
        return abi.decode(data, (uint256));
    }

    // ============ Liquidity Helpers (Extended) ============

    /// @notice Seeds BLP liquidity with a specific USDC amount
    function _seedBLPLiquidityAmount(uint256 amount) internal {
        address seeder = makeAddr("blpSeederCustom");
        _fundUSDC(seeder, amount);
        vm.prank(seeder);
        IERC20(address(usdc)).approve(address(usdcVault), amount);
        vm.prank(seeder);
        usdcVault.deposit(amount, seeder);
    }

    // ============ Loan Helpers (Extended) ============

    /// @notice Creates a loan for a specific user (must already have EXECUTOR role + funds)
    function _createLoanForUser(address user, uint256 collateral, uint256 duration, uint256 premium)
        internal
        returns (address lsa)
    {
        (,, uint256 minDeposit) = loanContract.getLoanDetails(collateral, duration);
        vm.prank(user);
        lsa = loanContract.initializeLoan(minDeposit, premium, collateral, duration, "");
    }

    // ============ State Management ============

    /// @notice Reverts to base snapshot for test isolation
    function _resetState() internal {
        vm.revertTo(_baseSnapshotId);
        _baseSnapshotId = vm.snapshotState();
    }
}
