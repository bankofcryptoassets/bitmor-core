// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {FuzzTestBase} from "./FuzzTestBase.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";
import {TestConstants as TC} from "../../helpers/TestConstants.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {ProxyTestHelper} from "../../helpers/ProxyTestHelper.sol";

// Protocol contracts
import {Loan} from "@bitmor/protocol/Loan.sol";
import {LoanVault} from "@bitmor/protocol/LoanVault.sol";
import {LoanVaultFactory} from "@bitmor/protocol/LoanVaultFactory.sol";
import {BitmorAddressesProvider} from "@bitmor/protocol/BitmorAddressesProvider.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";

// Mock contracts
import {MockBitmorLendingPool} from "../../mock/MockBitmorLendingPool.sol";
import {MockPriceOracle} from "../../mock/MockPriceOracle.sol";
import {MockAddressesProvider} from "../../mock/MockAddressesProvider.sol";
import {MockAToken} from "../../mock/MockAToken.sol";
import {MockVariableDebtToken} from "../../mock/MockVariableDebtToken.sol";
import {MockSwapAdapter} from "../../mock/MockSwapAdapter.sol";
import {MockBTCVault} from "../../mock/MockBTCVault.sol";
import {MockUSDCVault} from "../../mock/MockUSDCVault.sol";
import {MockLendingRateOracle} from "../../mock/MockLendingRateOracle.sol";
import {MockDefaultInterestRateStrategy} from "../../mock/MockDefaultInterestRateStrategy.sol";
import {MockUSDCInterestRateStrategy} from "../../mock/MockUSDCInterestRateStrategy.sol";

