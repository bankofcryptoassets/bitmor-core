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

    // Snapshots
    uint256 internal _baseSnapshotId;
    uint256 internal _preSeededSnapshotId;
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

        // 6. Snapshot BEFORE any liquidity seeding (for tests needing empty BLP)
        _preSeededSnapshotId = vm.snapshot();

        // 7. Setup test user (fund tokens, approve, grant EXECUTOR role)
        _setupTestUser();

        // 8. Snapshot AFTER seeding (standard test baseline)
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
    ///      We prank as the Loan contract to make the deposit, but send the resulting
    ///      bvBTC shares to a dedicated seeder address (NOT the Loan contract) to avoid
    ///      leaving residual bvBTC in the Loan contract that pollutes token balance assertions.
    function _seedBTCVault() internal {
        address vaultSeeder = makeAddr("vaultSeeder");
        uint256 seedAmount = TC.STANDARD_COLLATERAL;
        _fundCbBTC(address(loanContract), seedAmount);
        vm.startPrank(address(loanContract));
        cbBTC.approve(address(btcVault), seedAmount);
        btcVault.deposit(seedAmount, vaultSeeder);
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
    function _createStandardLoanWithData() internal returns (address lsa, DataTypes.LoanData memory loanData) {
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
        (bool ok, bytes memory data) = oracle.staticcall(abi.encodeWithSignature("getAssetPrice(address)", asset));
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

    /// @notice Decodes BLP getReserveData into the 4 commonly-needed fields
    /// @dev Single decode point for the 12-field Aave V2 ReserveData struct
    function _getReserveDataDecoded(address asset)
        internal
        view
        returns (uint128 liqIndex, uint128 borrowIndex, address aToken, address vdt)
    {
        (bool ok, bytes memory data) = bitmorPool.staticcall(abi.encodeWithSignature("getReserveData(address)", asset));
        require(ok, "getReserveData failed");
        // Aave V2 ReserveData: config, liqIdx, borrowIdx, liqRate, varBorrowRate,
        // stableBorrowRate, lastUpdateTs, aToken, stableDebtToken, variableDebtToken, IRS, id
        (, liqIndex, borrowIndex,,,,, aToken,, vdt,,) = abi.decode(
            data,
            (uint256, uint128, uint128, uint128, uint128, uint128, uint40, address, address, address, address, uint8)
        );
    }

    /// @notice Gets the USDC-denominated debt balance for an LSA (includes accrued interest)
    function _getDebtBalanceUSDC(address lsa) internal view returns (uint256 debt) {
        (,,, address vdt) = _getReserveDataDecoded(address(usdc));
        (bool ok, bytes memory data) = vdt.staticcall(abi.encodeWithSignature("balanceOf(address)", lsa));
        require(ok, "VDT balanceOf failed");
        debt = abi.decode(data, (uint256));
    }

    /// @notice Gets the scaled (principal-only) debt balance for an LSA
    function _getScaledDebtBalance(address lsa) internal view returns (uint256 scaledDebt) {
        (,,, address vdt) = _getReserveDataDecoded(address(usdc));
        (bool ok, bytes memory data) = vdt.staticcall(abi.encodeWithSignature("scaledBalanceOf(address)", lsa));
        require(ok, "VDT scaledBalanceOf failed");
        scaledDebt = abi.decode(data, (uint256));
    }

    /// @notice Gets the variable borrow index for USDC from the BLP
    function _getVariableBorrowIndex() internal view returns (uint256 index) {
        (, uint128 borrowIndex,,) = _getReserveDataDecoded(address(usdc));
        index = uint256(borrowIndex);
    }

    /// @notice Gets the aToken (collateral) balance for an LSA in the BLP
    function _getATokenBalance(address lsa) internal view returns (uint256 balance) {
        (,, address aTokenAddr,) = _getReserveDataDecoded(address(btcVault));
        (bool ok, bytes memory data) = aTokenAddr.staticcall(abi.encodeWithSignature("balanceOf(address)", lsa));
        require(ok, "aToken balanceOf failed");
        balance = abi.decode(data, (uint256));
    }

    /// @notice Gets the total scaled debt supply (sum of all scaledBalanceOf) for USDC
    function _getTotalScaledDebtSupply() internal view returns (uint256 totalScaled) {
        (,,, address vdt) = _getReserveDataDecoded(address(usdc));
        (bool ok, bytes memory data) = vdt.staticcall(abi.encodeWithSignature("scaledTotalSupply()"));
        require(ok, "VDT scaledTotalSupply failed");
        totalScaled = abi.decode(data, (uint256));
    }

    /// @notice Gets the liquidity index for an asset from BLP reserve data
    function _getLiquidityIndex(address asset) internal view returns (uint256 index) {
        (uint128 liqIndex,,,) = _getReserveDataDecoded(asset);
        index = uint256(liqIndex);
    }

    /// @notice Gets the BLP's available liquidity for an asset (token balance held by aToken contract)
    /// @dev In Aave V2, the LendingPool never holds underlying tokens - the aToken contract does
    function _getBLPAvailableLiquidity(address asset) internal view returns (uint256) {
        (,, address aTokenAddr,) = _getReserveDataDecoded(asset);
        return IERC20(asset).balanceOf(aTokenAddr);
    }

    /// @notice Asserts that the Loan contract holds zero USDC and zero cbBTC
    function _assertLoanContractIsEmpty(string memory context) internal view {
        assertEq(usdc.balanceOf(address(loanContract)), 0, string.concat("Loan USDC non-zero: ", context));
        assertEq(cbBTC.balanceOf(address(loanContract)), 0, string.concat("Loan cbBTC non-zero: ", context));
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
        (success,) = bitmorPool.call(abi.encodeWithSignature("microLiquidationCall(bytes)", mlData));
    }

    /// @notice Triggers a full liquidation on the BLP for a given LSA
    /// @dev Caller must call _setupLiquidator() before using this helper.
    /// @return success Whether the call succeeded
    function _triggerFullLiquidation(address lsa) internal returns (bool success) {
        vm.prank(testLiquidator);
        (success,) = bitmorPool.call(
            abi.encodeWithSignature(
                "liquidationCall(address,address,address,uint256,bool)",
                address(btcVault),
                address(usdc),
                lsa,
                type(uint256).max,
                false
            )
        );
    }

    /// @notice Triggers a full liquidation with a specific debtToCover amount (partial coverage)
    /// @dev Caller must call _setupLiquidator() before using this helper.
    /// @return success Whether the call succeeded
    function _triggerFullLiquidationPartial(address lsa, uint256 debtToCover) internal returns (bool success) {
        vm.prank(testLiquidator);
        (success,) = bitmorPool.call(
            abi.encodeWithSignature(
                "liquidationCall(address,address,address,uint256,bool)",
                address(btcVault),
                address(usdc),
                lsa,
                debtToCover,
                false
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

    // ============ Shared Test Helpers ============

    /// @notice Donates cbBTC to the AaveTokenizedStrategy by supplying to the external Aave pool
    ///         on behalf of the strategy address, inflating the strategy's aToken balance.
    /// @param amount The amount of cbBTC (8 decimals) to donate
    function _donateToStrategy(uint256 amount) internal {
        address strategyAddr = config.getAaveTokenizedStrategy();
        address donator = makeAddr("donator");
        _fundCbBTC(donator, amount);

        vm.prank(donator);
        cbBTC.approve(aaveV3Pool, amount);

        vm.prank(donator);
        (bool ok,) = aaveV3Pool.call(
            abi.encodeWithSignature("supply(address,uint256,address,uint16)", address(cbBTC), amount, strategyAddr, 0)
        );
        require(ok, "strategy donation via Aave supply failed");
    }

    /// @notice Advances time and makes N monthly payments
    function _makeMonthlyPayments(address lsa, uint256 monthlyPayment, uint256 count) internal {
        for (uint256 i = 0; i < count; i++) {
            _advanceDays(30);
            _repayLoan(lsa, testUser, monthlyPayment);
        }
    }

    /// @notice Ensures testUser has enough USDC for all remaining monthly payments
    function _ensureSufficientUSDC(uint256 monthlyPayment, uint256 paymentsRemaining) internal {
        uint256 totalNeeded = monthlyPayment * paymentsRemaining;
        uint256 currentBalance = usdc.balanceOf(testUser);
        if (currentBalance < totalNeeded) {
            _fundUSDC(testUser, totalNeeded - currentBalance);
        }
    }

    /// @notice Closes a loan early by funding the payer with enough USDC and calling closeLoan
    function _closeLoanEarly(address lsa, address payer, bool withdrawInBTC) internal {
        DataTypes.LoanData memory ld = loanContract.getLoanByLSA(lsa);
        uint256 closeBuffer = ld.loanAmount * 2;
        uint256 currentBalance = usdc.balanceOf(payer);
        if (currentBalance < closeBuffer) {
            _fundUSDC(payer, closeBuffer - currentBalance);
        }
        vm.prank(payer);
        usdc.approve(address(loanContract), type(uint256).max);
        vm.prank(payer);
        loanContract.closeLoan(lsa, withdrawInBTC);
    }

    /// @notice Fully repays a loan via repay() so status becomes Completed
    /// @dev Passes `type(uint256).max` to avoid stale-read race
    function _fullyRepayLoan(address lsa) internal {
        uint256 totalDebt = _getDebtBalanceUSDC(lsa);
        require(totalDebt > 0, "fullyRepayLoan: no debt to repay");

        uint256 buffer = totalDebt / 100 + 1e6; // 1% + 1 USDC
        uint256 userBal = usdc.balanceOf(testUser);
        if (userBal < totalDebt + buffer) {
            _fundUSDC(testUser, totalDebt + buffer - userBal);
            vm.prank(testUser);
            usdc.approve(address(loanContract), type(uint256).max);
        }

        _repayLoan(lsa, testUser, type(uint256).max);
    }

    /// @notice Executes N micro-liquidations by advancing time and triggering each one
    function _executeMicroLiquidations(address lsa, uint256 count) internal {
        for (uint256 i = 0; i < count; i++) {
            if (i == 0) {
                _makeFirstPaymentOverdue();
            } else {
                vm.warp(block.timestamp + TC.REPAYMENT_INTERVAL + config.getGracePeriod() + 1);
            }

            uint256 liquidationType = _checkTypeOfLiquidation(lsa);
            require(liquidationType == TC.LIQUIDATION_TYPE_MICRO, "not micro-liquidatable");

            bool success = _triggerMicroLiquidation(lsa);
            require(success, "microLiquidationCall failed");
        }
    }

    /// @notice Gets the pre-closure fee in basis points
    function _getPreClosureFeeBps() internal view returns (uint256) {
        return loanContract.getPreClosureFee();
    }

    /// @notice Force BLP reserve indices to update by doing a tiny deposit
    /// @dev Aave V2 only updates indices on interactions, not on time advance.
    function _pokeReserveIndex() internal {
        uint256 pokeAmount = 1e6; // 1 USDC
        address poker = makeAddr("indexPoker");
        _fundUSDC(poker, pokeAmount);
        vm.prank(poker);
        IERC20(address(usdc)).approve(address(usdcVault), pokeAmount);
        vm.prank(poker);
        usdcVault.deposit(pokeAmount, poker);
    }

    /// @notice Reverts to pre-seeded snapshot (empty BLP) and sets up user without BLP seeding
    function _resetStateWithoutBLP() internal {
        vm.revertTo(_preSeededSnapshotId);
        _preSeededSnapshotId = vm.snapshotState();
        _setupUserWithoutBLP(testUser);
    }

    // ============ Composite Helpers ============

    /// @notice Result of a liquidation execution with balance deltas
    struct LiquidationResult {
        bool success;
        uint256 cbBTCReceived;
        uint256 usdcPaid;
    }

    /// @notice Executes a micro-liquidation and captures the liquidator's balance deltas
    function _executeMicroLiquidationAndCapture(address lsa) internal returns (LiquidationResult memory result) {
        uint256 cbBTCBefore = cbBTC.balanceOf(testLiquidator);
        uint256 usdcBefore = usdc.balanceOf(testLiquidator);
        result.success = _triggerMicroLiquidation(lsa);
        result.cbBTCReceived = cbBTC.balanceOf(testLiquidator) - cbBTCBefore;
        result.usdcPaid = usdcBefore - usdc.balanceOf(testLiquidator);
    }

    /// @notice Executes a full liquidation and captures the liquidator's balance deltas
    function _executeFullLiquidationAndCapture(address lsa) internal returns (LiquidationResult memory result) {
        uint256 cbBTCBefore = cbBTC.balanceOf(testLiquidator);
        uint256 usdcBefore = usdc.balanceOf(testLiquidator);
        result.success = _triggerFullLiquidation(lsa);
        result.cbBTCReceived = cbBTC.balanceOf(testLiquidator) - cbBTCBefore;
        result.usdcPaid = usdcBefore - usdc.balanceOf(testLiquidator);
    }

    /// @notice Sets the BTCVault exit fee via AccessManager role setup
    /// @dev Automatically sets a default fee recipient if feeBps > 0 and none is configured
    function _setExitFee(uint256 feeBps) internal {
        if (feeBps > 0 && btcVault.getFeeRecipient() == address(0)) {
            _setFeeRecipient(makeAddr("defaultFeeCollector"));
        }
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = btcVault.setExitFee.selector;
        uint64 bvmFastId = BVM_FAST_ID();
        vm.startPrank(admin);
        manager.setTargetFunctionRole(address(btcVault), selectors, bvmFastId);
        manager.grantRole(bvmFastId, admin, 0);
        vm.stopPrank();
        vm.prank(admin);
        btcVault.setExitFee(feeBps);
    }

    /// @notice Sets the BTCVault fee recipient via AccessManager role setup
    /// @dev Remaps setFeeRecipient.selector to BVM_FAST for zero-delay access in tests
    function _setFeeRecipient(address recipient) internal {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = btcVault.setFeeRecipient.selector;
        uint64 bvmFastId = BVM_FAST_ID();
        vm.startPrank(admin);
        manager.setTargetFunctionRole(address(btcVault), selectors, bvmFastId);
        manager.grantRole(bvmFastId, admin, 0);
        vm.stopPrank();
        vm.prank(admin);
        btcVault.setFeeRecipient(recipient);
    }

    /// @notice Sets the liquidation fee and collector via schedule-and-execute
    function _setLiquidationFee(uint256 feeBps, address collector) internal {
        _scheduleAndExecute(
            address(loanContract), admin, LPM_SLOW_ID(), abi.encodeCall(loanContract.setLiquidationFeeBps, (feeBps))
        );
        _scheduleAndExecute(
            address(loanContract),
            admin,
            LPM_SLOW_ID(),
            abi.encodeCall(loanContract.setLiquidationFeeCollector, (collector))
        );
    }

    /// @notice Creates a standard loan and makes N monthly payments
    function _createLoanAndMakePayments(uint256 paymentCount)
        internal
        returns (address lsa, DataTypes.LoanData memory loanData)
    {
        (lsa, loanData) = _createStandardLoanWithData();
        _ensureSufficientUSDC(loanData.estimatedMonthlyPayment, TC.STANDARD_DURATION);
        _makeMonthlyPayments(lsa, loanData.estimatedMonthlyPayment, paymentCount);
    }

    /// @notice Creates a standard loan with insurance ID 1
    function _createInsuredLoan() internal returns (address lsa) {
        lsa = _createStandardLoan();
        _setInsurance(lsa, 1);
    }

    // ============ State Management ============

    /// @notice Reverts to base snapshot for test isolation
    function _resetState() internal {
        vm.revertTo(_baseSnapshotId);
        _baseSnapshotId = vm.snapshotState();
    }
}
