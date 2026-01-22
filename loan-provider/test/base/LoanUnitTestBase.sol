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

/// @title LoanUnitTestBase
/// @notice Base for Loan contract unit tests with mock dependencies
/// @dev Deploys real Loan contract with MockAaveV3Pool and mock tokens
abstract contract LoanUnitTestBase is UnitTestBase {
    // ============ Loan Infrastructure ============
    Loan public loan;
    LoanVaultFactory public loanVaultFactory;
    address public loanVaultImplementation;

    // ============ Test Actors ============
    address public user;
    address public liquidator;

    // ============ Protocol Addresses (from HelperConfig) ============
    address public premiumCollector;

    // ============ Mock Protocol Addresses (placeholders) ============
    address public mockBitmorPool;
    address public mockOracle;
    address public mockSwapAdapter;

    function setUp() public virtual override {
        super.setUp();

        user = makeAddr("user");
        liquidator = makeAddr("liquidator");
        premiumCollector = config.getPremiumCollector();

        // Create placeholder addresses for dependencies not yet mocked
        mockBitmorPool = makeAddr("mockBitmorPool");
        mockOracle = makeAddr("mockOracle");
        mockSwapAdapter = makeAddr("mockSwapAdapter");

        vm.startPrank(admin);
        _deployLoanInfrastructure();
        _configureLoanRoles();
        vm.stopPrank();

        _fundTestAccounts();

        // Update snapshot after full setup
        _baseSnapshotId = vm.snapshot();
    }

    /// @notice Deploys Loan contract with mock dependencies
    function _deployLoanInfrastructure() internal virtual {
        loanVaultImplementation = address(new LoanVault());

        // Deploy Loan with mock Aave V3 pool and mock tokens
        // Note: mockBitmorPool, mockOracle, mockSwapAdapter are placeholder addresses
        // that pass zero-address checks but have no implementation
        loan = new Loan(
            address(manager),               // AccessManager
            address(mockAavePool),          // Mock Aave V3 for flash loans
            makeAddr("aaveAddressesProvider"), // aaveAddressesProvider (placeholder)
            mockBitmorPool,                 // bitmorPool (placeholder)
            mockOracle,                     // oracle (placeholder)
            address(mockCbBTC),             // collateralAsset
            address(mockUSDC),              // debtAsset
            address(mockCbBTC),             // btc token
            mockSwapAdapter,                // swapAdapter (placeholder)
            address(0),                     // zQuoter (allowed to be zero)
            premiumCollector,               // premiumCollector
            config.getPreClosureFee(),      // preClosureFeeBps
            config.getGracePeriod(),        // gracePeriod
            config.getLiquidationBuffer()   // liquidationBuffer
        );

        loanVaultFactory = new LoanVaultFactory(loanVaultImplementation, address(loan));
        loan.setLoanVaultFactory(address(loanVaultFactory));
    }

    /// @notice Configures roles for Loan contract
    function _configureLoanRoles() internal virtual {
        _setLoanRoles(user);
        _setLoanTargetSelectors(address(loan));
    }

    /// @notice Funds test accounts with tokens
    function _fundTestAccounts() internal virtual {
        _fundUSDC(user, TC.USER_USDC_BALANCE);
        _fundCbBTC(user, TC.USER_CBBTC_BALANCE);

        vm.prank(user);
        mockUSDC.approve(address(loan), type(uint256).max);

        vm.prank(user);
        mockCbBTC.approve(address(loan), type(uint256).max);
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
}
