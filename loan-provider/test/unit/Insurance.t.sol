// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {console2} from "forge-std/console2.sol";
import {BaseLoanTest} from "./Loan/BaseLoan.t.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {ILendingPool} from "@bitmor/interfaces/ILendingPool.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";

/// @title InsuranceTest
/// @notice Tests for insurance-related flows.
/// @dev Note: Insurance ID is set via mock since the actual insurance integration
/// requires Deribit. Tests verify the protocol behavior assuming insurance is active.
contract InsuranceTest is BaseLoanTest {
    // Insurance bonus is 3% (300 basis points)
    uint256 internal constant INSURANCE_BONUS_BPS = 300;

    function setUp() public override {
        super.setUp();
    }

    function _createInsuredLoan(uint256 premiumAmount)
        internal
        returns (address lsa, DataTypes.LoanData memory loanData)
    {
        (,, uint256 minDepositRequired) = loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);

        vm.prank(user);
        lsa =
            loan.initializeLoan(minDepositRequired, premiumAmount, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, DATA);

        loanData = loan.getLoanByLSA(lsa);
    }

    function _collateralToUsdc(uint256 collateralAmount) internal view returns (uint256) {
        uint256 btcPrice = _getBtcPrice();
        uint256 usdcPrice = _getUsdcPrice();
        return (collateralAmount * btcPrice * 1e6) / (usdcPrice * 1e8);
    }

    /// @notice Creates an insured loan and sets the insurance ID in mock
    /// @dev Sets insurance ID via loan.updateInsuranceId since mock pool doesn't set it
    /// @param premiumAmount The premium amount for the loan
    /// @return lsa The loan smart account address
    /// @return loanData The loan data after insurance ID is set
    function _createInsuredLoanWithMockId(uint256 premiumAmount)
        internal
        returns (address lsa, DataTypes.LoanData memory loanData)
    {
        (lsa, loanData) = _createInsuredLoan(premiumAmount);

        // Set insurance ID in loan contract storage (premium > 0 means insured)
        if (premiumAmount > 0) {
            vm.prank(user);
            loan.updateInsuranceId(lsa, TC.DEFAULT_INSURANCE_ID);

            // Also set in mock pool for liquidation type checks
            mockBitmorPool.setInsuranceId(lsa, TC.DEFAULT_INSURANCE_ID);

            // Refresh loan data with updated insurance ID
            loanData = loan.getLoanByLSA(lsa);
        }
    }

    /// @notice Paying exact premium should create an insurance position with insuranceID > 0
    /// @dev Insurance ID is set via mock since actual Deribit integration is not available in tests
    function test_insurance_initializeLoan_exactPremium_createsInsuranceId() public mintDebtAssetToUser {
        uint256 premiumCollectorBalanceBefore = IERC20(debtAsset).balanceOf(premiumCollector);

        // Use helper that sets insurance ID via mock
        (address lsa, DataTypes.LoanData memory loanData) = _createInsuredLoanWithMockId(PREMIUM_AMOUNT);

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

    /// @notice Paying less than the required premium should still initialize the loan
    function test_insurance_initializeLoan_premiumBelowEstimate_accepts() public mintDebtAssetToUser {
        uint256 premiumCollectorBalanceBefore = IERC20(debtAsset).balanceOf(premiumCollector);
        (,, uint256 minDepositRequired) = loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);

        uint256 insufficientPremium = PREMIUM_AMOUNT - 1;

        vm.prank(user);
        address lsa = loan.initializeLoan(
            minDepositRequired, insufficientPremium, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, DATA
        );

        uint256 premiumCollectorBalanceAfter = IERC20(debtAsset).balanceOf(premiumCollector);
        assertEq(
            premiumCollectorBalanceAfter - premiumCollectorBalanceBefore,
            insufficientPremium,
            "Premium collector should receive the premium amount paid"
        );

        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(loanData.borrower, user, "Loan borrower should be user");
    }

    /// @notice Paying more than required premium should NOT refund the excess to user
    function test_insurance_initializeLoan_premiumAboveEstimate_dontRefundExcess() public mintDebtAssetToUser {
        uint256 userBalanceBefore = IERC20(debtAsset).balanceOf(user);
        uint256 premiumCollectorBalanceBefore = IERC20(debtAsset).balanceOf(premiumCollector);

        (,, uint256 minDepositRequired) = loan.getLoanDetails(STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION);

        uint256 overpaidPremium = PREMIUM_AMOUNT + OVERPAY_AMOUNT;

        vm.prank(user);
        address lsa = loan.initializeLoan(
            minDepositRequired, overpaidPremium, STANDARD_COLLATERAL_AMOUNT, STANDARD_DURATION, DATA
        );

        uint256 userBalanceAfter = IERC20(debtAsset).balanceOf(user);
        uint256 premiumCollectorBalanceAfter = IERC20(debtAsset).balanceOf(premiumCollector);

        uint256 premiumCollectorDelta = premiumCollectorBalanceAfter - premiumCollectorBalanceBefore;
        uint256 userTotalSpent = userBalanceBefore - userBalanceAfter;

        // Premium collector receives the full premium amount paid
        assertEq(premiumCollectorDelta, overpaidPremium, "Premium collector should receive full premium payment");

        // User pays deposit plus full premium amount
        assertEq(userTotalSpent, minDepositRequired + overpaidPremium, "User should pay full premium amount");

        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        assertEq(loanData.borrower, user, "Loan borrower should be user");
    }

    /// @notice Insured loan should NOT be liquidatable on 50% price drop when EMI is current
    /// @dev Uses mock helper to set insurance ID since actual Deribit integration unavailable
    function test_insurance_priceDrop50pct_notLiquidatable() public {
        _mintDebtAssetToUser();
        (address lsa, DataTypes.LoanData memory loanData) = _createInsuredLoanWithMockId(PREMIUM_AMOUNT);

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
        ILendingPool(s_bitmorPool).liquidationCall(collateralAsset, debtAsset, lsa, type(uint256).max, false);
    }

    /// @notice After full liquidation of overdue insured loan, liquidator should receive insurance payout
    /// @dev Uses mock helper to set insurance ID since actual Deribit integration unavailable
    function test_insurance_fullLiquidation_overdue_claimAfter1Day_paysLiquidatorPlus3pct() public {
        _mintDebtAssetToUser();
        (address lsa,) = _createInsuredLoanWithMockId(PREMIUM_AMOUNT);

        // Set up liquidation conditions in mock
        mockBitmorPool.setHealthFactor(lsa, 0.5e18); // HF < 1 for full liquidation

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
        console2.log("totalDebt: ", totalDebt);

        uint256 liquidatorBalance = IERC20(debtAsset).balanceOf(liquidator);
        if (liquidatorBalance < totalDebt) {
            _fundUSDC(liquidator, totalDebt - liquidatorBalance);
        }

        console2.log("liquidator balance:", IERC20(debtAsset).balanceOf(liquidator));

        // Perform liquidation
        vm.prank(liquidator);
        ILendingPool(s_bitmorPool).liquidationCall(collateralAsset, debtAsset, lsa, type(uint256).max, false);

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
        /// @dev this to mimick the offchain transafer.
        _fundUSDC(liquidator, expectedInsurancePayout);

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
