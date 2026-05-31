// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {UnitTestBase} from "./UnitTestBase.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";
import {ProxyTestHelper} from "../helpers/ProxyTestHelper.sol";

// Protocol contracts
import {Loan} from "@bitmor/protocol/Loan.sol";
import {ILoan} from "@bitmor/interfaces/ILoan.sol";
import {LoanVault} from "@bitmor/protocol/LoanVault.sol";
import {LoanVaultFactory} from "@bitmor/protocol/LoanVaultFactory.sol";
import {BitmorAddressesProvider} from "@bitmor/protocol/BitmorAddressesProvider.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

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
/// @author Bitmor Protocol
/// @notice Tier 2 test base providing a fully deployed Loan contract with mock lending pool infrastructure
/// @dev Inherits UnitTestBase (Tier 1) and adds 20+ mock contracts for complete loan lifecycle testing
abstract contract LoanUnitTestBase is UnitTestBase, ProxyTestHelper {
    // ============ Loan Infrastructure ============

    /// @notice The real Loan contract under test
    Loan public loan;

    /// @notice Factory for deploying LoanVault proxies
    LoanVaultFactory public loanVaultFactory;

    /// @notice LoanVault implementation address used by the factory
    address public loanVaultImplementation;

    /// @notice UpgradeableBeacon address for LoanVault proxies
    address public beacon;

    // ============ Test Actors ============

    /// @notice Primary test user (borrower) for loan operations
    address public user;

    /// @notice Test liquidator for liquidation scenarios
    address public liquidator;

    // ============ Protocol Addresses ============

    /// @notice Address that receives loan premiums
    address public premiumCollector;

    // ============ Mock Infrastructure ============

    /// @notice Mock Bitmor lending pool with controllable liquidation and health factor state
    MockBitmorLendingPool public mockBitmorPool;

    /// @notice Mock price oracle with configurable asset prices and price drop helper
    MockPriceOracle public mockOracle;

    /// @notice Mock addresses provider linking pool, oracle, and loan addresses
    MockAddressesProvider public mockAddressesProvider;

    /// @notice Mock swap adapter using oracle-based pricing for USDC/cbBTC swaps
    MockSwapAdapter public mockSwapAdapter;

    /// @dev Mock aToken and debt token for cbBTC reserve (backward compatibility)
    MockAToken public mockATokenCbBTC;

    /// @notice Mock aToken for USDC reserve
    MockAToken public mockATokenUSDC;

    /// @dev Mock variable debt token for cbBTC
    MockVariableDebtToken public mockDebtTokenCbBTC;

    /// @notice Mock variable debt token for USDC (tracks user debt)
    MockVariableDebtToken public mockDebtTokenUSDC;

    /// @dev Legacy mock interest rate strategy
    MockInterestRateStrategy public mockInterestRateStrategy;

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

    /// @notice Mock aToken for bvBTC vault shares (the actual collateral in the lending pool)
    MockAToken public mockATokenBvBTC;

    /// @notice Real BitmorAddressesProvider deployed in tests
    BitmorAddressesProvider public bitmorAddressesProvider;

    /// @notice Test autoRepayer address (used in RepayLogic authorization)
    address public autoRepayer;

    // ============ Price Constants ============

    /// @notice Default BTC price for tests: $100,000 (8 decimals)
    uint256 public constant BTC_PRICE = 100_000e8;

    /// @notice Default USDC price for tests: $1 (8 decimals)
    uint256 public constant USDC_PRICE = 1e8;

    function setUp() public virtual override {
        super.setUp();

        user = makeAddr("user");
        liquidator = makeAddr("liquidator");
        autoRepayer = makeAddr("autoRepayer");
        premiumCollector = config.getPremiumCollector();

        vm.startPrank(admin);
        _deployMockInfrastructure();
        _deployLoanInfrastructure();
        _configureLoanRoles();
        vm.stopPrank();

        _fundTestAccounts();

        // Update snapshot after full setup
        _baseSnapshotId = vm.snapshotState();
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

    /// @notice Deploys Loan contract with mock dependencies via UUPS proxies
    function _deployLoanInfrastructure() internal virtual {
        // Deploy BitmorAddressesProvider FIRST via UUPS proxy (Loan.initialize needs its address)
        bitmorAddressesProvider = _deployAddressesProviderProxy(
            address(manager), address(mockSwapAdapter), premiumCollector, premiumCollector
        );

        // Pre-compute config-derived params to avoid stack-too-deep under --ir-minimum (coverage)
        uint32 gracePeriod = uint32(config.getGracePeriod());
        uint16 preClosureFeeBps = uint16(config.getPreClosureFee());
        uint16 maxDuration = uint16(config.getMaxDuration());

        // Deploy Loan via UUPS proxy with InitParams struct
        loan = _deployLoanProxy(
            DataTypes.InitParams({
                manager: address(manager),
                aaveV3Pool: address(mockAavePool),
                aaveAddressesProvider: address(mockAddressesProvider),
                bitmorPool: address(mockBitmorPool),
                oracle: address(mockOracle),
                collateralAsset: address(mockBTCVault),
                debtAsset: address(mockUSDC),
                btc: address(mockCbBTC),
                bitmorAddressesProvider: address(bitmorAddressesProvider),
                maxBTCAmt: uint64(TC.MAX_COLLATERAL),
                minBTCAmt: uint64(TC.MIN_COLLATERAL),
                gracePeriod: gracePeriod,
                preClosureFeeBps: preClosureFeeBps,
                liquidationFee: 0,
                slippageSharesToAsset: uint16(TC.SLIPPAGE_SHARES_TO_ASSET),
                slippageSwap: uint16(TC.SLIPPAGE_SWAP),
                minDeposit: uint16(TC.MIN_DEPOSIT),
                maxDuration: maxDuration
            })
        );

        // Deploy beacon proxy (simplified -- no BeaconController for unit tests)
        address factoryAddr;
        (loanVaultImplementation, beacon, factoryAddr) = _deploySimpleBeaconProxy(address(loan));
        loanVaultFactory = LoanVaultFactory(factoryAddr);

        // BAP post-init setters: register factory and autoRepayer
        bitmorAddressesProvider.setVaultFactory(address(loanVaultFactory));
        bitmorAddressesProvider.setAutoRepayer(autoRepayer);

        // Register loan in lending pool addresses provider
        mockAddressesProvider.setBitmorLoan(address(loan));
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

    /// @notice Creates a standard loan with `TC.STANDARD_COLLATERAL` (1 BTC) and `TC.STANDARD_DURATION` (12 months)
    /// @return lsa The deployed LoanVault (Loan Smart Account) address
    function _createStandardLoan() internal returns (address lsa) {
        lsa = _createLoan(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);
    }

    /// @notice Creates a loan with custom parameters using the minimum required deposit
    /// @param collateral Target cbBTC amount (8 decimals)
    /// @param duration Loan duration in months
    /// @param premium Premium amount in USDC (6 decimals)
    /// @return lsa The deployed LoanVault (Loan Smart Account) address
    function _createLoan(uint256 collateral, uint256 duration, uint256 premium) internal returns (address lsa) {
        (,, uint256 minDeposit) = loan.getLoanDetails(collateral, duration);
        vm.prank(user);
        lsa = loan.initializeLoan(minDeposit, premium, collateral, duration, "");
    }

    /// @notice Creates a loan and returns both the LSA address and the stored `LoanData` struct
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
    /// @return The USDC balance (6 decimals)
    function _getUserUsdcBalance() internal view returns (uint256) {
        return mockUSDC.balanceOf(user);
    }

    /// @notice Returns the `user` address cbBTC balance
    /// @return The cbBTC balance (8 decimals)
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

    /// @notice Warps `block.timestamp` forward by `days_` days
    /// @param days_ Number of days to advance
    function _advanceDays(uint256 days_) internal {
        vm.warp(block.timestamp + days_ * 1 days);
    }

    /// @notice Advances time past the grace period to make loan overdue
    function _makeOverdue() internal {
        vm.warp(block.timestamp + config.getGracePeriod() + 1);
    }
}
