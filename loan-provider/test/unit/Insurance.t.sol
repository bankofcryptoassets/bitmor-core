// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseLoanTest} from "./BaseLoanTest.t.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@bitmor/dependencies/openzeppelin/IERC20.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {ILendingPool} from "@bitmor/interfaces/ILendingPool.sol";

/// @title InsuranceTest
/// @notice Tests for insurance functionality - these tests will fail until insurance features are implemented
contract InsuranceTest is BaseLoanTest {
    
    uint256 internal constant OVERPAY_AMOUNT = 500e6;
    uint256 internal constant PRICE_DROP_50_PERCENT = 50;
    uint256 internal constant PRICE_DROP_FOR_LIQUIDATION = 20;
    uint256 internal constant ONE_DAY = 1 days;
    uint256 internal constant INSURANCE_BONUS_BPS = 300; // 3%
    uint256 internal constant BPS_DENOMINATOR = 10_000;
    uint256 internal constant LIQUIDATION_TYPE_NONE = 0;
    uint256 internal constant LIQUIDATION_TYPE_FULL = 1;

    address internal premiumCollector;
    
    function setUp() public override {
        super.setUp();
        premiumCollector = loan.getPremiumCollector();
    }

    function _createInsuredLoan(uint256 premiumAmount) 
        internal 
        returns (address lsa, DataTypes.LoanData memory loanData) 
    {
        (,, uint256 minDepositRequired) = loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);
        
        vm.prank(user);
        lsa = loan.initializeLoan(
            minDepositRequired, 
            premiumAmount, 
            STANDARD_COLLATERAL_AMOUNT, 
            STANDARD_DURATION, 
            DATA
        );
        
        loanData = loan.getLoanByLSA(lsa);
    }
    
    function _collateralToUsdc(uint256 collateralAmount) internal view returns (uint256) {
        uint256 btcPrice = _getBtcPrice();
        uint256 usdcPrice = _getUsdcPrice();
        return (collateralAmount * btcPrice * 1e6) / (usdcPrice * 1e8);
    }

    /// @notice Paying exact premium should create an insurance position with insuranceID > 0
    function test_insurance_initializeLoan_exactPremium_createsInsuranceId() public mintDebtAssetToUser {
        uint256 premiumCollectorBalanceBefore = IERC20(debtAsset).balanceOf(premiumCollector);
        
        (address lsa, DataTypes.LoanData memory loanData) = _createInsuredLoan(PREMIUM_AMOUNT);
        
        uint256 premiumCollectorBalanceAfter = IERC20(debtAsset).balanceOf(premiumCollector);
        
        // Insurance ID must be > 0 for insured loans
        assertGt(loanData.insuranceID, 0, "insuranceID must be > 0 when premium is paid");
        
        // Premium collector received exactly the premium amount
        assertEq(
            premiumCollectorBalanceAfter - premiumCollectorBalanceBefore,
            PREMIUM_AMOUNT,
            "Premium collector should receive exactly PREMIUM_AMOUNT"
        );
        
        assertTrue(lsa != address(0), "LSA should be created");
        assertEq(uint256(loanData.status), uint256(DataTypes.LoanStatus.Active), "Loan should be active");
    }

    /// @notice Paying less than the required premium should revert
    function test_insurance_initializeLoan_premiumBelowEstimate_reverts() public mintDebtAssetToUser {
        (,, uint256 minDepositRequired) = loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);
        
        uint256 insufficientPremium = PREMIUM_AMOUNT - 1;
        
        vm.prank(user);
        vm.expectRevert();
        loan.initializeLoan(
            minDepositRequired, 
            insufficientPremium, 
            STANDARD_COLLATERAL_AMOUNT, 
            STANDARD_DURATION, 
            DATA
        );
    }

    /// @notice Paying more than required premium should refund the excess to user
    function test_insurance_initializeLoan_premiumAboveEstimate_refundsExcess() public mintDebtAssetToUser {
        uint256 userBalanceBefore = IERC20(debtAsset).balanceOf(user);
        uint256 premiumCollectorBalanceBefore = IERC20(debtAsset).balanceOf(premiumCollector);
        
        (,, uint256 minDepositRequired) = loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);
        
        uint256 overpaidPremium = PREMIUM_AMOUNT + OVERPAY_AMOUNT;
        
        vm.prank(user);
        address lsa = loan.initializeLoan(
            minDepositRequired, 
            overpaidPremium, 
            STANDARD_COLLATERAL_AMOUNT, 
            STANDARD_DURATION, 
            DATA
        );
        
        uint256 userBalanceAfter = IERC20(debtAsset).balanceOf(user);
        uint256 premiumCollectorBalanceAfter = IERC20(debtAsset).balanceOf(premiumCollector);
        
        uint256 premiumCollectorDelta = premiumCollectorBalanceAfter - premiumCollectorBalanceBefore;
        uint256 userTotalSpent = userBalanceBefore - userBalanceAfter;
        
        // Premium collector should only receive expected premium, not the overpayment
        assertEq(premiumCollectorDelta, PREMIUM_AMOUNT, "Premium collector should only receive PREMIUM_AMOUNT");
        
        // User should be refunded excess (total spent = deposit + PREMIUM_AMOUNT only)
        assertEq(userTotalSpent, minDepositRequired + PREMIUM_AMOUNT, "User should be refunded excess premium");
        
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(loanData.borrower, user, "Loan borrower should be user");
    }

    /// @notice Insured loan should NOT be liquidatable on 50% price drop when EMI is current
    function test_insurance_priceDrop50pct_notLiquidatable() public {
        _mintDebtAssetToUser();
        (address lsa, DataTypes.LoanData memory loanData) = _createInsuredLoan(PREMIUM_AMOUNT);
        
        _updateAddressesProviderBitmorLoan();
        
        // Prerequisite: loan must be insured
        assertGt(loanData.insuranceID, 0, "insuranceID must be > 0 for insured loan");
        
        // Drop price by 50%
        _dropOraclePrice(collateralAsset, PRICE_DROP_50_PERCENT);
        
        uint256 liquidationType = _checkLiquidationType(lsa);
        
        // Insured loan should not be liquidatable when EMI is current
        assertEq(liquidationType, LIQUIDATION_TYPE_NONE, "Insured loan should not be liquidatable on price drop");
        
        // Liquidation call should revert
        _fundLiquidator();
        
        vm.prank(liquidator);
        vm.expectRevert();
        ILendingPool(s_bitmorPool).liquidationCall(
            collateralAsset,
            debtAsset,
            lsa,
            type(uint256).max,
            false
        );
    }

    /// @notice After full liquidation of overdue insured loan, liquidator should receive insurance payout
    function test_insurance_fullLiquidation_overdue_claimAfter1Day_paysLiquidatorPlus3pct() public {
        _mintDebtAssetToUser();
        (address lsa,) = _createInsuredLoan(PREMIUM_AMOUNT);
        
        _updateAddressesProviderBitmorLoan();
        _fundLiquidator();
        
        // Force HF < 1
        _dropOraclePrice(collateralAsset, PRICE_DROP_FOR_LIQUIDATION);
        
        // Make EMI overdue
        _warpPastGracePeriod();
        
        uint256 liquidationType = _checkLiquidationType(lsa);
        assertGt(liquidationType, LIQUIDATION_TYPE_NONE, "Overdue insured loan should be liquidatable");
        
        // If micro liquidation, drop price more to trigger full liquidation
        if (liquidationType != LIQUIDATION_TYPE_FULL) {
            _dropOraclePrice(collateralAsset, 30);
        }
        
        // Record state before liquidation
        uint256 liquidatorUsdcBeforeLiquidation = IERC20(debtAsset).balanceOf(liquidator);
        uint256 liquidatorCollateralBeforeLiquidation = IERC20(collateralAsset).balanceOf(liquidator);
        uint256 totalDebt = _getLsaDebtBalance(lsa);
        
        // Perform liquidation
        vm.prank(liquidator);
        ILendingPool(s_bitmorPool).liquidationCall(
            collateralAsset,
            debtAsset,
            lsa,
            totalDebt,
            false
        );
        
        // Record state after liquidation
        uint256 liquidatorUsdcAfterLiquidation = IERC20(debtAsset).balanceOf(liquidator);
        uint256 liquidatorCollateralAfterLiquidation = IERC20(collateralAsset).balanceOf(liquidator);
        
        uint256 usdcPaid = liquidatorUsdcBeforeLiquidation - liquidatorUsdcAfterLiquidation;
        uint256 collateralReceived = liquidatorCollateralAfterLiquidation - liquidatorCollateralBeforeLiquidation;
        uint256 collateralValueUSDC = _collateralToUsdc(collateralReceived);
        
        // Calculate expected insurance payout: (uncovered debt) + (3% of total debt)
        uint256 uncoveredDebt = usdcPaid > collateralValueUSDC ? usdcPaid - collateralValueUSDC : 0;
        uint256 insuranceBonus = (totalDebt * INSURANCE_BONUS_BPS) / BPS_DENOMINATOR;
        uint256 expectedInsurancePayout = uncoveredDebt + insuranceBonus;
        
        // Wait 1 day for insurance claim eligibility
        vm.warp(block.timestamp + ONE_DAY);
        
        // Check if liquidator received insurance payout
        uint256 liquidatorUsdcAfterClaim = IERC20(debtAsset).balanceOf(liquidator);
        uint256 insurancePayoutReceived = liquidatorUsdcAfterClaim - liquidatorUsdcAfterLiquidation;
        
        // Liquidator must receive the insurance payout from Deribit
        assertGe(insurancePayoutReceived, expectedInsurancePayout, "Liquidator must receive insurance payout");
        
        // Total value received must cover what liquidator paid
        uint256 totalValueReceived = collateralValueUSDC + insurancePayoutReceived;
        assertGe(totalValueReceived, usdcPaid, "Liquidator total value must be >= USDC paid");
    }
}
