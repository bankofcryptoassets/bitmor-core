// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./BaseLoanTest.t.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@bitmor/dependencies/openzeppelin/IERC20.sol";
import {ILendingPool} from "@bitmor/interfaces/ILendingPool.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

/// @title LendingPoolTest
/// @notice Tests for Bitmor LendingPool security restrictions and loan payment calculations
contract LendingPoolTest is BaseLoanTest {
    using FixedPointMathLib for uint256;

    // ============ Constants ============

    /// @dev Standard deposit amount for pool tests (100,000 USDC)
    uint256 internal constant POOL_DEPOSIT_AMOUNT = 100_000e6;

    /// @dev Small borrow amount to ensure revert is from access control, not liquidity
    uint256 internal constant SMALL_BORROW_AMOUNT = 1_000e6;

    /// @dev BTC amount to seed for liquidity tests (0.1 BTC)
    uint256 internal constant BTC_SEED_AMOUNT = 0.1e8;

    /// @dev Max APR for amortization calculation (12% = 0.12)
    uint256 internal constant MAX_APR_BPS = 1200;

    /// @dev BPS denominator
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    /// @dev Precision for payment calculations (1e18 for fixed-point math)
    uint256 internal constant PRECISION = 1e18;

    /// @dev Tolerance for payment comparison (10 USDC wei - accounts for rounding)
    uint256 internal constant PAYMENT_TOLERANCE = 10;

    /// @dev Dust threshold for considering debt as fully repaid
    uint256 internal constant DEBT_DUST_THRESHOLD = 100;

    // ============ Test Actors ============

    address internal liquidityProvider;

    // ============ Setup ============

    function setUp() public virtual override {
        super.setUp();
        
        liquidityProvider = makeAddr("liquidityProvider");
        _updateAddressesProviderBitmorLoan();
    }

    // ============ Helper Functions ============

    /// @notice Mint BTC to an address
    function _mintBtcTo(address to, uint256 amount) internal {
        vm.prank(to);
        (bool success,) = collateralAsset.call(abi.encodeWithSignature("mint(uint256)", amount));
        assertTrue(success, "BTC_MINT_ERROR");
    }

    /// @notice Seed BTC liquidity into the Bitmor pool
    function _seedBtcLiquidity() internal {
        _mintBtcTo(liquidityProvider, BTC_SEED_AMOUNT);
        
        vm.startPrank(liquidityProvider);
        IERC20(collateralAsset).approve(s_bitmorPool, BTC_SEED_AMOUNT);
        ILendingPool(s_bitmorPool).deposit(collateralAsset, BTC_SEED_AMOUNT, liquidityProvider, 0);
        vm.stopPrank();
    }

    /// @notice Create a loan to increase pool utilization
    function _createLoanForUtilization(address loanUser) internal returns (address lsa) {
        _utilSeedUserAndApprove(loanUser, debtAsset, address(loan), DEBT_ASSET_TO_MINT_TO_USER);
        
        (,, uint256 minDepositRequired) = loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);
        
        vm.prank(loanUser);
        lsa = loan.initializeLoan(minDepositRequired, PREMIUM_AMOUNT, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, DATA);
    }

    /// @notice Calculate amortized monthly payment using standard formula
    /// @dev Formula: P * r * (1+r)^n / ((1+r)^n - 1)
    function _calculateAmortizedPayment(
        uint256 principal,
        uint256 annualRateBps,
        uint256 months
    ) internal pure returns (uint256 monthlyPayment) {
        if (principal == 0 || months == 0) return 0;
        
        // Monthly rate = annual rate / 12, scaled by PRECISION
        uint256 monthlyRateScaled = (annualRateBps * PRECISION) / (BPS_DENOMINATOR * 12);
        
        // (1 + r) in scaled form
        uint256 onePlusR = PRECISION + monthlyRateScaled;
        
        // Calculate (1+r)^n iteratively
        uint256 onePlusRPowN = PRECISION;
        for (uint256 i = 0; i < months; i++) {
            onePlusRPowN = (onePlusRPowN * onePlusR) / PRECISION;
        }
        
        // Numerator: P * r * (1+r)^n
        uint256 numerator = (principal * monthlyRateScaled * onePlusRPowN) / PRECISION;
        
        // Denominator: (1+r)^n - 1
        uint256 denominator = onePlusRPowN - PRECISION;
        
        if (denominator == 0) return principal / months;
        
        monthlyPayment = (numerator * PRECISION) / denominator / PRECISION;
    }

    // ============ Test 1: User Cannot Borrow USDC ============

    /// @notice Test that regular users cannot borrow USDC directly from the Bitmor pool
    /// @dev USDC liquidity is reserved for BTC-buy loans (protocol-only flow)
    /// @dev This test will FAIL until access control is implemented in LendingPool.borrow()
    function test_lendingPool_borrowUSDC_revertsForUser() public {
        // Setup: Mint USDC to user
        vm.startPrank(user);
        (bool mintSuccess,) = debtAsset.call(abi.encodeWithSignature("mint(uint256)", POOL_DEPOSIT_AMOUNT));
        assertTrue(mintSuccess, "USDC_MINT_ERROR");
        
        // User approves pool
        IERC20(debtAsset).approve(s_bitmorPool, type(uint256).max);
        
        // User deposits USDC as collateral
        ILendingPool(s_bitmorPool).deposit(debtAsset, POOL_DEPOSIT_AMOUNT, user, 0);
        vm.stopPrank();
        
        // User attempts to borrow USDC - should revert with UnauthorizedCaller
        vm.expectRevert(Errors.UnauthorizedCaller.selector);
        vm.prank(user);
        ILendingPool(s_bitmorPool).borrow(debtAsset, SMALL_BORROW_AMOUNT, 2, 0, user);
    }

    // ============ Test 2: User Cannot Borrow BTC ============

    /// @notice Test that regular users cannot borrow BTC directly from the Bitmor pool
    /// @dev BTC reserve is collateral, not for retail borrowing
    /// @dev This test will FAIL until access control is implemented in LendingPool.borrow()
    function test_lendingPool_borrowBTC_revertsForUser() public {
        // Seed BTC liquidity so revert is from access control, not insufficient liquidity
        _seedBtcLiquidity();
        
        // Setup: Mint USDC to user for collateral
        vm.startPrank(user);
        (bool mintSuccess,) = debtAsset.call(abi.encodeWithSignature("mint(uint256)", POOL_DEPOSIT_AMOUNT));
        assertTrue(mintSuccess, "USDC_MINT_ERROR");
        
        // User approves and deposits USDC as collateral
        IERC20(debtAsset).approve(s_bitmorPool, type(uint256).max);
        ILendingPool(s_bitmorPool).deposit(debtAsset, POOL_DEPOSIT_AMOUNT, user, 0);
        vm.stopPrank();
        
        uint256 btcBorrowAmount = BTC_SEED_AMOUNT / 10; // 0.01 BTC
        
        // User attempts to borrow BTC - should revert with UnauthorizedCaller
        vm.expectRevert(Errors.UnauthorizedCaller.selector);
        vm.prank(user);
        ILendingPool(s_bitmorPool).borrow(collateralAsset, btcBorrowAmount, 2, 0, user);
    }

    // ============ Test 3: Monthly Payment Calculation at Max Rate ============

    /// @notice Test that estimatedMonthlyPayment uses max APR (12%) for amortization
    /// @dev This test will FAIL until LoanLogic uses max APR instead of currentVariableBorrowRate
    function test_monthlyPaymentCalculation_amortizesAtMaxRate_12pct() public {
        // Mock oracle prices: BTC = $100,000, USDC = $1
        uint256 btcPrice = 100_000e8;
        uint256 usdcPrice = 1e8;
        
        _utilSetOraclePrice(s_bitmorPool, collateralAsset, btcPrice);
        _utilSetOraclePrice(s_bitmorPool, debtAsset, usdcPrice);
        
        // Get loan details for 1 BTC, 12 months
        uint256 collateralAmount = 1e8;
        uint256 duration = 12;
        
        (uint256 loanAmount, uint256 estimatedMonthlyPayment, uint256 minDepositRequired) = 
            loan.getLoanDetails(collateralAmount, duration);
        
        // Verify intermediate values
        uint256 expectedLoanAmount = 70_000e6;
        uint256 expectedMinDeposit = 30_000e6;
        
        assertEq(loanAmount, expectedLoanAmount, "Loan amount should be 70% of BTC value");
        assertEq(minDepositRequired, expectedMinDeposit, "Min deposit should be 30% of BTC value");
        
        // Calculate expected payment at MAX APR (12%)
        uint256 expectedPayment = _calculateAmortizedPayment(
            expectedLoanAmount,
            MAX_APR_BPS,
            duration
        );
        
        // Assert monthly payment matches expected (within tolerance)
        assertApproxEqAbs(
            estimatedMonthlyPayment,
            expectedPayment,
            PAYMENT_TOLERANCE,
            "Monthly payment should be calculated at max 12% APR"
        );
    }

    // ============ Test 4: High Utilization - 12 Payments Fully Repay Loan ============

    /// @notice Test that 12 monthly payments fully repay loan at ~100% utilization
    function test_highUtilization_100pct_12PaymentsFullyRepayLoan() public {
        // Create the main test loan
        _mintDebtAssetToUser();
        
        (,, uint256 minDepositRequired) = loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);
        
        vm.prank(user);
        address lsa = loan.initializeLoan(minDepositRequired, PREMIUM_AMOUNT, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, DATA);
        
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        uint256 estimatedMonthlyPayment = loanData.estimatedMonthlyPayment;
        
        // Drive utilization high by creating additional loans
        for (uint256 i = 0; i < 3; i++) {
            address utilizationUser = makeAddr(string(abi.encodePacked("utilizationUser", i)));
            _createLoanForUtilization(utilizationUser);
        }
        
        // Execute 12 monthly payments
        for (uint256 month = 1; month <= 12; month++) {
            uint256 debtBefore = _getDebtBalance(lsa);
            
            if (debtBefore == 0) break;
            
            _utilWarpPastRepaymentInterval();
            
            // Fund user for repayment
            vm.startPrank(user);
            (bool mintSuccess,) = debtAsset.call(abi.encodeWithSignature("mint(uint256)", estimatedMonthlyPayment));
            assertTrue(mintSuccess, "REPAYMENT_MINT_ERROR");
            IERC20(debtAsset).approve(address(loan), estimatedMonthlyPayment);
            vm.stopPrank();
            
            vm.prank(user);
            loan.repay(lsa, estimatedMonthlyPayment);
            
            uint256 debtAfter = _getDebtBalance(lsa);
            
            assertLt(debtAfter, debtBefore, "Debt should decrease each month");
        }
        
        // Assert debt is fully repaid
        uint256 finalDebt = _getDebtBalance(lsa);
        assertLe(finalDebt, DEBT_DUST_THRESHOLD, "Debt should be zero or dust after 12 payments");
    }

    // ============ Test 5: Low Utilization - Final Payment Overcovers Debt ============

    /// @notice Test that at ~90% utilization, final payment exceeds remaining debt
    function test_lowUtilization_90pct_finalPaymentOvercoversDebt() public {
        // Create the test loan
        _mintDebtAssetToUser();
        
        (,, uint256 minDepositRequired) = loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);
        
        vm.prank(user);
        address lsa = loan.initializeLoan(minDepositRequired, PREMIUM_AMOUNT, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, DATA);
        
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        uint256 estimatedMonthlyPayment = loanData.estimatedMonthlyPayment;
        
        // Keep utilization at ~90% with just 1 additional loan
        address utilizationUser = makeAddr("utilizationUser");
        _createLoanForUtilization(utilizationUser);
        
        // Execute 11 monthly payments
        for (uint256 month = 1; month <= 11; month++) {
            _utilWarpPastRepaymentInterval();
            
            vm.startPrank(user);
            (bool mintSuccess,) = debtAsset.call(abi.encodeWithSignature("mint(uint256)", estimatedMonthlyPayment));
            assertTrue(mintSuccess, "REPAYMENT_MINT_ERROR");
            IERC20(debtAsset).approve(address(loan), estimatedMonthlyPayment);
            vm.stopPrank();
            
            vm.prank(user);
            loan.repay(lsa, estimatedMonthlyPayment);
        }
        
        // Check debt before final payment
        uint256 debtRemaining = _getDebtBalance(lsa);
        
        // At lower utilization, remaining debt should be less than monthly payment
        assertLt(debtRemaining, estimatedMonthlyPayment, "Remaining debt should be less than monthly payment at ~90% utilization");
        
        // Execute final payment
        _utilWarpPastRepaymentInterval();
        
        vm.startPrank(user);
        (bool finalMintSuccess,) = debtAsset.call(abi.encodeWithSignature("mint(uint256)", estimatedMonthlyPayment));
        assertTrue(finalMintSuccess, "FINAL_REPAYMENT_MINT_ERROR");
        IERC20(debtAsset).approve(address(loan), estimatedMonthlyPayment);
        vm.stopPrank();
        
        vm.prank(user);
        uint256 actualRepaid = loan.repay(lsa, estimatedMonthlyPayment);
        
        // actualRepaid should be less than estimatedMonthlyPayment
        assertLt(actualRepaid, estimatedMonthlyPayment, "Final repay should return less than estimated payment");
        
        // Debt should now be zero
        uint256 finalDebt = _getDebtBalance(lsa);
        assertLe(finalDebt, DEBT_DUST_THRESHOLD, "Debt should be zero after final payment");
    }
}
