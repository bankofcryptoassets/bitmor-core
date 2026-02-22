// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IntegrationTestBase} from "../base/IntegrationTestBase.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

/// @title GlobalConservationTest
/// @notice Integration tests for global token conservation and accounting invariants
/// @dev Phase 4 of integration test plan: Cat 18.5, 18.6, 18.7, 18.9
contract GlobalConservationTest is IntegrationTestBase {
    // ============ Constants ============

    uint256 internal constant CLOSE_BUFFER_MULTIPLIER = 2; // 2x loanAmount ensures sufficient USDC for close

    // ============ State for conservation tracking ============

    address internal feeCollector;

    function setUp() public override {
        super.setUp();
        feeCollector = loanContract.getPremiumCollector();
    }

    // ============ Conservation Helpers ============

    /// @notice Sums cbBTC across all key addresses where it can reside
    /// @dev Global BTC conservation: this sum must be constant after setUp (no minting allowed).
    ///      Includes both btcVault.totalAssets() (strategy-held) AND cbBTC.balanceOf(address(btcVault))
    ///      (un-deployed vault balance) to catch bugs where cbBTC gets stuck in the vault's raw balance
    ///      (e.g., similar to the USDCStrategy.withdraw bug where assets weren't forwarded to the vault).
    /// @param users Array of user addresses to include in the sum
    function _totalCbBTC(address[] memory users) internal view returns (uint256 total) {
        total += btcVault.totalAssets();                  // strategy-held cbBTC
        total += cbBTC.balanceOf(address(btcVault));      // un-deployed vault balance (transit/dust)
        total += cbBTC.balanceOf(swapper);
        total += cbBTC.balanceOf(address(loanContract));
        total += cbBTC.balanceOf(feeCollector);
        for (uint256 i = 0; i < users.length; i++) {
            total += cbBTC.balanceOf(users[i]);
        }
    }

    // ============ Tests ============

    /// @notice 18.5: Global BTC conservation — sum of cbBTC across all addresses is constant
    function test_GlobalBTCConservation_AcrossLoanLifecycle() public {
        address[] memory users = new address[](1);
        users[0] = testUser;

        uint256 totalBtcBefore = _totalCbBTC(users);
        assertGt(totalBtcBefore, 0, "system must have cbBTC after setUp");

        // --- State transition 1: Initialize loan ---
        (address lsa, DataTypes.LoanData memory loanData) = _createStandardLoanWithData();

        uint256 totalBtcAfterInit = _totalCbBTC(users);
        assertApproxEqAbs(totalBtcAfterInit, totalBtcBefore, TC.DUST_TOLERANCE_BTC, "BTC conservation violated after loan init");
        assertGt(_getATokenBalance(lsa), 0, "LSA must hold aTokens after init");
        _assertLoanContractIsEmpty("after init");

        // --- State transition 2: Monthly repayments (3 months) ---
        _makeMonthlyPayments(lsa, loanData.estimatedMonthlyPayment, 3);

        uint256 totalBtcAfterRepay = _totalCbBTC(users);
        assertApproxEqAbs(totalBtcAfterRepay, totalBtcBefore, TC.DUST_TOLERANCE_BTC, "BTC conservation violated after partial repayments");
        assertGt(_getATokenBalance(lsa), 0, "collateral must persist during partial repayment");

        // --- State transition 3: Close loan (withdrawInBTC = true) ---
        _closeLoanEarly(lsa, testUser, true);

        uint256 totalBtcAfterClose = _totalCbBTC(users);
        assertApproxEqAbs(totalBtcAfterClose, totalBtcBefore, TC.DUST_TOLERANCE_BTC, "BTC conservation violated after close");
        assertEq(_getATokenBalance(lsa), 0, "LSA must hold zero aTokens after close");
        _assertLoanContractIsEmpty("after close");
        assertGt(cbBTC.balanceOf(testUser), 0, "user must receive BTC back after close");
    }

    /// @notice 18.6: Global USDC conservation across full loan lifecycle
    /// @dev Interest accrual creates new USDC-value; tolerance 1% per transition
    function test_GlobalUSDCConservation_AcrossLoanLifecycle() public {
        uint256 blpUsdcBefore = _getBLPAvailableLiquidity(address(usdc));
        uint256 userUsdcBefore = usdc.balanceOf(testUser);

        // --- State transition 1: Initialize loan ---
        (address lsa, DataTypes.LoanData memory loanData) = _createStandardLoanWithData();

        uint256 blpUsdcAfterInit = _getBLPAvailableLiquidity(address(usdc));
        uint256 lsaDebtAfterInit = _getDebtBalanceUSDC(lsa);
        uint256 userUsdcAfterInit = usdc.balanceOf(testUser);

        assertLt(blpUsdcAfterInit, blpUsdcBefore, "BLP USDC must decrease after loan init (borrowed)");
        assertGt(lsaDebtAfterInit, 0, "LSA must have debt after init");
        assertGt(userUsdcBefore - userUsdcAfterInit, 0, "user must spend USDC on deposit");

        uint256 blpUsdcDecrease = blpUsdcBefore - blpUsdcAfterInit;
        assertApproxEqRel(blpUsdcDecrease, lsaDebtAfterInit, 0.01e18, "BLP liquidity decrease must approximately equal LSA debt (within 1%)");
        _assertLoanContractIsEmpty("after init");

        // --- State transition 2: Monthly repayments (3 months) ---
        _makeMonthlyPayments(lsa, loanData.estimatedMonthlyPayment, 3);

        uint256 blpUsdcAfterRepay = _getBLPAvailableLiquidity(address(usdc));
        uint256 lsaDebtAfterRepay = _getDebtBalanceUSDC(lsa);

        assertLt(lsaDebtAfterRepay, lsaDebtAfterInit, "debt must decrease after repayments");
        assertGt(blpUsdcAfterRepay, blpUsdcAfterInit, "BLP liquidity must increase after repayments");
        _assertLoanContractIsEmpty("after USDC repayments");

        // --- State transition 3: Close loan ---
        _closeLoanEarly(lsa, testUser, false);

        uint256 blpUsdcAfterClose = _getBLPAvailableLiquidity(address(usdc));
        uint256 lsaDebtAfterClose = _getDebtBalanceUSDC(lsa);

        assertEq(lsaDebtAfterClose, 0, "LSA debt must be zero after close");
        assertGt(blpUsdcAfterClose, blpUsdcAfterRepay, "BLP liquidity must increase after close");
        assertGe(blpUsdcAfterClose, blpUsdcBefore, "BLP USDC must not decrease over full lifecycle (interest must cover costs)");
        assertApproxEqRel(blpUsdcAfterClose, blpUsdcBefore, 0.01e18, "BLP USDC approximately restored after full lifecycle (within 1%)");
        _assertLoanContractIsEmpty("after USDC close");
    }

    /// @notice 18.7: Multi-loan lifecycle — close one, liquidate one, complete one
    function test_NoValueLeakage_MultiLoan_FullLifecycle() public {
        address borrower2 = _setupAdditionalUser("borrower2");

        (, int256 initialBtcPrice,,,) = btcOracle.latestRoundData();

        address[] memory users = new address[](2);
        users[0] = testUser;
        users[1] = borrower2;
        uint256 totalBtcBaseline = _totalCbBTC(users);

        // --- Create 3 loans ---
        (address lsa1,) = _createStandardLoanWithData();
        vm.warp(block.timestamp + 1);
        (address lsa2,) = _createStandardLoanWithData();
        vm.warp(block.timestamp + 1);
        address lsa3 = _createLoanForUser(borrower2, TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        _assertLoanContractIsEmpty("after 3 loan inits");
        assertApproxEqAbs(_totalCbBTC(users), totalBtcBaseline, TC.DUST_TOLERANCE_BTC, "BTC conservation violated after 3 loan inits");

        // --- Partial repayments on all 3 loans (1 month each) ---
        {
            _advanceDays(30);
            uint256 payment1 = loanContract.getLoanByLSA(lsa1).estimatedMonthlyPayment;
            uint256 payment2 = loanContract.getLoanByLSA(lsa2).estimatedMonthlyPayment;
            uint256 payment3 = loanContract.getLoanByLSA(lsa3).estimatedMonthlyPayment;
            _repayLoan(lsa1, testUser, payment1);
            _repayLoan(lsa2, testUser, payment2);
            _repayLoan(lsa3, borrower2, payment3);
        }

        _assertLoanContractIsEmpty("after multi-loan repayments");

        // --- Path A: Close loan 1 early ---
        _closeLoanEarly(lsa1, testUser, false);

        assertEq(uint256(loanContract.getLoanByLSA(lsa1).status), uint256(DataTypes.LoanStatus.Completed), "loan 1 must be Completed");
        _assertLoanContractIsEmpty("after loan 1 close");

        // --- Path B: Liquidate loan 3 ---
        {
            _makeFirstPaymentOverdue();
            _dropOraclePrice(TC.PRICE_DROP_FULL);
            _setupLiquidator();

            uint256 liquidationType = _checkTypeOfLiquidation(lsa3);
            assertGt(liquidationType, 0, "loan 3 must be liquidatable after price drop + overdue");

            bool ok = _triggerFullLiquidation(lsa3);
            assertTrue(ok, "full liquidation must succeed");
        }

        assertEq(uint256(loanContract.getLoanByLSA(lsa3).status), uint256(DataTypes.LoanStatus.Liquidated), "loan 3 must be Liquidated");
        _assertLoanContractIsEmpty("after loan 3 liquidation");

        // --- Path C: Complete loan 2 normally ---
        _setBtcPrice(initialBtcPrice);

        {
            DataTypes.LoanData memory loan2Data = loanContract.getLoanByLSA(lsa2);
            uint256 remainingDuration = loan2Data.duration;
            uint256 monthlyPayment = loan2Data.estimatedMonthlyPayment;
            _ensureSufficientUSDC(monthlyPayment, remainingDuration);
            for (uint256 i = 0; i < remainingDuration; i++) {
                _advanceDays(30);
                _repayLoan(lsa2, testUser, monthlyPayment);
            }
        }

        assertEq(uint256(loanContract.getLoanByLSA(lsa2).status), uint256(DataTypes.LoanStatus.Completed), "loan 2 must be Completed");

        // --- Final conservation checks ---
        _assertLoanContractIsEmpty("at end of multi-loan lifecycle");
        assertEq(_getDebtBalanceUSDC(lsa1), 0, "LSA1 debt must be zero");
        assertEq(_getDebtBalanceUSDC(lsa2), 0, "LSA2 debt must be zero");

        // Global BTC conservation (add liquidator who received cbBTC)
        address[] memory allUsers = new address[](3);
        allUsers[0] = testUser;
        allUsers[1] = borrower2;
        allUsers[2] = testLiquidator;
        assertApproxEqAbs(_totalCbBTC(allUsers), totalBtcBaseline, TC.DUST_TOLERANCE_BTC, "BTC conservation violated after multi-loan lifecycle");
    }

    /// @notice 18.9: Aggregate scaled debt consistency across multiple loans
    function test_AggregateScaledDebt_ConsistencyAcrossLoans() public {
        address borrower2 = _setupAdditionalUser("borrower2_debt");

        uint256 baselineScaledDebt = _getTotalScaledDebtSupply();

        // --- Create loan 1 ---
        address lsa1 = _createStandardLoan();
        uint256 scaledDebt1 = _getScaledDebtBalance(lsa1);
        uint256 totalScaled = _getTotalScaledDebtSupply();
        assertEq(totalScaled, baselineScaledDebt + scaledDebt1, "total scaled == baseline + loan1 after first loan");

        // --- Create loan 2 (different borrower) ---
        vm.warp(block.timestamp + 1);
        address lsa2 = _createLoanForUser(borrower2, TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);
        uint256 scaledDebt2 = _getScaledDebtBalance(lsa2);
        totalScaled = _getTotalScaledDebtSupply();
        assertEq(totalScaled, baselineScaledDebt + scaledDebt1 + scaledDebt2, "total scaled == baseline + loan1 + loan2 after second loan");

        // --- Create loan 3 ---
        vm.warp(block.timestamp + 1);
        address lsa3 = _createStandardLoan();
        uint256 scaledDebt3 = _getScaledDebtBalance(lsa3);
        totalScaled = _getTotalScaledDebtSupply();
        assertEq(totalScaled, baselineScaledDebt + scaledDebt1 + scaledDebt2 + scaledDebt3, "total scaled == baseline + sum(loan_i) after third loan");

        // --- Advance time: scaled balances must NOT change ---
        _advanceDays(30);
        assertEq(_getScaledDebtBalance(lsa1), scaledDebt1, "loan1 scaled debt unchanged after time");
        assertEq(_getScaledDebtBalance(lsa2), scaledDebt2, "loan2 scaled debt unchanged after time");
        assertEq(_getScaledDebtBalance(lsa3), scaledDebt3, "loan3 scaled debt unchanged after time");
        totalScaled = _getTotalScaledDebtSupply();
        assertEq(totalScaled, baselineScaledDebt + scaledDebt1 + scaledDebt2 + scaledDebt3, "total scaled unchanged after time advance");

        // --- Partial repay on loan 1: scaled debt should decrease ---
        DataTypes.LoanData memory loan1Data = loanContract.getLoanByLSA(lsa1);
        _repayLoan(lsa1, testUser, loan1Data.estimatedMonthlyPayment);

        uint256 scaledDebt1AfterRepay = _getScaledDebtBalance(lsa1);
        assertLt(scaledDebt1AfterRepay, scaledDebt1, "loan1 scaled debt must decrease after repay");

        totalScaled = _getTotalScaledDebtSupply();
        assertEq(totalScaled, baselineScaledDebt + scaledDebt1AfterRepay + scaledDebt2 + scaledDebt3, "total scaled == baseline + sum after partial repay");

        // --- Close loan 1: scaled debt should reach zero ---
        _closeLoanEarly(lsa1, testUser, false);

        assertEq(_getScaledDebtBalance(lsa1), 0, "loan1 scaled debt must be zero after close");

        uint256 currentScaledDebt2 = _getScaledDebtBalance(lsa2);
        uint256 currentScaledDebt3 = _getScaledDebtBalance(lsa3);
        totalScaled = _getTotalScaledDebtSupply();
        assertEq(totalScaled, baselineScaledDebt + currentScaledDebt2 + currentScaledDebt3, "total scaled == baseline + remaining loans after loan1 closed");
    }
}
