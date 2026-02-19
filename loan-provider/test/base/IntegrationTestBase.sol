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
// Strategy (for yield simulation)
import {AaveTokenizedStrategy} from "@btcVault/TokenizedStrategy/AaveTokenizedStrategy.sol";

/// @title IntegrationTestBase
/// @author Bitmor Protocol
/// @notice Base contract for integration tests using pre-deployed contracts
/// @dev Reads all addresses from deployments.json - requires `make deploy-local` first.
///      Tests must run with `--fork-url http://127.0.0.1:8545` to connect to live Anvil.
abstract contract IntegrationTestBase is BitmorTestBase {
    // ============ Configuration & State ============

    HelperConfig public config;

    // Pre-deployed Contracts
    Loan public loanContract;
    BTCVault public btcVault;
    USDCVault public usdcVault;
    LoanVaultFactory public loanVaultFactory;
    address public bitmorPool;
    address public addressesProvider;
    address public swapper;

    // Tokens
    IERC20 public cbBTC;
    IERC20 public usdc;

    // Oracles
    MockChainlinkOracle public btcOracle;
    MockChainlinkOracle public usdcOracle;
    address public aaveV3Pool;

    // Test Actors
    address public admin;
    address public testUser;
    address public testLiquidator;

    // Snapshot
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

    // ============ Actor Setup ============

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

    /// @notice Creates an additional test user with EXECUTOR role and funding
    /// @param name Unique name for the user (used in makeAddr)
    function _setupAdditionalUser(string memory name) internal returns (address user) {
        user = makeAddr(name);
        _setupUserWithoutBLP(user);
    }

    /// @notice Funds a user with tokens and grants EXECUTOR role, WITHOUT seeding BLP liquidity
    /// @dev Use when test needs to control BLP liquidity separately, or when BLP is already seeded
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

    /// @notice Funds testLiquidator with tokens, approves lending pool
    function _setupLiquidator() internal {
        _fundUSDC(testLiquidator, TC.USER_USDC_BALANCE);

        vm.prank(testLiquidator);
        usdc.approve(bitmorPool, type(uint256).max);
    }

    // ============ Funding & Liquidity ============

    /// @notice Mints mock USDC to `to` (MintableERC20.mint is public)
    function _fundUSDC(address to, uint256 amount) internal {
        MintableERC20(address(usdc)).mint(to, amount);
    }

    /// @notice Mints mock cbBTC to `to` (MintableERC20.mint is public)
    function _fundCbBTC(address to, uint256 amount) internal {
        MintableERC20(address(cbBTC)).mint(to, amount);
    }

    /// @notice Seeds the BLP with USDC liquidity by depositing into USDCVault
    /// @dev Must be called before any loan creation (loans borrow USDC from BLP)
    function _seedBLPLiquidity() internal {
        _seedBLPLiquidity(TC.LENDING_POOL_USDC_BALANCE);
    }

    /// @notice Seeds BLP liquidity with a specific USDC amount
    function _seedBLPLiquidity(uint256 amount) internal {
        address seeder = makeAddr("blpSeeder");
        _fundUSDC(seeder, amount);
        vm.prank(seeder);
        IERC20(address(usdc)).approve(address(usdcVault), amount);
        vm.prank(seeder);
        usdcVault.deposit(amount, seeder);
    }

    /// @notice Seeds BTCVault with initial cbBTC so oracle price is computable
    /// @dev BTCVault.deposit() requires BVD role - only the Loan contract has it.
    ///      We prank as the Loan contract to bootstrap the vault.
    function _seedBTCVault() internal {
        uint256 seedAmount = TC.STANDARD_COLLATERAL;
        _fundCbBTC(address(loanContract), seedAmount);
        vm.startPrank(address(loanContract));
        cbBTC.approve(address(btcVault), seedAmount);
        btcVault.deposit(seedAmount, address(loanContract));
        vm.stopPrank();
    }

    // ============ Loan Helpers ============

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

    /// @notice Creates a standard loan and returns the LSA + loan data
    function _createStandardLoanWithData()
        internal
        returns (address lsa, DataTypes.LoanData memory loanData)
    {
        return _createLoanWithData(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);
    }

    /// @notice Creates a loan for a specific user (must already have EXECUTOR role + funds)
    function _createLoanForUser(address user, uint256 collateral, uint256 duration, uint256 premium)
        internal
        returns (address lsa)
    {
        (,, uint256 minDeposit) = loanContract.getLoanDetails(collateral, duration);
        vm.prank(user);
        lsa = loanContract.initializeLoan(minDeposit, premium, collateral, duration, "");
    }

    /// @notice Executes a repayment on behalf of a user
    /// @param lsa The LSA to repay
    /// @param payer The address paying
    /// @param amount The repayment amount in USDC
    function _repayLoan(address lsa, address payer, uint256 amount) internal {
        vm.prank(payer);
        loanContract.repay(lsa, amount);
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

    /// @notice Queries the Bitmor Lending Pool oracle price for an asset
    function _getOraclePrice(address asset) internal view returns (uint256) {
        address oracle = config.getOracle();
        (bool ok, bytes memory data) =
            oracle.staticcall(abi.encodeWithSignature("getAssetPrice(address)", asset));
        require(ok, "getAssetPrice failed");
        return abi.decode(data, (uint256));
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

    /// @notice Makes a freshly created loan overdue by advancing past the first payment + grace period
    /// @dev Overdue threshold = lastPaymentTimestamp + REPAYMENT_INTERVAL(30d) + GRACE_PERIOD(7d)
    ///      This helper warps past that threshold. Use instead of _makeOverdue() when the loan
    ///      was just created and no payments have been made.
    function _makeFirstPaymentOverdue() internal {
        vm.warp(block.timestamp + 30 days + config.getGracePeriod() + 1);
    }

    // ============ BLP Query Helpers ============

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

    /// @notice Gets the USDC-denominated debt balance for an LSA (includes accrued interest)
    /// @dev Queries BLP getReserveData → variableDebtTokenAddress → balanceOf(lsa)
    function _getDebtBalanceUSDC(address lsa) internal view returns (uint256 debt) {
        // Step 1: Get the variable debt token address from reserve data
        (bool ok1, bytes memory reserveData) =
            bitmorPool.staticcall(abi.encodeWithSignature("getReserveData(address)", address(usdc)));
        require(ok1, "getReserveData failed");
        // ReserveData struct: field 9 (0-indexed) is variableDebtTokenAddress
        (,,,,,,,,,address vdt,,) = abi.decode(
            reserveData,
            (uint256, uint128, uint128, uint128, uint128, uint128, uint40, address, address, address, address, uint8)
        );
        // Step 2: Get current debt balance (includes accrued interest)
        (bool ok2, bytes memory balData) =
            vdt.staticcall(abi.encodeWithSignature("balanceOf(address)", lsa));
        require(ok2, "VDT balanceOf failed");
        debt = abi.decode(balData, (uint256));
    }

    /// @notice Gets the scaled (principal-only) debt balance for an LSA
    function _getScaledDebtBalance(address lsa) internal view returns (uint256 scaledDebt) {
        (bool ok1, bytes memory reserveData) =
            bitmorPool.staticcall(abi.encodeWithSignature("getReserveData(address)", address(usdc)));
        require(ok1, "getReserveData failed");
        (,,,,,,,,,address vdt,,) = abi.decode(
            reserveData,
            (uint256, uint128, uint128, uint128, uint128, uint128, uint40, address, address, address, address, uint8)
        );
        (bool ok2, bytes memory data) =
            vdt.staticcall(abi.encodeWithSignature("scaledBalanceOf(address)", lsa));
        require(ok2, "VDT scaledBalanceOf failed");
        scaledDebt = abi.decode(data, (uint256));
    }

    /// @notice Gets the variable borrow index for USDC from the BLP
    function _getVariableBorrowIndex() internal view returns (uint256 index) {
        (bool ok, bytes memory reserveData) =
            bitmorPool.staticcall(abi.encodeWithSignature("getReserveData(address)", address(usdc)));
        require(ok, "getReserveData failed");
        // Field 2 (0-indexed) is variableBorrowIndex (uint128, stored as RAY)
        (,, uint128 borrowIndex,,,,,,,,,) = abi.decode(
            reserveData,
            (uint256, uint128, uint128, uint128, uint128, uint128, uint40, address, address, address, address, uint8)
        );
        index = uint256(borrowIndex);
    }

    /// @notice Gets the aToken (collateral) balance for an LSA in the BLP
    function _getATokenBalance(address lsa) internal view returns (uint256 balance) {
        (bool ok1, bytes memory reserveData) = bitmorPool.staticcall(
            abi.encodeWithSignature("getReserveData(address)", address(btcVault))
        );
        require(ok1, "getReserveData(btcVault) failed");
        (,,,,,,, address aTokenAddr,,,,) = abi.decode(
            reserveData,
            (uint256, uint128, uint128, uint128, uint128, uint128, uint40, address, address, address, address, uint8)
        );
        (bool ok2, bytes memory data) =
            aTokenAddr.staticcall(abi.encodeWithSignature("balanceOf(address)", lsa));
        require(ok2, "aToken balanceOf failed");
        balance = abi.decode(data, (uint256));
    }

    /// @notice Gets the total scaled debt supply (sum of all scaledBalanceOf) for USDC
    function _getTotalScaledDebtSupply() internal view returns (uint256 totalScaled) {
        (bool ok1, bytes memory reserveData) =
            bitmorPool.staticcall(abi.encodeWithSignature("getReserveData(address)", address(usdc)));
        require(ok1, "getReserveData failed");
        (,,,,,,,,,address vdt,,) = abi.decode(
            reserveData,
            (uint256, uint128, uint128, uint128, uint128, uint128, uint40, address, address, address, address, uint8)
        );
        (bool ok2, bytes memory data) =
            vdt.staticcall(abi.encodeWithSignature("scaledTotalSupply()"));
        require(ok2, "VDT scaledTotalSupply failed");
        totalScaled = abi.decode(data, (uint256));
    }

    /// @notice Gets the liquidity index for an asset from BLP reserve data
    function _getLiquidityIndex(address asset) internal view returns (uint256 index) {
        (bool ok, bytes memory reserveData) =
            bitmorPool.staticcall(abi.encodeWithSignature("getReserveData(address)", asset));
        require(ok, "getReserveData failed");
        // Field 1 (0-indexed) is liquidityIndex (uint128, stored as RAY)
        (, uint128 liqIndex,,,,,,,,,,) = abi.decode(
            reserveData,
            (uint256, uint128, uint128, uint128, uint128, uint128, uint40, address, address, address, address, uint8)
        );
        index = uint256(liqIndex);
    }

    /// @notice Gets the BLP's available liquidity for an asset (raw token balance held by pool)
    function _getBLPAvailableLiquidity(address asset) internal view returns (uint256) {
        return IERC20(asset).balanceOf(bitmorPool);
    }

    // ============ Liquidation Helpers ============

    /// @notice Queries checkTypeOfLiquidation from the lending pool
    function _checkTypeOfLiquidation(address lsa) internal view returns (uint256 liquidationType) {
        (bool ok, bytes memory data) =
            bitmorPool.staticcall(abi.encodeWithSignature("checkTypeOfLiquidation(address)", lsa));
        require(ok, "checkTypeOfLiquidation failed");
        liquidationType = abi.decode(data, (uint256));
    }

    /// @notice Triggers a micro-liquidation on the BLP for a given LSA
    /// @dev Uses low-level call because BLP is Solidity 0.6.12.
    ///      Caller must call _setupLiquidator() before using this helper.
    /// @return success Whether the call succeeded
    function _triggerMicroLiquidation(address lsa) internal returns (bool success) {
        bytes memory mlData = abi.encode(address(btcVault), address(usdc), lsa);
        vm.prank(testLiquidator);
        (success,) = bitmorPool.call(
            abi.encodeWithSignature("microLiquidationCall(bytes)", mlData)
        );
    }

    /// @notice Triggers a full liquidation on the BLP for a given LSA
    /// @dev Caller must call _setupLiquidator() before using this helper.
    /// @return success Whether the call succeeded
    function _triggerFullLiquidation(address lsa) internal returns (bool success) {
        vm.prank(testLiquidator);
        (success,) = bitmorPool.call(
            abi.encodeWithSignature(
                "liquidationCall(address,address,address,uint256,bool)",
                address(btcVault), address(usdc), lsa, type(uint256).max, false
            )
        );
    }

    // ============ Yield Simulation ============

    /// @notice Simulates yield accrual in BTCVault's AaveTokenizedStrategy
    /// @dev Uses deal() to inflate the strategy's aToken balance. This is acceptable
    ///      because it simulates an external dependency (Aave yield) not our protocol.
    ///      MUST be called AFTER a loan exists (strategy needs deposits to inflate).
    function _simulateVaultYield(uint256 yieldBps) internal virtual {
        address strategy = config.getAaveTokenizedStrategy();
        AaveTokenizedStrategy ats = AaveTokenizedStrategy(strategy);
        address yieldSource = ats.i_yieldSource();
        (bool ok, bytes memory data) =
            yieldSource.staticcall(abi.encodeWithSignature("getReserveAToken(address)", address(cbBTC)));
        require(ok, "getReserveAToken failed");
        address aToken = abi.decode(data, (address));
        uint256 currentBalance = IERC20(aToken).balanceOf(strategy);
        require(currentBalance > 0, "strategy must have deposits before simulating yield");
        uint256 yieldAmount = currentBalance * yieldBps / 10_000;
        deal(aToken, strategy, currentBalance + yieldAmount);
    }

    /// @notice Simulates strategy loss by reducing the strategy's aToken balance
    function _simulateStrategyLoss(uint256 lossBps) internal {
        address strategy = config.getAaveTokenizedStrategy();
        AaveTokenizedStrategy ats = AaveTokenizedStrategy(strategy);
        address yieldSource = ats.i_yieldSource();
        (bool ok, bytes memory data) =
            yieldSource.staticcall(abi.encodeWithSignature("getReserveAToken(address)", address(cbBTC)));
        require(ok, "getReserveAToken failed");
        address aToken = abi.decode(data, (address));
        uint256 currentBalance = IERC20(aToken).balanceOf(strategy);
        uint256 lossAmount = currentBalance * lossBps / 10_000;
        deal(aToken, strategy, currentBalance - lossAmount);
    }

    // ============ Insurance Helpers ============

    /// @notice Sets insurance ID on a loan (admin has EXECUTOR role from deploy-local)
    function _setInsurance(address lsa, uint256 insuranceId) internal {
        vm.prank(admin);
        loanContract.updateInsuranceId(lsa, insuranceId);
    }

    // ============ State Management ============

    /// @notice Reverts to base snapshot for test isolation
    function _resetState() internal {
        vm.revertTo(_baseSnapshotId);
        _baseSnapshotId = vm.snapshotState();
    }
}
