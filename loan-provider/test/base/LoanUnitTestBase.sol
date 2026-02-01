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
import {MockBTCVault} from "../mock/MockBTCVault.sol";
import {MockUSDCVault} from "../mock/MockUSDCVault.sol";
import {MockLendingRateOracle} from "../mock/MockLendingRateOracle.sol";
import {MockDefaultInterestRateStrategy} from "../mock/MockDefaultInterestRateStrategy.sol";
import {MockUSDCInterestRateStrategy} from "../mock/MockUSDCInterestRateStrategy.sol";

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

    // New vault mocks for proper collateral handling
    MockBTCVault public mockBTCVault;
    MockUSDCVault public mockUSDCVault;

    // New interest rate strategy mocks
    MockDefaultInterestRateStrategy public mockBTCInterestRateStrategy;
    MockUSDCInterestRateStrategy public mockUSDCInterestRateStrategy;
    MockLendingRateOracle public mockLendingRateOracle;

    // Renamed: aToken for bvBTC shares (was cbBTC)
    MockAToken public mockATokenBvBTC;

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
        // Deploy lending rate oracle first (needed by interest rate strategies)
        mockLendingRateOracle = new MockLendingRateOracle();

        // Deploy price oracle
        mockOracle = new MockPriceOracle(address(mockBTCVault), address(mockCbBTC));
        mockOracle.setAssetPrice(address(mockCbBTC), BTC_PRICE);
        mockOracle.setAssetPrice(address(mockUSDC), USDC_PRICE);

        // Deploy addresses provider (with placeholder pool address, will update later)
        mockAddressesProvider = new MockAddressesProvider(
            address(0), // Will set lending pool later
            address(mockOracle),
            admin
        );

        // Set lending rate oracle in addresses provider
        mockAddressesProvider.setLendingRateOracle(address(mockLendingRateOracle));

        // Deploy BTCVault that wraps cbBTC → bvBTC shares
        mockBTCVault = new MockBTCVault(
            address(mockCbBTC),
            "Bitmor BTC Vault",
            "bvBTC",
            8 // Same decimals as cbBTC
        );

        // Set bvBTC price (same as cbBTC for 1:1 share ratio in testing)
        mockOracle.setAssetPrice(address(mockBTCVault), BTC_PRICE);

        // Deploy USDCVault for USDC interest rate strategy liquidity source
        mockUSDCVault = new MockUSDCVault(
            address(mockUSDC),
            "Bitmor USDC Vault",
            "bvUSDC",
            6 // Same decimals as USDC
        );
        // Set initial liquidity for USDC vault
        mockUSDCVault.setMockTotalAssets(TC.LENDING_POOL_USDC_BALANCE);

        // Deploy lending pool
        mockBitmorPool = new MockBitmorLendingPool(address(mockAddressesProvider));

        // Update addresses provider with lending pool
        mockAddressesProvider.setLendingPool(address(mockBitmorPool));

        // Deploy interest rate strategies
        mockBTCInterestRateStrategy = new MockDefaultInterestRateStrategy(address(mockAddressesProvider));
        mockUSDCInterestRateStrategy =
            new MockUSDCInterestRateStrategy(address(mockAddressesProvider), address(mockUSDCVault));

        // Deploy aTokens for bvBTC (vault shares as collateral)
        mockATokenBvBTC = new MockAToken(
            "Bitmor aToken bvBTC",
            "abvBTC",
            8, // Same decimals as bvBTC
            address(mockBTCVault), // Underlying is bvBTC (vault shares)
            address(mockBitmorPool)
        );

        // Keep cbBTC aToken for backward compatibility during transition
        mockATokenCbBTC = new MockAToken("Bitmor aToken cbBTC", "aBTC", 8, address(mockCbBTC), address(mockBitmorPool));

        mockDebtTokenCbBTC = new MockVariableDebtToken(
            "Bitmor Variable Debt cbBTC", "variableDebtBTC", 8, address(mockCbBTC), address(mockBitmorPool)
        );

        // Deploy aTokens and debt tokens for USDC
        mockATokenUSDC = new MockAToken("Bitmor aToken USDC", "aUSDC", 6, address(mockUSDC), address(mockBitmorPool));

        mockDebtTokenUSDC = new MockVariableDebtToken(
            "Bitmor Variable Debt USDC", "variableDebtUSDC", 6, address(mockUSDC), address(mockBitmorPool)
        );

        // Initialize reserves in lending pool with proper interest rate strategies
        // Use bvBTC (vault shares) as collateral reserve
        mockBitmorPool.initReserveWithStrategy(
            address(mockBTCVault), // bvBTC as reserve
            address(mockATokenBvBTC),
            address(mockDebtTokenCbBTC), // Debt is still in cbBTC terms
            address(mockBTCInterestRateStrategy)
        );

        // USDC reserve uses USDC interest rate strategy
        mockBitmorPool.initReserveWithStrategy(
            address(mockUSDC),
            address(mockATokenUSDC),
            address(mockDebtTokenUSDC),
            address(mockUSDCInterestRateStrategy)
        );

        // Deploy swap adapter with oracle
        mockSwapAdapter = new MockSwapAdapter(address(mockOracle));

        // Fund swap adapter with tokens for swaps
        // Swap adapter needs cbBTC for USDC → cbBTC swaps
        mockCbBTC.mint(address(mockSwapAdapter), TC.SWAP_ADAPTER_CBBTC_BALANCE);
        mockUSDC.mint(address(mockSwapAdapter), TC.SWAP_ADAPTER_USDC_BALANCE);

        // Note: BTCVault is NOT pre-funded with cbBTC
        // cbBTC flows into the vault naturally through deposits during loan initialization
        // This maintains proper share accounting (virtual shares protection)

        // Fund lending pool with tokens for borrows/withdraws
        mockCbBTC.mint(address(mockBitmorPool), TC.LENDING_POOL_CBBTC_BALANCE);
        mockUSDC.mint(address(mockBitmorPool), TC.LENDING_POOL_USDC_BALANCE);

        // Fund Aave V3 pool for flash loans
        mockUSDC.mint(address(mockAavePool), TC.LENDING_POOL_USDC_BALANCE);
    }

    /// @notice Deploys Loan contract with mock dependencies
    function _deployLoanInfrastructure() internal virtual {
        loanVaultImplementation = address(new LoanVault());

        // Deploy Loan with bvBTC (vault shares) as collateral
        loan = new Loan(
            address(manager), // AccessManager
            address(mockAavePool), // Mock Aave V3 for flash loans
            address(mockAddressesProvider), // Our mock addresses provider
            address(mockBitmorPool), // Our mock Bitmor lending pool
            address(mockOracle), // Our mock price oracle
            address(mockBTCVault), // collateralAsset = bvBTC (vault shares)
            address(mockUSDC), // debtAsset
            address(mockCbBTC), // btc token (underlying)
            address(mockSwapAdapter), // Our mock swap adapter
            address(0), // zQuoter (allowed to be zero)
            premiumCollector, // premiumCollector
            config.getPreClosureFee(), // preClosureFeeBps
            config.getGracePeriod() // gracePeriod
        );

        loanVaultFactory = new LoanVaultFactory(loanVaultImplementation, address(loan));
        loan.setLoanVaultFactory(address(loanVaultFactory));

        loan.setMaxBTCAmount(TC.MAX_COLLATERAL);

        // Register loan in addresses provider
        mockAddressesProvider.setBitmorLoan(address(loan));

        // Configure loan parameters using proper setters via AccessManager
        // Note: Done in _configureLoanRoles() after roles are configured
    }

    /// @notice Configures roles for Loan contract
    function _configureLoanRoles() internal virtual {
        _setLoanRoles(user);
        _setLoanTargetSelectors(address(loan));

        // Grant LPCM role to mock pool so it can call updateLoanDataFor* functions
        manager.grantRole(LPCM_ID(), address(mockBitmorPool), 0);

        // Configure loan parameters using proper setters (replaces vm.store)
        _configureLoanParameters(address(loan), TC.MAX_COLLATERAL, TC.MIN_COLLATERAL, TC.SLIPPAGE_SWAP, TC.MIN_DEPOSIT);
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
        return mockATokenBvBTC.balanceOf(lsa);
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
