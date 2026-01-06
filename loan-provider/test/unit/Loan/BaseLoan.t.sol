// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {Utilities} from "../Utilities.t.sol";
import {Loan} from "@bitmor/protocol/Loan.sol";
import {LoanVault} from "@bitmor/protocol/LoanVault.sol";
import {LoanVaultFactory} from "@bitmor/protocol/LoanVaultFactory.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@bitmor/dependencies/openzeppelin/IERC20.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {ILendingPool} from "@bitmor/interfaces/ILendingPool.sol";
import {ILendingPoolAddressesProvider} from "@bitmor/interfaces/ILendingPoolAddressesProvider.sol";
import {IPriceOracleGetter} from "@bitmor/interfaces/IPriceOracleGetter.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";

/// @title BaseLoanTest
/// @notice Single base contract for all Bitmor Protocol test suites
/// @dev Provides shared state, constants, and core setUp functionality
/// @dev Inherits from Utilities which inherits from Test
/// @dev All test files should inherit from this contract
abstract contract BaseLoanTest is Utilities {
    using FixedPointMathLib for uint256;

    // ============ Core Protocol Contracts ============

    HelperConfig internal config;
    Loan internal loan;

    // ============ Test Actors ============

    address internal owner;
    address internal user;
    address internal liquidator;

    // ============ Protocol Addresses ============

    address internal debtAsset;
    address internal aavePool;
    address internal collateralAsset;
    address internal s_bitmorPool;
    address internal s_addressesProvider;

    // ============ Protocol Parameters ============

    uint256 internal s_gracePeriod;

    // ============ Constants ============

    /// @dev Premium amount is arbitrary as it's calculated offchain
    /// @dev Premium amount is required in debtAsset (bUSDC), 6 decimals. 1000e6 = 1000 bUSDC
    uint256 internal constant PREMIUM_AMOUNT = 1000e6;

    /// @dev Insurance ID > 0 indicates user opted in for insurance
    uint256 internal constant INSURANCE_ID = 1;

    /// @dev Arbitrary loan data identifier
    bytes internal constant DATA = "0xLOAN";

    /// @dev Amount of debt asset to mint to user for testing (1M USDC)
    uint256 internal constant DEBT_ASSET_TO_MINT_TO_USER = 1_000_000 * 1e6;

    /// @dev Standard loan repayment interval (30 days)
    uint256 internal constant LOAN_REPAYMENT_INTERVAL = 30 days;

    /// @dev Standard collateral amount for tests (1 BTC with 8 decimals)
    uint256 internal constant STANDARD_COLLATERAL_AMOUNT = 1e8;

    /// @dev Standard loan duration for tests (12 months)
    uint256 internal constant STANDARD_DURATION = 12;

    /// @dev RAY unit for interest rate calculations (1e27)
    uint256 internal constant RAY = 1e27;

    /// @dev Basis points denominator (10,000 = 100%)
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    /// @dev Precision for fixed-point math calculations
    uint256 internal constant PRECISION = 1e18;

    /// @dev Standard test amounts for various scenarios
    uint256 internal constant OVERPAY_AMOUNT = 500e6;
    uint256 internal constant POOL_DEPOSIT_AMOUNT = 100_000e6;
    uint256 internal constant SMALL_BORROW_AMOUNT = 1_000e6;
    uint256 internal constant BTC_SEED_AMOUNT = 0.1e8;

    /// @dev Price drop percentages for liquidation testing
    uint256 internal constant PRICE_DROP_50_PERCENT = 50;
    uint256 internal constant PRICE_DROP_FOR_LIQUIDATION = 20;

    /// @dev Time constants
    uint256 internal constant ONE_DAY = 1 days;

    /// @dev Liquidation and insurance constants
    uint256 internal constant INSURANCE_BONUS_BPS = 300; // 3%
    uint256 internal constant LIQUIDATION_TYPE_NONE = 0;
    uint256 internal constant LIQUIDATION_TYPE_FULL = 1;
    uint256 internal constant LIQUIDATION_TYPE_MICRO = 2;

    /// @dev Interest rate constants
    uint256 internal constant MAX_APR_BPS = 1200; // 12%

    /// @dev Tolerance and threshold constants
    uint256 internal constant PAYMENT_TOLERANCE = 10;
    uint256 internal constant DEBT_DUST_THRESHOLD = 100;

    // ============ Debug Flag ============

    /// @dev Set to true to enable debug logging (should be false in final tests)
    bool internal constant DEBUG = false;

    // ============ Setup ============

    /// @notice Core test setup - deploys/attaches contracts, creates actors, sets up roles
    /// @dev Uses vm.startPrank instead of vm.startBroadcast for test environment
    function setUp() public virtual {
        config = new HelperConfig();

        // Create test actors with labeled addresses
        owner = makeAddr("owner");
        user = makeAddr("user");
        liquidator = makeAddr("liquidator");

        // Deploy contracts as owner
        vm.startPrank(owner);

        (
            address bitmorPool,
            address aaveV3Pool,
            address aaveAddressesProvider,
            address oracle,
            address collateralAssetAddr,
            address debtAssetAddr,
            address swapAdapterWrapper,
            address zQuoter,
            address premiumCollector,
            uint256 preClosureFeeBps,
            uint256 gracePeriod,
            uint256 liquidationBuffer
        ) = config.networkConfig();

        // Store addresses
        debtAsset = debtAssetAddr;
        aavePool = aaveV3Pool;
        collateralAsset = collateralAssetAddr;
        s_bitmorPool = bitmorPool;
        s_gracePeriod = gracePeriod;
        s_addressesProvider = aaveAddressesProvider;

        // Deploy Loan contract
        loan = new Loan(
            aaveV3Pool,
            aaveAddressesProvider,
            bitmorPool,
            oracle,
            collateralAsset,
            debtAsset,
            swapAdapterWrapper,
            zQuoter,
            premiumCollector,
            preClosureFeeBps,
            gracePeriod,
            liquidationBuffer
        );

        // Deploy LoanVault infrastructure
        address loanVaultImplementation = address(new LoanVault());
        address loanVaultFactory = address(new LoanVaultFactory(loanVaultImplementation, address(loan)));
        loan.setLoanVaultFactory(loanVaultFactory);

        vm.stopPrank();
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

    /// @dev Helper wrapper for consistent error expectations with specific selector
    function _expectRevertSelector(bytes4 selector) internal {
        vm.expectRevert(selector);
    }

    /// @dev Helper wrapper for consistent error expectations with specific error message
    function _expectRevertMessage(string memory message) internal {
        vm.expectRevert(bytes(message));
    }

    /// @dev Helper wrapper for generic revert expectation (use only when specific error unknown)
    function _expectGenericRevert() internal {
        vm.expectRevert();
    }

    // ============ Internal Setup Helpers ============

    /// @dev Mint debt asset to user and approve loan contract
    function _mintDebtAssetToUser() internal {
        vm.startPrank(user);
        (bool success,) = debtAsset.call(abi.encodeWithSignature("mint(uint256)", DEBT_ASSET_TO_MINT_TO_USER));
        assertTrue(success, "MINT_ERROR");
        IERC20(debtAsset).approve(address(loan), DEBT_ASSET_TO_MINT_TO_USER);
        vm.stopPrank();
    }

    /// @dev Set up a standard loan for user (1 BTC, 12 months)
    function _setUpLoanForUser() internal {
        _mintDebtAssetToUser();

        (,, uint256 minDepositRequired) = loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);

        vm.prank(user);
        loan.initializeLoan(minDepositRequired, PREMIUM_AMOUNT, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, DATA);
    }

    // ============ Consolidated Helper Wrappers ============
    // The following helpers wrap Utilities methods with inherited state variables
    // Moved here from individual test files to eliminate duplication (DRY principle)

    /// @dev Warp past grace period using inherited s_gracePeriod
    function _warpPastGracePeriod() internal {
        _utilWarpPastGracePeriod(s_gracePeriod);
    }

    /// @dev Update AddressesProvider to point to test Loan contract
    function _updateAddressesProviderBitmorLoan() internal {
        _utilUpdateAddressesProviderBitmorLoan(s_bitmorPool, address(loan));
    }

    /// @dev Fund the liquidator with debt asset
    function _fundLiquidator() internal {
        _utilFundLiquidator(liquidator, debtAsset, s_bitmorPool, DEBT_ASSET_TO_MINT_TO_USER);
    }

    /// @dev Drop oracle price by percentage
    /// @param asset The asset to drop price for
    /// @param dropPercent Percentage to drop (e.g., 15 = 15% drop)
    /// @return newPrice The new oracle price after drop
    function _dropOraclePrice(address asset, uint256 dropPercent) internal returns (uint256) {
        return _utilDropOraclePrice(s_bitmorPool, asset, dropPercent);
    }

    /// @dev Execute full liquidation
    /// @param lsa The Loan Smart Account to liquidate
    /// @param debtToCover Amount of debt to cover (use type(uint256).max for max)
    /// @param receiveAToken True to receive aTokens, false for underlying
    function _executeFullLiquidation(address lsa, uint256 debtToCover, bool receiveAToken) internal {
        _utilExecuteFullLiquidation(
            s_bitmorPool, liquidator, collateralAsset, debtAsset, lsa, debtToCover, receiveAToken
        );
    }

    /// @dev Get the variable debt token balance for an LSA
    /// @param lsa The Loan Smart Account address
    /// @return The variable debt token balance
    function _getDebtBalance(address lsa) internal view returns (uint256) {
        return _utilGetDebtBalance(s_bitmorPool, debtAsset, lsa);
    }

    /// @dev Get the collateral (aToken) balance for an LSA
    /// @param lsa The Loan Smart Account address
    /// @return The aToken balance
    function _getCollateralBalance(address lsa) internal view returns (uint256) {
        return _utilGetATokenBalance(s_bitmorPool, collateralAsset, lsa);
    }

    // ============ Liquidation Helpers ============
    // Additional liquidation-related helpers consolidated from liquidation test files

    /// @dev Snapshot liquidator balances
    /// @return debtBalance The liquidator's debt asset balance
    /// @return collateralBalance The liquidator's collateral asset balance
    function _snapshotLiquidatorBalances() internal view returns (uint256 debtBalance, uint256 collateralBalance) {
        debtBalance = IERC20(debtAsset).balanceOf(liquidator);
        collateralBalance = IERC20(collateralAsset).balanceOf(liquidator);
    }

    /// @dev Execute micro liquidation
    /// @param lsa The Loan Smart Account to liquidate
    function _executeMicroLiquidation(address lsa) internal {
        _utilExecuteMicroLiquidation(s_bitmorPool, liquidator, collateralAsset, debtAsset, lsa);
    }

    /// @dev Check liquidation type for an LSA
    /// @param lsa The Loan Smart Account to check
    /// @return liquidationType 0=None, 1=Full, 2=Micro
    function _checkLiquidationType(address lsa) internal returns (uint256) {
        return _utilCheckLiquidationType(s_bitmorPool, lsa);
    }

    /// @dev Get BTC price from oracle
    /// @return The BTC price (8 decimals)
    function _getBtcPrice() internal view returns (uint256) {
        return _utilGetAssetPrice(s_bitmorPool, collateralAsset);
    }

    /// @dev Get USDC price from oracle
    /// @return The USDC price (8 decimals)
    function _getUsdcPrice() internal view returns (uint256) {
        return _utilGetAssetPrice(s_bitmorPool, debtAsset);
    }

    /// @dev Get debt aToken address
    /// @return The aToken address for the debt asset
    function _getDebtATokenAddress() internal view returns (address) {
        return _utilGetATokenAddress(s_bitmorPool, debtAsset);
    }

    /// @dev Get LSA variable debt balance (alias for _getDebtBalance for clarity in liquidation tests)
    /// @param lsa The Loan Smart Account address
    /// @return The variable debt token balance
    function _getLsaDebtBalance(address lsa) internal view returns (uint256) {
        return _utilGetDebtBalance(s_bitmorPool, debtAsset, lsa);
    }

    /// @dev Get liquidation bonus in bps
    /// @return The liquidation bonus in basis points
    function _getLiquidationBonus() internal view returns (uint256) {
        return _utilGetLiquidationBonus(s_bitmorPool, collateralAsset);
    }

    /// @dev Calculate expected collateral seized for a given debt amount
    /// @param debtPaid The amount of debt being paid
    /// @return The expected collateral amount (with liquidation bonus)
    function _calculateExpectedCollateralSeized(uint256 debtPaid) internal view returns (uint256) {
        return _utilCalculateExpectedCollateralSeized(s_bitmorPool, collateralAsset, debtAsset, debtPaid);
    }
}
