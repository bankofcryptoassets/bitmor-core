// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {LoanUnitTestBase} from "../../base/LoanUnitTestBase.sol";
import {TestConstants as TC} from "../../helpers/TestConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {Loan} from "@bitmor/protocol/Loan.sol";

/// @title BaseLoanTest
/// @author Bitmor Protocol
/// @notice Shared base contract for all Loan test suites providing snapshot structs, constants, and reusable helpers
/// @dev Extends `LoanUnitTestBase` with before/after state capture, liquidation setup, and compatibility wrappers
abstract contract BaseLoanTest is LoanUnitTestBase {
    using FixedPointMathLib for uint256;

    // ============ Test Actors (inherited from LoanUnitTestBase) ============
    // user, liquidator are inherited

    // ============ Protocol Addresses (aliases for inherited state) ============
    address internal debtAsset;
    address internal collateralAsset;
    address internal btc;
    address internal s_bitmorPool;
    address internal s_addressesProvider;
    address internal aavePool;

    // ============ Protocol Parameters ============
    uint256 internal s_gracePeriod;

    // ============ Constants (aliased from TestConstants) ============
    uint256 internal constant PREMIUM_AMOUNT = TC.PREMIUM_AMOUNT;
    bytes internal constant DATA = "0xLOAN";
    uint256 internal constant USER_USDC_FUNDING = TC.USER_USDC_BALANCE;
    uint256 internal constant LOAN_REPAYMENT_INTERVAL = TC.ONE_MONTH;
    uint256 internal constant STANDARD_COLLATERAL_AMOUNT = TC.STANDARD_COLLATERAL;
    uint256 internal constant STANDARD_DURATION = TC.STANDARD_DURATION;
    uint256 internal constant RAY = TC.RAY;
    uint256 internal constant BPS_DENOMINATOR = TC.BPS_DENOMINATOR;
    uint256 internal constant PRECISION = TC.PRECISION;
    uint256 internal constant OVERPAY_AMOUNT = TC.OVERPAY_AMOUNT;
    uint256 internal constant PRICE_DROP_50_PERCENT = TC.PRICE_DROP_FULL;
    uint256 internal constant PRICE_DROP_FOR_LIQUIDATION = 20;
    uint256 internal constant ONE_DAY = TC.ONE_DAY;
    uint256 internal constant LIQUIDATION_TYPE_NONE = TC.LIQUIDATION_TYPE_NONE;
    uint256 internal constant LIQUIDATION_TYPE_FULL = TC.LIQUIDATION_TYPE_FULL;
    uint256 internal constant LIQUIDATION_TYPE_MICRO = TC.LIQUIDATION_TYPE_MICRO;
    uint256 internal constant BTC_SEED_AMOUNT = TC.BTC_SEED_AMOUNT;
    uint256 internal constant POOL_DEPOSIT_AMOUNT = TC.POOL_DEPOSIT_AMOUNT;
    uint256 internal constant SMALL_BORROW_AMOUNT = TC.SMALL_BORROW_AMOUNT;
    uint256 internal constant MAX_APR_BPS = TC.MAX_APR_BPS;
    uint256 internal constant PAYMENT_TOLERANCE = TC.PAYMENT_TOLERANCE;
    uint256 internal constant DEBT_DUST_THRESHOLD = TC.DEBT_DUST_THRESHOLD;

    // ============ Flash Loan Test Parameters ============
    uint256 internal constant FLASH_LOAN_AMOUNT = TC.FLASH_LOAN_AMOUNT;
    uint256 internal constant FLASH_LOAN_PREMIUM = TC.FLASH_LOAN_PREMIUM;
    uint256 internal constant TEST_BTC_SWAP_AMOUNT = TC.TEST_BTC_SWAP_AMOUNT;
    uint256 internal constant TEST_PRECLOSURE_FEE = TC.TEST_PRECLOSURE_FEE;
    uint256 internal constant TEST_REPAYMENT_SHORTFALL = TC.TEST_REPAYMENT_SHORTFALL;

    // ============ Generic Test Snapshot Structs ============

    /// @notice Generic test state snapshot for capturing loan before/after state
    /// @dev Fields prefixed `Before`/`After` are populated by `_captureTestSnapshot` and `_updateTestSnapshotAfter`
    struct TestSnapshot {
        address lsa;
        uint256 debtBefore;
        uint256 debtAfter;
        uint256 collateralBefore;
        uint256 collateralAfter;
        uint256 durationBefore;
        uint256 durationAfter;
        uint256 lastPaymentBefore;
        uint256 lastPaymentAfter;
        DataTypes.LoanStatus statusBefore;
        DataTypes.LoanStatus statusAfter;
        uint256 estimatedMonthlyPayment;
    }

    /// @notice Liquidator-specific balance snapshot for liquidation tests
    struct LiquidatorSnapshot {
        uint256 liquidatorDebtBefore;
        uint256 liquidatorDebtAfter;
        uint256 liquidatorCollateralBefore;
        uint256 liquidatorCollateralAfter;
    }

    /// @notice Account balance snapshot capturing debt and collateral asset balances for any address
    struct AccountBalanceSnapshot {
        uint256 debtAssetBalance;
        uint256 collateralAssetBalance;
    }

    /// @notice LSA position snapshot capturing debt token and aToken balances
    struct LsaPositionSnapshot {
        uint256 debt;
        uint256 collateral;
    }

    /// @notice Extended liquidation test state combining loan, liquidator, and price snapshots
    struct LiquidationTestState {
        TestSnapshot loanState;
        LiquidatorSnapshot liquidatorState;
        uint256 debtPaid;
        uint256 collateralReceived;
        uint256 btcPriceUSD;
        uint256 usdcPriceUSD;
        uint256 monthsLiquidated;
        uint256 totalDebtPaid;
        uint256 totalCollateralReceived;
        uint256 fullLiqDebtPaid;
        uint256 fullLiqCollateralReceived;
        bool fullLiquidationExecuted;
    }

    /// @notice User balance snapshot for close loan tests tracking debt and collateral asset deltas
    struct UserBalanceSnapshot {
        uint256 userDebtAssetBefore;
        uint256 userDebtAssetAfter;
        uint256 userCollateralBefore;
        uint256 userCollateralAfter;
    }

    // ============ Setup ============

    function setUp() public virtual override {
        super.setUp();

        // Set up address aliases for backward compatibility
        debtAsset = address(mockUSDC);
        // Collateral is bvBTC (vault shares), btc is the underlying cbBTC
        collateralAsset = address(mockBTCVault);
        btc = address(mockCbBTC);
        s_bitmorPool = address(mockBitmorPool);
        s_addressesProvider = address(mockAddressesProvider);
        aavePool = address(mockAavePool);
        s_gracePeriod = config.getGracePeriod();
    }

    // ============ Modifiers ============

    /// @notice Modifier to mint debt asset to user and approve loan contract
    modifier mintDebtAssetToUser() {
        _mintDebtAssetToUser();
        _;
    }

    /// @notice Modifier to set up a standard loan for user (1 BTC, 12 months)
    modifier setUpLoanForUser() {
        _setUpLoanForUser();
        _;
    }

    // ============ Error Testing Helpers ============

    /// @notice Expects the next call to revert with the given error `selector`
    function _expectRevertSelector(bytes4 selector) internal {
        vm.expectRevert(selector);
    }

    /// @notice Expects the next call to revert with the given string `message`
    function _expectRevertMessage(string memory message) internal {
        vm.expectRevert(bytes(message));
    }

    /// @notice Expects the next call to revert with any error
    function _expectGenericRevert() internal {
        vm.expectRevert();
    }

    // ============ Internal Setup Helpers ============

    /// @notice Mints USDC to `user` and approves max spending on the `loan` contract
    function _mintDebtAssetToUser() internal {
        _fundUSDC(user, USER_USDC_FUNDING);
        vm.prank(user);
        mockUSDC.approve(address(loan), type(uint256).max);
    }

    /// @notice Creates a standard loan (1 BTC, 12 months) for `user` with the minimum required deposit
    function _setUpLoanForUser() internal {
        _mintDebtAssetToUser();
        (,, uint256 minDepositRequired) = loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);
        vm.prank(user);
        loan.initializeLoan(minDepositRequired, PREMIUM_AMOUNT, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, DATA);
    }

    // ============ Pause Helpers ============

    /// @notice Pauses the loan contract via LPM_FAST role
    function _pauseContract() internal {
        uint64 lpmFastRole = LPM_FAST_ID();
        vm.prank(admin);
        manager.grantRole(lpmFastRole, admin, 0);
        vm.prank(admin);
        loan.pause();
    }

    /// @notice Unpauses the loan contract via LPM_SLOW role (with delay)
    function _unpauseContract() internal {
        bytes memory data = abi.encodeCall(loan.unpause, ());
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);
    }

    // ============ Setter Helpers ============

    /// @notice Sets minimum BTC amount via LPM_SLOW role
    function _setMinBTCAmount(uint256 newMin) internal {
        bytes memory data = abi.encodeCall(loan.setMinBTCAmount, (newMin));
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);
    }

    /// @notice Sets maximum BTC amount via LPM_SLOW role
    function _setMaxBTCAmount(uint256 newMax) internal {
        bytes memory data = abi.encodeCall(loan.setMaxBTCAmount, (newMax));
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);
    }

    /// @notice Sets minimum deposit basis points via LPM_SLOW role
    function _setMinDepositBps(uint256 newBps) internal {
        bytes memory data = abi.encodeCall(loan.setMinDepositBps, (newBps));
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);
    }

    /// @notice Sets maximum loan duration via LPM_SLOW role
    function _setMaxDuration(uint256 newMax) internal {
        bytes memory data = abi.encodeCall(loan.setMaxDuration, (newMax));
        _scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);
    }

    // ============ Loan Creation Helpers ============

    /// @notice Creates a custom loan with explicit `deposit`, `premium`, `collateral`, and `duration`
    /// @return lsa The address of the created Loan Smart Account
    function _createCustomLoan(uint256 deposit, uint256 premium, uint256 collateral, uint256 duration)
        internal
        returns (address lsa)
    {
        _mintDebtAssetToUser();
        vm.prank(user);
        lsa = loan.initializeLoan(deposit, premium, collateral, duration, DATA);
    }

    /// @dev Inherited `_createStandardLoan` from LoanUnitTestBase uses TC constants

    /// @notice Creates a custom loan computing the minimum deposit from `btcAmount` and `duration`
    /// @return lsa The address of the created Loan Smart Account
    function _createCustomLoan(uint256 btcAmount, uint256 duration, uint256 premiumAmount)
        internal
        returns (address lsa)
    {
        _mintDebtAssetToUser();
        (,, uint256 minDeposit) = loan.getLoanDetails(btcAmount, duration);
        vm.prank(user);
        lsa = loan.initializeLoan(minDeposit, premiumAmount, btcAmount, duration, DATA);
    }

    /// @notice Creates a loan for a specific `borrower`, granting EXECUTOR role and funding USDC
    /// @return lsa The address of the created Loan Smart Account
    function _createLoanForBorrower(address borrower, uint256 btcAmount, uint256 duration, uint256 premiumAmount)
        internal
        returns (address lsa)
    {
        // Cache role ID before prank to avoid consuming the prank
        // (EXECUTOR_ID() makes external call to rolesData which would consume the prank)
        uint64 executorRoleId = EXECUTOR_ID();

        // Grant EXECUTOR role to borrower so they can call initializeLoan
        vm.prank(admin);
        manager.grantRole(executorRoleId, borrower, NO_DELAY);

        _fundUSDC(borrower, USER_USDC_FUNDING);
        vm.prank(borrower);
        mockUSDC.approve(address(loan), type(uint256).max);

        (,, uint256 minDeposit) = loan.getLoanDetails(btcAmount, duration);
        vm.prank(borrower);
        lsa = loan.initializeLoan(minDeposit, premiumAmount, btcAmount, duration, DATA);
    }

    /// @notice Creates a standard loan (1 BTC, 12 months) for a specific `borrower`
    function _createStandardLoanForBorrower(address borrower) internal returns (address lsa) {
        lsa = _createLoanForBorrower(borrower, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, PREMIUM_AMOUNT);
    }

    /// @notice Creates a standard loan and returns both the LSA address and the loan data struct
    function _createStandardLoanWithData() internal returns (address lsa, DataTypes.LoanData memory loanData) {
        _mintDebtAssetToUser();
        (,, uint256 minDeposit) = loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);
        vm.prank(user);
        lsa = loan.initializeLoan(minDeposit, PREMIUM_AMOUNT, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, DATA);
        loanData = loan.getLoanByLSA(lsa);
    }

    // ============ Consolidated Helper Wrappers ============

    /// @notice Warps block timestamp past the configured grace period
    function _warpPastGracePeriod() internal {
        vm.warp(block.timestamp + s_gracePeriod + 1);
    }

    /// @notice Funds `liquidator` with USDC and approves max spending on the Bitmor pool
    function _fundLiquidator() internal {
        _fundUSDC(liquidator, USER_USDC_FUNDING);
        vm.prank(liquidator);
        mockUSDC.approve(address(mockBitmorPool), type(uint256).max);
    }

    // ============ Balance Snapshot Helpers ============

    /// @notice Captures current debt and collateral asset balances for `account`
    function _snapshotAccountBalances(address account) internal view returns (AccountBalanceSnapshot memory snapshot) {
        snapshot.debtAssetBalance = IERC20(debtAsset).balanceOf(account);
        snapshot.collateralAssetBalance = IERC20(collateralAsset).balanceOf(account);
    }

    /// @notice Captures the LSA's current debt and collateral (aToken) balances
    function _snapshotLsaPositions(address lsa) internal view returns (LsaPositionSnapshot memory snapshot) {
        snapshot.debt = _getDebtBalance(lsa);
        snapshot.collateral = _getCollateralBalance(lsa);
    }

    /// @notice Returns the liquidator's current debt and collateral asset balances
    function _snapshotLiquidatorBalances() internal view returns (uint256 debtBalance, uint256 collateralBalance) {
        AccountBalanceSnapshot memory snapshot = _snapshotAccountBalances(liquidator);
        debtBalance = snapshot.debtAssetBalance;
        collateralBalance = snapshot.collateralAssetBalance;
    }

    /// @notice Returns the user's current debt and collateral asset balances
    function _snapshotUserBalances() internal view returns (uint256 debtBalance, uint256 collateralBalance) {
        AccountBalanceSnapshot memory snapshot = _snapshotAccountBalances(user);
        debtBalance = snapshot.debtAssetBalance;
        collateralBalance = snapshot.collateralAssetBalance;
    }

    /// @notice Captures the "before" state for a loan at `lsa` into a `TestSnapshot`
    function _captureTestSnapshot(address lsa) internal view returns (TestSnapshot memory snapshot) {
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);

        snapshot.lsa = lsa;
        snapshot.debtBefore = _getDebtBalance(lsa);
        snapshot.collateralBefore = _getCollateralBalance(lsa);
        snapshot.durationBefore = loanData.duration;
        snapshot.lastPaymentBefore = loanData.lastPaymentTimestamp;
        snapshot.statusBefore = loanData.status;
        snapshot.estimatedMonthlyPayment = loanData.estimatedMonthlyPayment;
    }

    /// @notice Populates the "after" fields of an existing `TestSnapshot` with current state from `lsa`
    function _updateTestSnapshotAfter(TestSnapshot memory snapshot, address lsa) internal view {
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);

        snapshot.debtAfter = _getDebtBalance(lsa);
        snapshot.collateralAfter = _getCollateralBalance(lsa);
        snapshot.durationAfter = loanData.duration;
        snapshot.lastPaymentAfter = loanData.lastPaymentTimestamp;
        snapshot.statusAfter = loanData.status;
    }

    /// @notice Captures the liquidator's "before" balances into a `LiquidatorSnapshot`
    function _captureLiquidatorSnapshot() internal view returns (LiquidatorSnapshot memory snapshot) {
        (snapshot.liquidatorDebtBefore, snapshot.liquidatorCollateralBefore) = _snapshotLiquidatorBalances();
    }

    /// @notice Populates the "after" fields of an existing `LiquidatorSnapshot`
    function _updateLiquidatorSnapshotAfter(LiquidatorSnapshot memory snapshot) internal view {
        (snapshot.liquidatorDebtAfter, snapshot.liquidatorCollateralAfter) = _snapshotLiquidatorBalances();
    }

    /// @notice Captures the user's "before" balances into a `UserBalanceSnapshot`
    function _captureUserBalanceSnapshot() internal view returns (UserBalanceSnapshot memory snapshot) {
        (snapshot.userDebtAssetBefore, snapshot.userCollateralBefore) = _snapshotUserBalances();
    }

    /// @notice Populates the "after" fields of an existing `UserBalanceSnapshot`
    function _updateUserBalanceSnapshotAfter(UserBalanceSnapshot memory snapshot) internal view {
        (snapshot.userDebtAssetAfter, snapshot.userCollateralAfter) = _snapshotUserBalances();
    }

    // ============ Liquidation Helpers ============

    /// @notice Executes a micro-liquidation on `lsa` as the `liquidator`
    function _executeMicroLiquidation(address lsa) internal {
        bytes memory data = abi.encode(collateralAsset, debtAsset, lsa);
        vm.prank(liquidator);
        mockBitmorPool.microLiquidationCall(data);
    }

    /// @notice Executes a full liquidation on `lsa` as the `liquidator`
    function _executeFullLiquidation(address lsa, uint256 debtToCover, bool receiveAToken) internal {
        vm.prank(liquidator);
        mockBitmorPool.liquidationCall(collateralAsset, debtAsset, lsa, debtToCover, receiveAToken);
    }

    /// @notice Returns the current liquidation type for `lsa` (0=none, 1=full, 2=micro)
    function _checkLiquidationType(address lsa) internal view returns (uint256) {
        return mockBitmorPool.checkTypeOfLiquidation(lsa);
    }

    /// @notice Returns the current mock oracle price for BTC
    function _getBtcPrice() internal view returns (uint256) {
        return mockOracle.getAssetPrice(address(mockCbBTC));
    }

    /// @notice Returns the current mock oracle price for USDC
    function _getUsdcPrice() internal view returns (uint256) {
        return mockOracle.getAssetPrice(debtAsset);
    }

    /// @dev Drop oracle price for any asset (overload for compatibility)
    function _dropOraclePrice(address asset, uint256 dropPercent) internal returns (uint256 newPrice) {
        newPrice = mockOracle.dropPrice(asset, dropPercent);
    }

    // ============ Liquidation State Capture Helpers ============

    /// @notice Captures full pre-liquidation state including loan, liquidator, and oracle prices
    function _captureLiquidationStateBefore(address lsa) internal view returns (LiquidationTestState memory state) {
        state.loanState = _captureTestSnapshot(lsa);
        state.liquidatorState = _captureLiquidatorSnapshot();
        state.btcPriceUSD = _getBtcPrice();
        state.usdcPriceUSD = _getUsdcPrice();
    }

    /// @notice Populates "after" fields and computes `debtPaid` / `collateralReceived` deltas
    function _updateLiquidationStateAfter(LiquidationTestState memory state, address lsa) internal view {
        _updateTestSnapshotAfter(state.loanState, lsa);
        _updateLiquidatorSnapshotAfter(state.liquidatorState);

        state.debtPaid = state.liquidatorState.liquidatorDebtBefore - state.liquidatorState.liquidatorDebtAfter;
        state.collateralReceived =
            state.liquidatorState.liquidatorCollateralAfter - state.liquidatorState.liquidatorCollateralBefore;
    }

    // ============ Liquidation Setup Helpers ============

    /// @notice Composite helper: warps time, funds liquidator, sets overdue state, and configures micro-liquidation
    function _setupForMicroLiquidation(address lsa) internal returns (uint256 liquidationType) {
        _updateAddressesProviderBitmorLoan();
        _warpPastGracePeriod();
        _fundLiquidator();
        // Set overdue state in mock for computed liquidation type
        mockBitmorPool.setUserOverdue(lsa, true);
        _setLiquidationType(lsa, LIQUIDATION_TYPE_MICRO);
        liquidationType = _checkLiquidationType(lsa);
    }

    /// @notice Composite helper: warps time, funds liquidator, drops price, and configures full liquidation
    function _setupForFullLiquidation(address lsa, uint256 priceDrop) internal returns (uint256 liquidationType) {
        _updateAddressesProviderBitmorLoan();
        _warpPastGracePeriod();
        _fundLiquidator();
        _dropOraclePrice(priceDrop);
        // Set health factor < 1 in mock for computed liquidation type
        mockBitmorPool.setHealthFactor(lsa, 0.5e18);
        _setLiquidationType(lsa, LIQUIDATION_TYPE_FULL);
        liquidationType = _checkLiquidationType(lsa);
    }

    /// @notice Composite helper: sets up full liquidation with default 50% price drop
    function _setupForFullLiquidation(address lsa) internal returns (uint256 liquidationType) {
        liquidationType = _setupForFullLiquidation(lsa, PRICE_DROP_50_PERCENT);
    }

    /// @notice Sets up full liquidation without time warp (price drop only, loan not overdue)
    function _setupForFullLiquidationNoWarp(address lsa, uint256 priceDrop) internal returns (uint256 liquidationType) {
        _updateAddressesProviderBitmorLoan();
        _fundLiquidator();
        _dropOraclePrice(priceDrop);
        // Set health factor < 1 in mock for computed liquidation type
        mockBitmorPool.setHealthFactor(lsa, 0.5e18);
        _setLiquidationType(lsa, LIQUIDATION_TYPE_FULL);
        liquidationType = _checkLiquidationType(lsa);
    }

    // ============ Utility Helpers for Test Compatibility ============

    /// @dev Seed user and approve (compatibility with old Utilities pattern)
    function _utilSeedUserAndApprove(address _user, address token, address spender, uint256 amount) internal {
        if (token == debtAsset) {
            _fundUSDC(_user, amount);
        } else if (token == collateralAsset) {
            _fundCbBTC(_user, amount);
        }
        vm.prank(_user);
        IERC20(token).approve(spender, type(uint256).max);
    }

    /// @dev Create loan utility (compatibility with old Utilities pattern)
    function _utilCreateLoan(
        Loan _loan,
        address _user,
        uint256 collateral,
        uint256 duration,
        uint256 premium,
        bytes memory data
    ) internal returns (address lsa, DataTypes.LoanData memory loanData) {
        (,, uint256 minDeposit) = _loan.getLoanDetails(collateral, duration);
        vm.prank(_user);
        lsa = _loan.initializeLoan(minDeposit, premium, collateral, duration, data);
        loanData = _loan.getLoanByLSA(lsa);
    }

    /// @dev Assert LSA ownership (compatibility with old Utilities pattern)
    /// @param lsa The loan smart account address
    /// @param _expectedOwner Unused, kept for API compatibility
    /// @param expectedBorrower Expected borrower address
    function _utilAssertLSAOwnership(address lsa, address _expectedOwner, address expectedBorrower) internal view {
        _expectedOwner; // Silence unused parameter warning
        // LSA should be owned by loan contract
        // Just check the loan data has correct borrower
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(loanData.borrower, expectedBorrower, "LSA borrower mismatch");
    }

    // ============ Additional Compatibility Helpers ============

    /// @dev Get LSA debt balance (alias for _getDebtBalance)
    function _getLsaDebtBalance(address lsa) internal view returns (uint256) {
        return _getDebtBalance(lsa);
    }

    /// @dev Get aToken address for an asset from pool reserves
    function _utilGetATokenAddress(address, address asset) internal view returns (address) {
        DataTypes.ReserveData memory reserve = mockBitmorPool.getReserveData(asset);
        return reserve.aTokenAddress;
    }

    /// @dev Get debt token address for debt asset (USDC)
    function _getDebtATokenAddress() internal view returns (address) {
        DataTypes.ReserveData memory reserve = mockBitmorPool.getReserveData(debtAsset);
        return reserve.variableDebtTokenAddress;
    }

    /// @dev Update addresses provider with current loan address
    function _updateAddressesProviderBitmorLoan() internal {
        mockAddressesProvider.setBitmorLoan(address(loan));
    }

    /// @dev Mint tokens to liquidator without approval
    function _utilMintToLiquidatorNoApproval(address _liquidator, address token, uint256 amount) internal {
        if (token == debtAsset) {
            _fundUSDC(_liquidator, amount);
        } else if (token == collateralAsset) {
            mockBTCVault.mint(_liquidator, amount);
        } else if (token == btc) {
            _fundCbBTC(_liquidator, amount);
        }
    }

    /// @dev Mint tokens to any address (compatibility helper)
    function _utilMintTokenTo(address token, address to, uint256 amount) internal {
        if (token == debtAsset) {
            _fundUSDC(to, amount);
        } else if (token == collateralAsset) {
            mockBTCVault.mint(to, amount);
        } else if (token == btc) {
            _fundCbBTC(to, amount);
        }
    }

    /// @dev Mint tokens and approve max to spender (compatibility helper)
    function _utilMintTokenAndApproveMax(address token, address to, address spender, uint256 amount) internal {
        _utilMintTokenTo(token, to, amount);
        vm.prank(to);
        IERC20(token).approve(spender, type(uint256).max);
    }

    /// @dev Mint tokens and approve specific amount to spender
    function _utilMintTokenAndApprove(address token, address to, address spender, uint256 amount) internal {
        _utilMintTokenTo(token, to, amount);
        vm.prank(to);
        IERC20(token).approve(spender, amount);
    }

    /// @dev Set oracle price for an asset (compatibility helper)
    function _utilSetOraclePrice(address, address asset, uint256 price) internal {
        mockOracle.setAssetPrice(asset, price);
    }

    /// @dev Warp past the repayment interval (one month)
    function _utilWarpPastRepaymentInterval() internal {
        vm.warp(block.timestamp + LOAN_REPAYMENT_INTERVAL + 1);
    }

    /// @dev Return minimum of two values
    function _utilMin(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /// @dev Calculate expected collateral seized for a given debt amount
    function _calculateExpectedCollateralSeized(uint256 debtAmount) internal view returns (uint256) {
        uint256 btcPrice = _getBtcPrice();
        uint256 usdcPrice = _getUsdcPrice();
        uint256 bonus = _getLiquidationBonus();
        // Convert debt to collateral value with bonus
        return (debtAmount * usdcPrice * 1e8 * bonus) / (btcPrice * 1e6 * 10000);
    }

    /// @dev Get liquidation bonus from lending pool (105% = 10500 bps)
    function _getLiquidationBonus() internal view returns (uint256) {
        DataTypes.ReserveConfigurationMap memory config = mockBitmorPool.getConfiguration(collateralAsset);
        // Liquidation bonus is at bits 32-47
        return (config.data >> 32) & 0xFFFF;
    }
}