/// @title LoanFuzzTestBase
/// @author Bitmor Protocol
/// @notice Shared base for Loan fuzz and invariant tests using real Loan + mock infrastructure
/// @dev Deploys real Loan, LoanVaultFactory, and full mock lending pool infrastructure.
///      Inherits FuzzTestBase for bound helpers. Overrides _boundCollateral to use
///      Loan contract parameters. Does NOT call super.setUp() to avoid double-deploying
///      AccessManager and mocks (matching BTCVaultFuzzTestBase / USDCVaultFuzzTestBase pattern).
abstract contract LoanFuzzTestBase is FuzzTestBase, ProxyTestHelper {
    // ============ Loan Infrastructure ============

    /// @notice The real Loan contract under test
    Loan public loan;

    /// @notice Factory for deploying LoanVault proxies
    LoanVaultFactory public loanVaultFactory;

    /// @notice LoanVault implementation address used by the factory
    address public loanVaultImplementation;

    /// @notice UpgradeableBeacon address for LoanVault proxies
    address public beacon;

    /// @notice BitmorAddressesProvider registry for swapper, premiumCollector, etc.
    BitmorAddressesProvider public bitmorAddressesProvider;

    // ============ Test Actors ============

    /// @notice Primary test user (borrower) for loan operations
    address public user;

    /// @notice Test liquidator for liquidation scenarios
    address public liquidator;

    /// @notice Address that receives loan premiums
    address public premiumCollector;

    /// @notice Address of the auto repayer
    address public autoRepayer;

    // ============ Mock Infrastructure ============

    /// @notice Mock Bitmor lending pool with controllable liquidation and health factor state
    MockBitmorLendingPool public mockBitmorPool;

    /// @notice Mock price oracle with configurable asset prices and price drop helper
    MockPriceOracle public mockOracle;

    /// @notice Mock addresses provider linking pool, oracle, and loan addresses
    MockAddressesProvider public mockAddressesProvider;

    /// @notice Mock swap adapter using oracle-based pricing for USDC/cbBTC swaps
    MockSwapAdapter public mockSwapAdapter;

    /// @dev Mock aToken for cbBTC reserve (backward compatibility)
    MockAToken public mockATokenCbBTC;

    /// @notice Mock aToken for USDC reserve
    MockAToken public mockATokenUSDC;

    /// @notice Mock aToken for bvBTC vault shares (the actual collateral in the lending pool)
    MockAToken public mockATokenBvBTC;

    /// @dev Mock variable debt token for cbBTC
    MockVariableDebtToken public mockDebtTokenCbBTC;

    /// @notice Mock variable debt token for USDC (tracks user debt)
    MockVariableDebtToken public mockDebtTokenUSDC;

    /// @notice Mock BTC vault wrapping cbBTC into bvBTC shares
    MockBTCVault public mockBTCVault;

    /// @notice Mock USDC vault for interest rate strategy liquidity
    MockUSDCVault public mockUSDCVault;

    /// @notice Mock BTC interest rate strategy for the lending pool
    MockDefaultInterestRateStrategy public mockBTCInterestRateStrategy;

    /// @notice Mock USDC interest rate strategy backed by `mockUSDCVault`
    MockUSDCInterestRateStrategy public mockUSDCInterestRateStrategy;

    /// @notice Mock lending rate oracle for interest rate strategies
    MockLendingRateOracle public mockLendingRateOracle;

    // ============ Price Constants ============

    /// @notice Default BTC price for tests: $100,000 (8 decimals)
    uint256 public constant BTC_PRICE = 100_000e8;

    /// @notice Default USDC price for tests: $1 (8 decimals)
    uint256 public constant USDC_PRICE = 1e8;

    // ============ Setup ============

    /// @notice Deploys full loan infrastructure with mock lending pool and configures roles
    /// @dev Does NOT call super.setUp() to avoid double-deploying AccessManager and mocks
    function setUp() public virtual override {
        // Create test actors BEFORE initializing AccessManager
        user = makeAddr("user");
        liquidator = makeAddr("liquidator");
        autoRepayer = makeAddr("autoRepayer");

        // Initialize AccessManager with test contract as admin (matching vault fuzz base pattern)
        _initializeAccessManager(address(this));

        // Deploy HelperConfig for protocol parameters (premiumCollector, fees, grace period)
        config = new HelperConfig();
        premiumCollector = config.getPremiumCollector();

        // Deploy base mock externals (mockAavePool, mockCbBTC, mockUSDC) from UnitTestBase
        _deployMockExternals();

        // Deploy loan-specific mock infrastructure (oracle, lending pool, tokens, etc.)
        _deployLoanMockInfrastructure();

        // Deploy real Loan contract + LoanVaultFactory
        _deployLoanInfrastructure();

        // Configure roles and loan parameters via AccessManager
        _configureLoanRoles();
    }

    // ============ FuzzTestBase Overrides ============

    /// @notice Bounds collateral using Loan contract's configured min/max range
    /// @dev Fulfills the virtual override hook documented in FuzzTestBase._boundCollateral
    /// @param raw The raw fuzzed input
    /// @return The bounded collateral amount
    function _boundCollateral(uint256 raw) internal view override returns (uint256) {
        return bound(raw, loan.getMinBTCAmount(), loan.getMaxBTCAmount());
    }

    // ============ Loan-Specific Bound Helpers ============

    /// @notice Bounds deposit between contract-computed minimum and 90% of collateral value
    /// @param collateral Target cbBTC amount (8 decimals)
    /// @param duration Loan duration in months
    /// @param raw The raw fuzzed input
    /// @return deposit The bounded deposit amount in USDC (6 decimals)
    /// @return minDeposit The minimum deposit from loan contract
    function _boundValidDeposit(uint256 collateral, uint256 duration, uint256 raw)
        internal
        view
        returns (uint256 deposit, uint256 minDeposit)
    {
        (,, minDeposit) = loan.getLoanDetails(collateral, duration);
        uint256 btcPrice = mockOracle.getAssetPrice(address(mockBTCVault));
        uint256 collateralValueUsdc = (collateral * btcPrice) / 1e8;
        uint256 maxDeposit = (collateralValueUsdc * 90) / 100;
        maxDeposit = (maxDeposit * 1e6) / 1e8;

        if (minDeposit >= maxDeposit) {
            deposit = minDeposit;
        } else {
            deposit = bound(raw, minDeposit, maxDeposit);
        }
    }

    // ============ Internal Setup Helpers ============

    /// @notice Deploys all mock contracts for the lending pool infrastructure
    /// @dev Mirrors LoanUnitTestBase._deployMockInfrastructure() but uses address(this) as admin
    function _deployLoanMockInfrastructure() internal {
        // Deploy lending rate oracle first (needed by interest rate strategies)
        mockLendingRateOracle = new MockLendingRateOracle();

        // Deploy price oracle (mockBTCVault not yet deployed, passes address(0) — prices set later)
        mockOracle = new MockPriceOracle(address(mockBTCVault), address(mockCbBTC));
        mockOracle.setAssetPrice(address(mockCbBTC), BTC_PRICE);
        mockOracle.setAssetPrice(address(mockUSDC), USDC_PRICE);

        // Deploy addresses provider (address(this) is admin in fuzz base pattern)
        mockAddressesProvider = new MockAddressesProvider(
            address(0), // Will set lending pool later
            address(mockOracle),
            address(this)
        );

        // Set lending rate oracle in addresses provider
        mockAddressesProvider.setLendingRateOracle(address(mockLendingRateOracle));

        // Deploy BTCVault that wraps cbBTC → bvBTC shares
        mockBTCVault = new MockBTCVault(address(mockCbBTC), "Bitmor BTC Vault", "bvBTC", 8);

        // Set bvBTC price (same as cbBTC for 1:1 share ratio in testing)
        mockOracle.setAssetPrice(address(mockBTCVault), BTC_PRICE);

        // Deploy USDCVault for USDC interest rate strategy liquidity source
        mockUSDCVault = new MockUSDCVault(address(mockUSDC), "Bitmor USDC Vault", "bvUSDC", 6);
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
            8,
            address(mockBTCVault), // Underlying is bvBTC (vault shares)
            address(mockBitmorPool)
        );

        // Keep cbBTC aToken for backward compatibility
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
        mockBitmorPool.initReserveWithStrategy(
            address(mockBTCVault),
            address(mockATokenBvBTC),
            address(mockDebtTokenCbBTC),
            address(mockBTCInterestRateStrategy)
        );

        mockBitmorPool.initReserveWithStrategy(
            address(mockUSDC),
            address(mockATokenUSDC),
            address(mockDebtTokenUSDC),
            address(mockUSDCInterestRateStrategy)
        );

        // Deploy swap adapter with oracle
        mockSwapAdapter = new MockSwapAdapter(address(mockOracle));

        // Fund protocol contracts with liquidity
        mockCbBTC.mint(address(mockSwapAdapter), TC.SWAP_ADAPTER_CBBTC_BALANCE);
        mockUSDC.mint(address(mockSwapAdapter), TC.SWAP_ADAPTER_USDC_BALANCE);
        mockCbBTC.mint(address(mockBitmorPool), TC.LENDING_POOL_CBBTC_BALANCE);
        mockUSDC.mint(address(mockBitmorPool), TC.LENDING_POOL_USDC_BALANCE);
        mockUSDC.mint(address(mockAavePool), TC.LENDING_POOL_USDC_BALANCE);
    }

    /// @notice Deploys the real Loan contract, LoanVaultFactory, and BitmorAddressesProvider via UUPS proxies
    function _deployLoanInfrastructure() internal {
        // Deploy Loan via UUPS proxy
        loan = _deployLoanProxy(
            address(manager),
            address(mockAavePool),
            address(mockAddressesProvider),
            address(mockBitmorPool),
            address(mockOracle),
            address(mockBTCVault),
            address(mockUSDC),
            address(mockCbBTC),
            config.getPreClosureFee(),
            config.getGracePeriod()
        );

        // Deploy beacon chain (simplified -- no BeaconController for fuzz tests)
        address factoryAddr;
        (loanVaultImplementation, beacon, factoryAddr) = _deploySimpleBeaconChain(address(loan));
        loanVaultFactory = LoanVaultFactory(factoryAddr);

        // Deploy BitmorAddressesProvider via UUPS proxy
        bitmorAddressesProvider = _deployAddressesProviderProxy(address(manager), address(loan));
        bitmorAddressesProvider.setVaultFactory(address(loanVaultFactory));
        bitmorAddressesProvider.setSwapper(address(mockSwapAdapter));
        bitmorAddressesProvider.setPremiumCollector(premiumCollector);
        bitmorAddressesProvider.setAutoRepayer(autoRepayer);
        loan.setBitmorAddressesProvider(address(bitmorAddressesProvider));

        loan.setMaxBTCAmount(TC.MAX_COLLATERAL);

        // Register loan in addresses provider
        mockAddressesProvider.setBitmorLoan(address(loan));
    }

    /// @notice Configures roles and loan parameters via AccessManager
    function _configureLoanRoles() internal {
        _setLoanRoles(user);
        _setLoanTargetSelectors(address(loan));

        // Grant LPCM role to mock pool so it can call updateLoanDataFor* functions
        manager.grantRole(LPCM_ID(), address(mockBitmorPool), 0);

        // Configure loan parameters using proper setters (delayed operations)
        _configureLoanParameters(address(loan), TC.MAX_COLLATERAL, TC.MIN_COLLATERAL, TC.SLIPPAGE_SWAP, TC.MIN_DEPOSIT);
    }

    // ============ Loan Creation Helpers ============

    /// @notice Creates a standard loan with TC.STANDARD_COLLATERAL (1 BTC) and TC.STANDARD_DURATION (12 months)
    /// @dev Caller must ensure `user` has sufficient USDC balance and approval
    /// @return lsa The deployed LoanVault (Loan Smart Account) address
    function _createStandardLoan() internal returns (address lsa) {
        lsa = _createLoan(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);
    }

    /// @notice Creates a loan with custom parameters using the minimum required deposit
    /// @dev Caller must ensure `user` has sufficient USDC balance and approval
    /// @param collateral Target cbBTC amount (8 decimals)
    /// @param duration Loan duration in months
    /// @param premium Premium amount in USDC (6 decimals)
    /// @return lsa The deployed LoanVault (Loan Smart Account) address
    function _createLoan(uint256 collateral, uint256 duration, uint256 premium) internal returns (address lsa) {
        (,, uint256 minDeposit) = loan.getLoanDetails(collateral, duration);
        vm.prank(user);
        lsa = loan.initializeLoan(minDeposit, premium, collateral, duration, "");
    }

    /// @notice Creates a loan and returns both the LSA address and the stored LoanData struct
    /// @dev Caller must ensure `user` has sufficient USDC balance and approval
    /// @param collateral Target cbBTC amount (8 decimals)
    /// @param duration Loan duration in months
    /// @param premium Premium amount in USDC (6 decimals)
    /// @return lsa The deployed LoanVault address
    /// @return loanData The stored loan data struct
    function _createLoanWithData(uint256 collateral, uint256 duration, uint256 premium)
        internal
        returns (address lsa, DataTypes.LoanData memory loanData)
    {
        lsa = _createLoan(collateral, duration, premium);
        loanData = loan.getLoanByLSA(lsa);
    }

    // ============ Balance Helpers ============

    /// @notice Returns the `user` address USDC balance
    function _getUserUsdcBalance() internal view returns (uint256) {
        return mockUSDC.balanceOf(user);
    }

    /// @notice Returns the `user` address cbBTC balance
    function _getUserCbBtcBalance() internal view returns (uint256) {
        return mockCbBTC.balanceOf(user);
    }

    /// @notice Returns the USDC variable debt token balance for a given LSA
    /// @param lsa The LoanVault address to query
    /// @return The outstanding debt balance (6 decimals)
    function _getDebtBalance(address lsa) internal view returns (uint256) {
        return mockDebtTokenUSDC.balanceOf(lsa);
    }

    /// @notice Returns the bvBTC aToken (collateral) balance for a given LSA
    /// @param lsa The LoanVault address to query
    /// @return The collateral balance in bvBTC shares (8 decimals)
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

    /// @notice Sets the liquidation type for a given LSA on the mock lending pool
    /// @param lsa The LoanVault address
    /// @param liquidationType 0 = none, 1 = full, 2 = micro
    function _setLiquidationType(address lsa, uint256 liquidationType) internal {
        mockBitmorPool.setLiquidationType(lsa, liquidationType);
    }

    /// @notice Returns the current liquidation type for a given LSA
    /// @param lsa The LoanVault address to query
    /// @return 0 = none, 1 = full, 2 = micro
    function _getLiquidationType(address lsa) internal view returns (uint256) {
        return mockBitmorPool.checkTypeOfLiquidation(lsa);
    }

    // ============ Time Helpers ============

    /// @notice Warps block.timestamp forward by `days_` days
    /// @param days_ Number of days to advance
    function _advanceDays(uint256 days_) internal {
        vm.warp(block.timestamp + days_ * 1 days);
    }

    /// @notice Advances time past the grace period to make loan overdue
    function _makeOverdue() internal {
        vm.warp(block.timestamp + config.getGracePeriod() + 1);
    }

    // ============ AccessManager Helpers ============

    /// @notice Schedule and execute a delayed operation targeting the Loan contract
    /// @param caller The address performing the operation
    /// @param roleId The role ID of the caller
    /// @param data The encoded function call data
    function _scheduleAndExecuteLocal(address caller, uint64 roleId, bytes memory data) internal {
        (, uint32 delay,,) = manager.getAccess(roleId, caller);
        uint48 when = uint48(block.timestamp + delay);

        vm.startPrank(caller);
        if (delay > 0) {
            manager.schedule(address(loan), data, when);
            vm.warp(when);
        }
        manager.execute(address(loan), data);
        vm.stopPrank();
    }
}
