// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {console2} from "forge-std/console2.sol";
import {Helper} from "./Helper.t.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@bitmor/dependencies/openzeppelin/IERC20.sol";
import {ILendingPool} from "@bitmor/interfaces/ILendingPool.sol";
import {ILendingPoolAddressesProvider} from "@bitmor/interfaces/ILendingPoolAddressesProvider.sol";
import {IPriceOracleGetter} from "@bitmor/interfaces/IPriceOracleGetter.sol";

/// @title LiquidationTest
/// @notice Tests for micro-liquidation and full liquidation functionality
contract LiquidationTest is Helper {
    // ============ Structs ============

    /// @dev Struct to hold micro-liquidation test variables and avoid stack too deep
    struct MicroLiquidationTestVars {
        address lsa;
        uint256 durationBefore;
        uint256 lastPaymentBefore;
        uint256 liquidatorDebtBefore;
        uint256 liquidatorCollateralBefore;
        uint256 liquidatorDebtAfter;
        uint256 liquidatorCollateralAfter;
        uint256 durationAfter;
        uint256 lastPaymentAfter;
        uint256 statusAfter;
        uint256 btcPriceUSD;
        uint256 usdcPriceUSD;
        uint256 collateralLiquidatedUSDValue;
    }

    /// @dev Struct to hold repeated micro-liquidation test variables
    struct RepeatedMicroLiquidationVars {
        address lsa;
        uint256 initialDuration;
        uint256 currentDuration;
        uint256 monthsLiquidated;
        uint256 liquidationType;
        uint256 totalDebtPaid;
        uint256 totalCollateralReceived;
        uint256 liquidatorDebtBefore;
        uint256 liquidatorCollateralBefore;
        uint256 liquidatorDebtAfter;
        uint256 liquidatorCollateralAfter;
        uint256 btcPriceUSD;
        uint256 collateralInLSA;
        // Full liquidation tracking
        uint256 fullLiqDebtPaid;
        uint256 fullLiqCollateralReceived;
        bool fullLiquidationExecuted;
    }

    // ============ Single Micro Liquidation Test ============

    /// @notice Test micro-liquidation when borrower has not paid monthly dues and grace period has passed
    /// @dev Micro-liquidation (type 2) is triggered when:
    ///      1. Loan is active
    ///      2. lastPaymentTimestamp + repaymentInterval + gracePeriod < block.timestamp
    ///      3. Collateral value is sufficient to cover the micro-liquidation
    function test_microLiquidation_whenPaymentOverdue() public setUpLoanForUser {
        MicroLiquidationTestVars memory vars;

        /// CRITICAL: Update the Bitmor Lending Pool's AddressesProvider to point to our test's Loan contract
        /// Without this, the Lending Pool will query the OLD deployed Loan contract on testnet
        _updateAddressesProviderBitmorLoan();

        /// Get LSA address
        vars.lsa = loan.getUserLoanAtIndex(user, 0);

        /// Get loan data before liquidation and store key values
        {
            DataTypes.LoanData memory loanDataBefore = loan.getLoanByLSA(vars.lsa);
            vars.durationBefore = loanDataBefore.duration;

            console2.log("=== Loan State Before Micro Liquidation ===");
            console2.log("LSA Address:", vars.lsa);
            console2.log("Loan Amount (USDC):", loanDataBefore.loanAmount);
            console2.log("Collateral Amount (BTC):", loanDataBefore.collateralAmount);
            console2.log("Duration (months):", vars.durationBefore);
            console2.log("Estimated Monthly Payment (USDC):", loanDataBefore.estimatedMonthlyPayment);

            /// Update loan to set lastPaymentTimestamp to createdAt
            loanDataBefore.lastPaymentTimestamp = loanDataBefore.createdAt;
            vars.lastPaymentBefore = loanDataBefore.lastPaymentTimestamp;

            vm.prank(owner);
            loan.updateLoanData(abi.encode(loanDataBefore), vars.lsa);
        }

        /// Warp time forward to make loan overdue
        _warpPastGracePeriod();

        /// Check type of liquidation - should be 2 (micro-liquidation)
        uint256 liquidationType = ILendingPool(s_bitmorPool).checkTypeOfLiquidation(vars.lsa);
        console2.log("");
        console2.log("=== Liquidation Type Check ===");
        console2.log("Liquidation Type (0=None, 1=Full, 2=Micro):", liquidationType);
        assertEq(liquidationType, 2, "Liquidation type should be 2 (micro-liquidation)");

        /// Fund liquidator
        _fundLiquidator();

        /// Get liquidator balances before
        vars.liquidatorDebtBefore = IERC20(debtAsset).balanceOf(liquidator);
        vars.liquidatorCollateralBefore = IERC20(collateralAsset).balanceOf(liquidator);

        console2.log("");
        console2.log("=== Liquidator Balances Before ===");
        console2.log("Liquidator Debt Asset (USDC):", vars.liquidatorDebtBefore);
        console2.log("Liquidator Collateral Asset (BTC):", vars.liquidatorCollateralBefore);

        /// Execute micro liquidation
        _executeMicroLiquidation(vars.lsa);

        /// Get balances after
        vars.liquidatorDebtAfter = IERC20(debtAsset).balanceOf(liquidator);
        vars.liquidatorCollateralAfter = IERC20(collateralAsset).balanceOf(liquidator);

        /// Get loan data after
        {
            DataTypes.LoanData memory loanDataAfter = loan.getLoanByLSA(vars.lsa);
            vars.durationAfter = loanDataAfter.duration;
            vars.lastPaymentAfter = loanDataAfter.lastPaymentTimestamp;
            vars.statusAfter = uint256(loanDataAfter.status);
        }

        /// Calculate USD value of liquidated collateral using the same oracle
        _calculateCollateralUSDValue(vars);

        /// Log results
        _logMicroLiquidationResults(vars);

        /// Run assertions
        _assertMicroLiquidationSuccess(vars);
    }

    // ============ Repeated Micro Liquidation Test ============

    /// @notice Test repeated micro-liquidations until full liquidation or loan completion
    /// @dev Each month:
    ///      1. Time passes (30 days + grace period)
    ///      2. User does not pay
    ///      3. Liquidator micro-liquidates
    ///      4. Check if full liquidation is now required
    ///      5. Loop continues until liquidationType == 1 (full) or duration == 0 (completed)
function test_repeatedMicroLiquidation_untilFullLiquidationOrCompletion() public setUpLoanForUser {
        RepeatedMicroLiquidationVars memory vars;
        
        // 1. Setup: Update AddressesProvider
        _updateAddressesProviderBitmorLoan();
        
        // 2. Setup: Get LSA and initial data
        vars.lsa = loan.getUserLoanAtIndex(user, 0);
        {
            DataTypes.LoanData memory loanDataInitial = loan.getLoanByLSA(vars.lsa);
            vars.initialDuration = loanDataInitial.duration;
            vars.currentDuration = loanDataInitial.duration;

            console2.log("=== Initial Loan State ===");
            console2.log("LSA Address:", vars.lsa);
            console2.log("Loan Amount (USDC):", loanDataInitial.loanAmount);
            console2.log("Collateral Amount (BTC):", loanDataInitial.collateralAmount);
            
            // Set payment timestamp to start the clock
            loanDataInitial.lastPaymentTimestamp = loanDataInitial.createdAt;
            vm.prank(owner);
            loan.updateLoanData(abi.encode(loanDataInitial), vars.lsa);
        }

        // 3. Setup: Fund Liquidator
        _fundLiquidator();
        uint256 liquidatorDebtStart = IERC20(debtAsset).balanceOf(liquidator);
        uint256 liquidatorCollateralStart = IERC20(collateralAsset).balanceOf(liquidator);

        // 4. Setup: Prepare for Price Manipulation
        address addressesProvider = ILendingPool(s_bitmorPool).getAddressesProvider();
        address oracleAddress = ILendingPoolAddressesProvider(addressesProvider).getPriceOracle();
        
        // Get the starting REAL price
        uint256 currentBtcPrice = IPriceOracleGetter(oracleAddress).getAssetPrice(collateralAsset);

        console2.log("");
        // UPDATED: Increased drop to 15% to force Full Liquidation before loan completion
        console2.log("=== Starting Repeated Micro-Liquidation Loop with 15% Monthly Price Drop ===");
        console2.log("Initial BTC Price (8 decimals):", currentBtcPrice);
        console2.log("");

        while (true) {
            vars.monthsLiquidated++;
            console2.log("--- Month", vars.monthsLiquidated, "---");

            // A. Warp time forward
            _warpPastGracePeriodSilent();

            // B. Apply Price Drop (15% drop per month)
            currentBtcPrice = (currentBtcPrice * 85) / 100; 
            
            // C. Mock the Oracle call
            vm.mockCall(
                oracleAddress,
                abi.encodeWithSelector(IPriceOracleGetter.getAssetPrice.selector, collateralAsset),
                abi.encode(currentBtcPrice)
            );
            
            // Update vars with the new mocked price for logging
            vars.btcPriceUSD = currentBtcPrice;
            console2.log(">> Price dropped to:", vars.btcPriceUSD);

            // D. Check type of liquidation
            vars.liquidationType = ILendingPool(s_bitmorPool).checkTypeOfLiquidation(vars.lsa);
            console2.log("Liquidation Type (0=None, 1=Full, 2=Micro):", vars.liquidationType);

            // E. Break Conditions
            if (vars.liquidationType == 1) {
                console2.log("");
                console2.log("=== Full Liquidation Triggered (Health Factor too low) ===");
                console2.log("Total months micro-liquidated:", vars.monthsLiquidated - 1);
                
                // Execute Full Liquidation
                console2.log("");
                console2.log("=== Executing Full Liquidation ===");
                
                // Get balances before full liquidation
                vars.liquidatorDebtBefore = IERC20(debtAsset).balanceOf(liquidator);
                vars.liquidatorCollateralBefore = IERC20(collateralAsset).balanceOf(liquidator);
                
                // Execute full liquidation with max debt coverage, receive underlying collateral (not aTokens)
                _executeFullLiquidation(vars.lsa, type(uint256).max, false);
                
                // Get balances after full liquidation
                vars.liquidatorDebtAfter = IERC20(debtAsset).balanceOf(liquidator);
                vars.liquidatorCollateralAfter = IERC20(collateralAsset).balanceOf(liquidator);
                
                // Calculate full liquidation results
                vars.fullLiqDebtPaid = vars.liquidatorDebtBefore - vars.liquidatorDebtAfter;
                vars.fullLiqCollateralReceived = vars.liquidatorCollateralAfter - vars.liquidatorCollateralBefore;
                vars.fullLiquidationExecuted = true;
                
                // Log full liquidation results
                console2.log("Full Liq - Debt Paid (USDC):", vars.fullLiqDebtPaid);
                console2.log("Full Liq - BTC Received:", vars.fullLiqCollateralReceived);
                
                // Calculate USD value of collateral received
                uint256 fullLiqBtcValueUSD = (vars.fullLiqCollateralReceived * vars.btcPriceUSD) / 1e8;
                console2.log("Full Liq - BTC Value Received (USD, 8 decimals):", fullLiqBtcValueUSD);
                
                // Check loan status after full liquidation
                DataTypes.LoanData memory loanDataAfterFullLiq = loan.getLoanByLSA(vars.lsa);
                console2.log("Loan Status After Full Liq (0=Active, 1=Completed, 2=Liquidated):", uint256(loanDataAfterFullLiq.status));
                console2.log("Remaining Collateral in LSA:", loanDataAfterFullLiq.collateralAmount);
                console2.log("Remaining Duration:", loanDataAfterFullLiq.duration);
                
                break;
            }

            if (vars.liquidationType == 0) {
                console2.log("");
                console2.log("=== Loan Completed via Micro-Liquidations ===");
                break;
            }

            // F. Execute Micro Liquidation
            vars.liquidatorDebtBefore = IERC20(debtAsset).balanceOf(liquidator);
            vars.liquidatorCollateralBefore = IERC20(collateralAsset).balanceOf(liquidator);

            _executeMicroLiquidation(vars.lsa);

            vars.liquidatorDebtAfter = IERC20(debtAsset).balanceOf(liquidator);
            vars.liquidatorCollateralAfter = IERC20(collateralAsset).balanceOf(liquidator);

            // G. Log Loop Details & FIX WARNING
            {
                uint256 debtPaidThisMonth = vars.liquidatorDebtBefore - vars.liquidatorDebtAfter;
                uint256 btcReceivedThisMonth = vars.liquidatorCollateralAfter - vars.liquidatorCollateralBefore;
                
                // Calculate Value
                uint256 btcValueUSD = (btcReceivedThisMonth * vars.btcPriceUSD) / 1e8;

                console2.log("Debt Paid (USDC):", debtPaidThisMonth);
                console2.log("BTC Received:", btcReceivedThisMonth);
                
                // FIX: Log the variable that was causing the warning
                console2.log("BTC Value Received (USD):", btcValueUSD);
            }

            // H. Update Loan Data for Next Iteration
            DataTypes.LoanData memory loanDataCurrent = loan.getLoanByLSA(vars.lsa);
            vars.currentDuration = loanDataCurrent.duration;
            vars.collateralInLSA = loanDataCurrent.collateralAmount;

            if (vars.currentDuration == 0 || loanDataCurrent.status != DataTypes.LoanStatus.Active) {
                console2.log("");
                console2.log("=== Loan Completed ===");
                break;
            }

            // Safety break
            if (vars.monthsLiquidated >= vars.initialDuration + 5) {
                console2.log("Safety limit reached");
                break;
            }
            console2.log("");
        }

        // 5. Final Calculations & Assertions
        vars.totalDebtPaid = liquidatorDebtStart - IERC20(debtAsset).balanceOf(liquidator);
        vars.totalCollateralReceived = IERC20(collateralAsset).balanceOf(liquidator) - liquidatorCollateralStart;

        console2.log("");
        console2.log("=== Final Results ===");
        console2.log("Final Liquidation Type:", vars.liquidationType);
        console2.log("Total Debt Paid (all liquidations):", vars.totalDebtPaid);
        console2.log("Total Collateral Received (all liquidations):", vars.totalCollateralReceived);
        
        if (vars.fullLiquidationExecuted) {
            console2.log("");
            console2.log("=== Full Liquidation Summary ===");
            console2.log("Full Liquidation Executed: YES");
            console2.log("Full Liq Debt Paid:", vars.fullLiqDebtPaid);
            console2.log("Full Liq Collateral Received:", vars.fullLiqCollateralReceived);
            
            // Calculate liquidator profit from full liquidation
            uint256 fullLiqBtcValueUSD = (vars.fullLiqCollateralReceived * vars.btcPriceUSD) / 1e8;
            uint256 fullLiqDebtIn8Decimals = vars.fullLiqDebtPaid * 1e2; // Convert 6 decimals to 8
            if (fullLiqBtcValueUSD > fullLiqDebtIn8Decimals) {
                uint256 fullLiqProfit = fullLiqBtcValueUSD - fullLiqDebtIn8Decimals;
                console2.log("Full Liq Profit (8 decimals):", fullLiqProfit);
            }
        }
        
        vm.clearMockedCalls();

        // If we successfully triggered full liquidation, this assertion passes
        bool isFullLiquidation = vars.liquidationType == 1;
        bool isCompleted = vars.currentDuration == 0;

        assertTrue(isFullLiquidation || isCompleted, "Test should end with full liquidation or completion");
        
        // If full liquidation was triggered, verify it was actually executed
        if (isFullLiquidation) {
            assertTrue(vars.fullLiquidationExecuted, "Full liquidation should have been executed");
            assertTrue(vars.fullLiqDebtPaid > 0, "Liquidator should have paid debt in full liquidation");
            assertTrue(vars.fullLiqCollateralReceived > 0, "Liquidator should have received collateral in full liquidation");
        }
    }    
    // ============ Internal Liquidation Helper Functions ============

    /// @dev Calculate the USD value of liquidated collateral using the protocol's oracle
    /// @param vars The test variables struct to populate with oracle data
    function _calculateCollateralUSDValue(MicroLiquidationTestVars memory vars) internal view {
        address addressesProvider = ILendingPool(s_bitmorPool).getAddressesProvider();
        address oracleAddress = ILendingPoolAddressesProvider(addressesProvider).getPriceOracle();

        IPriceOracleGetter oracle = IPriceOracleGetter(oracleAddress);

        vars.btcPriceUSD = oracle.getAssetPrice(collateralAsset);
        vars.usdcPriceUSD = oracle.getAssetPrice(debtAsset);

        uint256 collateralReceived = vars.liquidatorCollateralAfter - vars.liquidatorCollateralBefore;

        vars.collateralLiquidatedUSDValue = (collateralReceived * vars.btcPriceUSD) / 1e8;
    }

    /// @dev Log micro liquidation results
    function _logMicroLiquidationResults(MicroLiquidationTestVars memory vars) internal view {
        uint256 debtPaid = vars.liquidatorDebtBefore - vars.liquidatorDebtAfter;
        uint256 collateralReceived = vars.liquidatorCollateralAfter - vars.liquidatorCollateralBefore;

        console2.log("");
        console2.log("=== Micro Liquidation Results ===");
        console2.log("Debt paid by liquidator (USDC):", debtPaid);
        console2.log("Collateral received by liquidator (BTC):", collateralReceived);

        console2.log("");
        console2.log("=== Oracle Price Data ===");
        console2.log("Oracle BTC Price (8 decimals):", vars.btcPriceUSD);
        console2.log("Oracle USDC Price (8 decimals):", vars.usdcPriceUSD);

        console2.log("");
        console2.log("=== USD Value Calculation ===");
        console2.log("Collateral Liquidated USD Value (8 decimals):", vars.collateralLiquidatedUSDValue);

        uint256 usdValueIn6Decimals = vars.collateralLiquidatedUSDValue / 1e2;
        console2.log("Collateral Liquidated USD Value (6 decimals, USDC comparable):", usdValueIn6Decimals);

        if (usdValueIn6Decimals > debtPaid) {
            uint256 liquidatorProfit = usdValueIn6Decimals - debtPaid;
            console2.log("Liquidator Profit (USDC, 6 decimals):", liquidatorProfit);

            uint256 profitBps = (liquidatorProfit * 10000) / debtPaid;
            console2.log("Liquidator Profit (basis points):", profitBps);
        }

        console2.log("");
        console2.log("=== Loan State After Micro Liquidation ===");
        console2.log("Duration before:", vars.durationBefore);
        console2.log("Duration after:", vars.durationAfter);
        console2.log("Duration reduced by:", vars.durationBefore - vars.durationAfter);
        console2.log("Last payment timestamp before:", vars.lastPaymentBefore);
        console2.log("Last payment timestamp after:", vars.lastPaymentAfter);
        console2.log("Loan Status (0=Active, 1=Completed, 2=Liquidated):", vars.statusAfter);
        console2.log("");
        console2.log("=== Liquidator Balances After ===");
        console2.log("Liquidator Debt Asset (USDC):", vars.liquidatorDebtAfter);
        console2.log("Liquidator Collateral Asset (BTC):", vars.liquidatorCollateralAfter);
    }

    /// @dev Assert micro liquidation was successful
    function _assertMicroLiquidationSuccess(MicroLiquidationTestVars memory vars) internal pure {
        uint256 debtPaid = vars.liquidatorDebtBefore - vars.liquidatorDebtAfter;
        uint256 collateralReceived = vars.liquidatorCollateralAfter - vars.liquidatorCollateralBefore;

        /// 1. Liquidator paid debt
        assert(debtPaid > 0);

        /// 2. Liquidator received collateral (BTC) with bonus
        assert(collateralReceived > 0);

        /// 3. Loan duration should be reduced by 1
        assert(vars.durationAfter == vars.durationBefore - 1);

        /// 4. Last payment timestamp should be updated
        assert(vars.lastPaymentAfter > vars.lastPaymentBefore);

        /// 5. Loan should still be active (status = 0)
        assert(vars.statusAfter == 0);

        /// 6. Verify USD value was calculated (oracle returned valid prices)
        assert(vars.btcPriceUSD > 0);
        assert(vars.collateralLiquidatedUSDValue > 0);

        /// 7. Verify liquidator received a bonus (USD value of BTC > debt paid)
        uint256 debtPaidIn8Decimals = debtPaid * 1e2;
        assert(vars.collateralLiquidatedUSDValue > debtPaidIn8Decimals);
    }
}
