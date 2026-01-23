// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {UnitTestBase} from "./UnitTestBase.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";

// Protocol contracts
import {Loan} from "@bitmor/protocol/Loan.sol";
import {LoanVault} from "@bitmor/protocol/LoanVault.sol";
import {LoanVaultFactory} from "@bitmor/protocol/LoanVaultFactory.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

// Mock contracts
import {MockBitmorLendingPool} from "../mock/MockBitmorLendingPool.sol";
import {MockPriceOracle} from "../mock/MockPriceOracle.sol";
import {MockAddressesProvider} from "../mock/MockAddressesProvider.sol";
import {MockAToken} from "../mock/MockAToken.sol";
import {MockVariableDebtToken} from "../mock/MockVariableDebtToken.sol";
import {MockSwapAdapter} from "../mock/MockSwapAdapter.sol";
import {MockInterestRateStrategy} from "../mock/MockInterestRateStrategy.sol";

/// @title LoanUnitTestBase
/// @notice Base for Loan contract unit tests with comprehensive mock dependencies
/// @dev Deploys real Loan contract with full mock infrastructure for lending pool
abstract contract LoanUnitTestBase is UnitTestBase {
    // ============ Loan Infrastructure ============
    Loan public loan;
    LoanVaultFactory public loanVaultFactory;
    address public loanVaultImplementation;

    // ============ Test Actors ============
    address public user;
    address public liquidator;

    // ============ Protocol Addresses ============
    address public premiumCollector;

    // ============ Mock Infrastructure ============
    MockBitmorLendingPool public mockBitmorPool;
    MockPriceOracle public mockOracle;
    MockAddressesProvider public mockAddressesProvider;
    MockSwapAdapter public mockSwapAdapter;

    // Mock tokens for lending pool
    MockAToken public mockATokenCbBTC;
    MockAToken public mockATokenUSDC;
    MockVariableDebtToken public mockDebtTokenCbBTC;
    MockVariableDebtToken public mockDebtTokenUSDC;
    MockInterestRateStrategy public mockInterestRateStrategy;

    // ============ Price Constants ============
    uint256 public constant BTC_PRICE = 100_000e8; // $100,000 per BTC
    uint256 public constant USDC_PRICE = 1e8; // $1 per USDC

    function setUp() public virtual override {
        super.setUp();

        user = makeAddr("user");
        liquidator = makeAddr("liquidator");
        premiumCollector = config.getPremiumCollector();

        vm.startPrank(admin);
        _deployMockInfrastructure();
        _deployLoanInfrastructure();
        _configureLoanRoles();
        vm.stopPrank();

        _fundTestAccounts();

        // Update snapshot after full setup
        _baseSnapshotId = vm.snapshot();
    }

    /// @notice Deploys all mock contracts for the lending pool
    function _deployMockInfrastructure() internal virtual {
        // Deploy price oracle
        mockOracle = new MockPriceOracle();
        mockOracle.setAssetPrice(address(mockCbBTC), BTC_PRICE);
        mockOracle.setAssetPrice(address(mockUSDC), USDC_PRICE);

        // Deploy addresses provider (with placeholder pool address, will update later)
        mockAddressesProvider = new MockAddressesProvider(
            address(0), // Will set lending pool later
            address(mockOracle),
            admin
        );

        // Deploy lending pool
        mockBitmorPool = new MockBitmorLendingPool(address(mockAddressesProvider));

        // Update addresses provider with lending pool
        mockAddressesProvider.setLendingPool(address(mockBitmorPool));

        //! TODO: This is wrong. We need to deploy mockBTCVault with shares `bvBTC` which act as a reserve in BitmorLendingPool instead of `cbBTC` acting as reserve in BitmorLendingPool.
        // Deploy aTokens and debt tokens for cbBTC
        mockATokenCbBTC = new MockAToken(
            "Bitmor aToken cbBTC",
            "aBTC",
            8, // Same decimals as cbBTC
            address(mockCbBTC),
            address(mockBitmorPool)
        );

        mockDebtTokenCbBTC = new MockVariableDebtToken(
            "Bitmor Variable Debt cbBTC", "variableDebtBTC", 8, address(mockCbBTC), address(mockBitmorPool)
        );

        // Deploy aTokens and debt tokens for USDC
        mockATokenUSDC = new MockAToken(
            "Bitmor aToken USDC",
            "aUSDC",
            6, // Same decimals as USDC
            address(mockUSDC),
            address(mockBitmorPool)
        );

        mockDebtTokenUSDC = new MockVariableDebtToken(
            "Bitmor Variable Debt USDC", "variableDebtUSDC", 6, address(mockUSDC), address(mockBitmorPool)
        );

        // Deploy interest rate strategy
        //! TODO: This is wrong. Interest rate strategy for `bvBTC` reserve and `USDC` reserve will be different as USDC reserve will consider the `availableLiquidity  = USDCVault.totalAssets()` as setup in `USDCReserveInterestRateStartegy` in `lending-pool`
        mockInterestRateStrategy = new MockInterestRateStrategy();

        // Initialize reserves in lending pool with interest rate strategy
        //! TODO: need to use `bvBTC` vault shares as reserves instead of this.
        mockBitmorPool.initReserveWithStrategy(
            address(mockCbBTC), address(mockATokenCbBTC), address(mockDebtTokenCbBTC), address(mockInterestRateStrategy)
        );

        //! TODO: need to use USDCReserveInterestRateStrategy logic instead.
        mockBitmorPool.initReserveWithStrategy(
            address(mockUSDC), address(mockATokenUSDC), address(mockDebtTokenUSDC), address(mockInterestRateStrategy)
        );

        // Deploy swap adapter with oracle
        mockSwapAdapter = new MockSwapAdapter(address(mockOracle));

        // Fund swap adapter with tokens for swaps
        mockCbBTC.mint(address(mockSwapAdapter), TC.SWAP_ADAPTER_CBBTC_BALANCE);
        mockUSDC.mint(address(mockSwapAdapter), TC.SWAP_ADAPTER_USDC_BALANCE);

        // Fund lending pool with tokens for borrows/withdraws
        mockCbBTC.mint(address(mockBitmorPool), TC.LENDING_POOL_CBBTC_BALANCE);
        mockUSDC.mint(address(mockBitmorPool), TC.LENDING_POOL_USDC_BALANCE);

        // Fund Aave V3 pool for flash loans
        mockUSDC.mint(address(mockAavePool), TC.LENDING_POOL_USDC_BALANCE);
    }

    /// @notice Deploys Loan contract with mock dependencies
    function _deployLoanInfrastructure() internal virtual {
        loanVaultImplementation = address(new LoanVault());

        // Deploy Loan with comprehensive mock infrastructure
        loan = new Loan(
            address(manager), // AccessManager
            address(mockAavePool), // Mock Aave V3 for flash loans
            address(mockAddressesProvider), // Our mock addresses provider
            address(mockBitmorPool), // Our mock Bitmor lending pool
            address(mockOracle), // Our mock price oracle
            address(mockCbBTC), // collateralAsset
            address(mockUSDC), // debtAsset
            address(mockCbBTC), // btc token
            address(mockSwapAdapter), // Our mock swap adapter
            address(0), // zQuoter (allowed to be zero)
            premiumCollector, // premiumCollector
            config.getPreClosureFee(), // preClosureFeeBps
            config.getGracePeriod(), // gracePeriod
            config.getLiquidationBuffer() // liquidationBuffer
        );

        loanVaultFactory = new LoanVaultFactory(loanVaultImplementation, address(loan));
        loan.setLoanVaultFactory(address(loanVaultFactory));

        // Register loan in addresses provider
        mockAddressesProvider.setBitmorLoan(address(loan));

        // Set storage values for min/max BTC amounts (slots 9 and 10)
        // s_maxBTCAmt = 10e8 (10 BTC)
        //! TODO: Instead of using vm.store update it with Loan.setMaxBTCAmount() and same for others.
        vm.store(address(loan), bytes32(uint256(9)), bytes32(uint256(10e8)));
        // s_minBTCAmt = 0.001e8 (0.001 BTC)
        vm.store(address(loan), bytes32(uint256(10)), bytes32(uint256(0.001e8)));
        // s_slippage_swap = 50 (0.5% slippage)
        vm.store(address(loan), bytes32(uint256(8)), bytes32(uint256(50)));
    }

    /// @notice Configures roles for Loan contract
    function _configureLoanRoles() internal virtual {
        _setLoanRoles(user);
        _setLoanTargetSelectors(address(loan));

        // Grant LPCM role to mock pool so it can call updateLoanDataFor* functions
        manager.grantRole(LPCM_ID(), address(mockBitmorPool), 0);
    }

    /// @notice Funds test accounts with tokens
    function _fundTestAccounts() internal virtual {
        _fundUSDC(user, TC.USER_USDC_BALANCE);
        _fundCbBTC(user, TC.USER_CBBTC_BALANCE);

        vm.prank(user);
        mockUSDC.approve(address(loan), type(uint256).max);

        vm.prank(user);
        mockCbBTC.approve(address(loan), type(uint256).max);

        // Fund liquidator
        _fundUSDC(liquidator, TC.USER_USDC_BALANCE);
        _fundCbBTC(liquidator, TC.USER_CBBTC_BALANCE);

        vm.prank(liquidator);
        mockUSDC.approve(address(mockBitmorPool), type(uint256).max);
    }

    // ============ Loan Creation Helpers ============

    /// @notice Creates a standard loan (1 BTC, 12 months)
    function _createStandardLoan() internal returns (address lsa) {
        lsa = _createLoan(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);
    }

    /// @notice Creates a loan with custom parameters
    function _createLoan(uint256 collateral, uint256 duration, uint256 premium) internal returns (address lsa) {
        (,, uint256 minDeposit) = loan.getLoanDetails(collateral, duration);
        vm.prank(user);
        lsa = loan.initializeLoan(minDeposit, premium, collateral, duration, "");
    }

    /// @notice Creates a loan and returns both LSA and loan data
    function _createLoanWithData(uint256 collateral, uint256 duration, uint256 premium)
        internal
        returns (address lsa, DataTypes.LoanData memory loanData)
    {
        lsa = _createLoan(collateral, duration, premium);
        loanData = loan.getLoanByLSA(lsa);
    }

    // ============ Balance Helpers ============

    /// @notice Gets user's USDC balance
    function _getUserUsdcBalance() internal view returns (uint256) {
        return mockUSDC.balanceOf(user);
    }

    /// @notice Gets user's cbBTC balance
    function _getUserCbBtcBalance() internal view returns (uint256) {
        return mockCbBTC.balanceOf(user);
    }

    /// @notice Gets user's debt balance from the lending pool
    function _getDebtBalance(address lsa) internal view returns (uint256) {
        return mockDebtTokenUSDC.balanceOf(lsa);
    }

    /// @notice Gets user's collateral balance from the lending pool
    function _getCollateralBalance(address lsa) internal view returns (uint256) {
        return mockATokenCbBTC.balanceOf(lsa);
    }

    // ============ Oracle Helpers ============

    /// @notice Drops the BTC price by a percentage
    /// @param dropPercent Percentage to drop (e.g., 50 = 50% drop)
    /// @return newPrice The new BTC price
    function _dropOraclePrice(uint256 dropPercent) internal returns (uint256 newPrice) {
        newPrice = mockOracle.dropPrice(address(mockCbBTC), dropPercent);
    }

    /// @notice Sets the BTC price directly
    /// @param price New price in 8 decimals
    function _setBtcPrice(uint256 price) internal {
        mockOracle.setAssetPrice(address(mockCbBTC), price);
    }

    // ============ Liquidation Helpers ============

    /// @notice Sets up a user for liquidation testing
    /// @param lsa The loan smart account address
    /// @param liquidationType 0=none, 1=full, 2=micro
    function _setLiquidationType(address lsa, uint256 liquidationType) internal {
        mockBitmorPool.setLiquidationType(lsa, liquidationType);
    }

    /// @notice Gets the current liquidation type for a user
    function _getLiquidationType(address lsa) internal view returns (uint256) {
        return mockBitmorPool.checkTypeOfLiquidation(lsa);
    }

    // ============ Time Helpers ============

    /// @notice Advances time by a number of days
    function _advanceDays(uint256 days_) internal {
        vm.warp(block.timestamp + days_ * 1 days);
    }

    /// @notice Advances time past the grace period to make loan overdue
    function _makeOverdue() internal {
        vm.warp(block.timestamp + config.getGracePeriod() + 1);
    }
}
