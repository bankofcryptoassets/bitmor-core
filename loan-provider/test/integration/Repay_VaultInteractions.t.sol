// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IntegrationTestBase} from "../base/IntegrationTestBase.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

/// @title Repay_VaultInteractionsTest
/// @notice Integration tests verifying how BTCVault/USDCVault state affects the repayment flow.
/// @dev Tests run against real deployed contracts on local Anvil via --fork-url.
///      A failing test is a security finding, not a test bug.
contract Repay_VaultInteractionsTest is IntegrationTestBase {
    // ============ Test-Specific Constants ============

    uint256 constant STRATEGY_LOSS_BPS = 1000; // 10%
    uint256 constant PAYMENTS_BEFORE_FINAL = 11; // For a 12-month loan, 11 partial + 1 final

    // ============ Test 1: Strategy Loss Reduces Collateral Return ============

    /// @notice Verifies that a BTCVault strategy loss reduces collateral returned on full repay
    function test_BTCVault_SharePriceDrop_DuringFullRepay_ReducesCollateralReturn() public {
        // Arrange: Create loan and make 11 monthly payments
        (address lsa,) = _createLoanAndMakePayments(PAYMENTS_BEFORE_FINAL);

        // Snapshot before final payment
        uint256 snap = vm.snapshot();

        // Reference: full repay without strategy loss
        _advanceDays(30);
        uint256 remainingDebt = _getDebtBalanceUSDC(lsa);
        _ensureSufficientUSDC(remainingDebt, 1);
        uint256 cbBTCBeforeRef = cbBTC.balanceOf(testUser);
        _repayLoan(lsa, testUser, remainingDebt);
        uint256 collateralReturnRef = cbBTC.balanceOf(testUser) - cbBTCBeforeRef;

        // Revert to pre-final-payment state
        vm.revertTo(snap);

        // Attack: simulate 10% strategy loss, then full repay
        _simulateStrategyLoss(STRATEGY_LOSS_BPS);
        _advanceDays(30);
        remainingDebt = _getDebtBalanceUSDC(lsa);
        _ensureSufficientUSDC(remainingDebt, 1);
        uint256 cbBTCBeforeAttack = cbBTC.balanceOf(testUser);
        _repayLoan(lsa, testUser, remainingDebt);
        uint256 collateralReturnAttack = cbBTC.balanceOf(testUser) - cbBTCBeforeAttack;

        // Assert
        assertLt(
            collateralReturnAttack, collateralReturnRef, "strategy loss must reduce collateral return"
        );
        assertGt(collateralReturnAttack, 0, "borrower must still receive some collateral");
        assertGt(
            collateralReturnAttack,
            collateralReturnRef * 1 / 100,
            "slippage floor must prevent near-total loss"
        );
    }

    // ============ Test 2: Exit Fee Reduces Collateral Return ============

    /// @notice Verifies that BTCVault exit fee reduces collateral returned on full repay
    function test_BTCVault_ExitFee_OnFullRepayCollateralReturn() public {
        // Arrange: Set fee recipient and exit fee via admin
        address feeCollector = makeAddr("feeCollector");
        vm.prank(admin);
        btcVault.setFeeRecipient(feeCollector);
        _setExitFee(TC.EXIT_FEE_LOW_BPS);

        // Create loan and make 11 monthly payments
        (address lsa,) = _createLoanAndMakePayments(PAYMENTS_BEFORE_FINAL);

        // Capture nominal collateral value before final repay
        uint256 aTokenBalance = _getATokenBalance(lsa);
        uint256 nominalValue = btcVault.convertToAssets(aTokenBalance);

        // Act: full repay
        _advanceDays(30);
        uint256 remainingDebt = _getDebtBalanceUSDC(lsa);
        _ensureSufficientUSDC(remainingDebt, 1);
        uint256 cbBTCBefore = cbBTC.balanceOf(testUser);
        _repayLoan(lsa, testUser, remainingDebt);
        uint256 actualReturn = cbBTC.balanceOf(testUser) - cbBTCBefore;

        // Assert: exit fee must reduce collateral return
        assertLt(actualReturn, nominalValue, "exit fee must reduce collateral return");
        assertGt(actualReturn, 0, "borrower must receive collateral minus exit fee");

        // Verify fee approximation: fee = nominalValue * TC.EXIT_FEE_LOW_BPS / (TC.EXIT_FEE_LOW_BPS + 10_000)
        uint256 expectedFee = nominalValue * TC.EXIT_FEE_LOW_BPS / (TC.EXIT_FEE_LOW_BPS + TC.BPS_DENOMINATOR);
        uint256 actualFee = nominalValue - actualReturn;
        assertApproxEqAbs(
            actualFee,
            expectedFee,
            expectedFee / 10 + 1, // 10% tolerance on fee amount + 1 for rounding
            "exit fee amount should approximate expected value"
        );
    }

    // ============ Test 3: Paused BTCVault Blocks Full Repay ============

    /// @notice Verifies that a paused BTCVault prevents collateral return during full repay
    function test_BTCVault_StrategyWithdrawalFailure_DuringFullRepay() public {
        // Arrange: Create loan and make 11 monthly payments
        (address lsa,) = _createLoanAndMakePayments(PAYMENTS_BEFORE_FINAL);

        // Pause BTCVault (admin has ADMIN role 0, pause defaults to ADMIN since BVM_FAST selectors not mapped)
        vm.prank(admin);
        btcVault.pause();

        // Capture USDC balance before attempted repay
        _advanceDays(30);
        uint256 usdcBefore = usdc.balanceOf(testUser);
        uint256 remainingDebt = _getDebtBalanceUSDC(lsa);
        _ensureSufficientUSDC(remainingDebt, 1);

        // Act: attempt full repay — should revert because collateral withdrawal from paused vault fails
        vm.expectRevert();
        _repayLoan(lsa, testUser, remainingDebt);

        // Assert: USDC must not be consumed if collateral cannot be returned
        assertEq(
            usdc.balanceOf(testUser),
            usdcBefore,
            "USDC must not be consumed if collateral can't be returned"
        );

        // Cleanup: unpause via admin (defaults to ADMIN role 0)
        vm.prank(admin);
        btcVault.unpause();
    }

    // ============ Test 4: Partial Repay Does Not Touch Collateral ============

    /// @notice Verifies that a partial (monthly) repayment does not affect collateral position
    function test_PartialRepay_DoesNotTouchCollateral() public {
        // Arrange
        (address lsa, DataTypes.LoanData memory loanData) = _createStandardLoanWithData();
        uint256 collateralBefore = _getATokenBalance(lsa);
        uint256 debtBefore = _getDebtBalanceUSDC(lsa);

        // Act: make 1 monthly payment
        _advanceDays(30);
        _repayLoan(lsa, testUser, loanData.estimatedMonthlyPayment);

        // Assert
        uint256 collateralAfter = _getATokenBalance(lsa);
        assertEq(collateralAfter, collateralBefore, "partial repayment must not touch collateral");

        uint256 debtAfter = _getDebtBalanceUSDC(lsa);
        assertLt(debtAfter, debtBefore, "debt must decrease after partial repay");
    }

    // ============ Test 5: Vault Yield Benefits Borrower on Full Repay ============

    /// @notice Verifies that BTCVault share price appreciation benefits the borrower on full repay
    function test_BTCVault_SharePriceAppreciation_BenefitsBorrowerOnFullRepay() public {
        // Arrange
        (address lsa, DataTypes.LoanData memory loanData) = _createStandardLoanWithData();
        uint256 monthlyPayment = loanData.estimatedMonthlyPayment;
        uint256 originalCollateral = loanData.collateralAmount;
        _ensureSufficientUSDC(monthlyPayment, TC.STANDARD_DURATION);

        // Make 11 monthly payments
        _makeMonthlyPayments(lsa, monthlyPayment, PAYMENTS_BEFORE_FINAL);

        // Simulate 5% vault yield
        _simulateVaultYield(TC.SIMULATED_YIELD_BPS);

        // Act: full repay
        uint256 remainingDebt = _getDebtBalanceUSDC(lsa);
        _ensureSufficientUSDC(remainingDebt, 1);
        _advanceDays(30);
        _repayLoan(lsa, testUser, remainingDebt);
        uint256 actualReturn = cbBTC.balanceOf(testUser);

        // Assert: borrower should benefit from vault yield
        assertGt(
            actualReturn,
            originalCollateral,
            "borrower must benefit from vault yield on full repay"
        );
    }

    // ============ Test 6: BTCVault Donation Has No Effect ============

    /// @notice Verifies that a raw cbBTC donation to BTCVault does not affect totalAssets or repayments
    /// @dev BTCVault.totalAssets() only sums strategy balances, not vault's own token balance.
    ///      If this test fails, it means the vault is susceptible to donation attacks.
    function test_BTCVault_DonationBetweenRepayments_NoEffect() public {
        // Arrange: create loan and make 1 monthly payment
        (address lsa, DataTypes.LoanData memory loanData) = _createStandardLoanWithData();
        uint256 monthlyPayment = loanData.estimatedMonthlyPayment;
        _ensureSufficientUSDC(monthlyPayment, TC.STANDARD_DURATION);

        _advanceDays(30);
        _repayLoan(lsa, testUser, monthlyPayment);

        uint256 totalAssetsBefore = btcVault.totalAssets();
        DataTypes.LoanData memory afterFirstPayment = loanContract.getLoanByLSA(lsa);
        uint256 durationAfterFirstPayment = afterFirstPayment.duration;

        // Act: attacker donates cbBTC directly to BTCVault
        address attacker = makeAddr("attacker");
        _fundCbBTC(attacker, TC.DONATION_AMOUNT_CBBTC);
        vm.prank(attacker);
        cbBTC.transfer(address(btcVault), TC.DONATION_AMOUNT_CBBTC);

        // Assert: totalAssets must not change from raw donation
        assertEq(
            btcVault.totalAssets(),
            totalAssetsBefore,
            "raw donation must not change totalAssets"
        );

        // Act: make another payment after donation
        _advanceDays(30);
        _repayLoan(lsa, testUser, monthlyPayment);

        // Assert: repayment must be unaffected by donation
        DataTypes.LoanData memory afterSecondPayment = loanContract.getLoanByLSA(lsa);
        assertEq(
            afterSecondPayment.duration,
            durationAfterFirstPayment - 1,
            "repayment must be unaffected by donation"
        );
    }

    // ============ Test 7: USDCVault Liquidity Drain Does Not Block Repay ============

    /// @notice Verifies that draining USDCVault does not prevent repayment processing
    /// @dev Repayments go to BLP directly (not via USDCVault), so vault liquidity is irrelevant
    function test_USDCVault_LiquidityDrain_DoesNotBlockRepayment() public {
        // Arrange: create loan
        (address lsa, DataTypes.LoanData memory loanData) = _createStandardLoanWithData();
        _ensureSufficientUSDC(loanData.estimatedMonthlyPayment, TC.STANDARD_DURATION);

        // Drain USDCVault by having the seeder redeem max redeemable shares
        address seeder = makeAddr("blpSeeder");
        uint256 redeemable = usdcVault.maxRedeem(seeder);
        if (redeemable > 0) {
            vm.prank(seeder);
            usdcVault.redeem(redeemable, seeder, seeder);
        }

        // Capture debt before repay
        uint256 debtBefore = _getDebtBalanceUSDC(lsa);

        // Act: attempt monthly payment after vault is drained
        _advanceDays(30);
        _repayLoan(lsa, testUser, loanData.estimatedMonthlyPayment);

        // Assert: repay must still work since it repays to BLP, not vault directly
        assertLt(
            _getDebtBalanceUSDC(lsa),
            debtBefore,
            "repay must still work since it repays to BLP, not vault directly"
        );
    }

    // ============ Test 8: Repay Increases BLP Available Liquidity ============

    /// @notice Verifies that a monthly repayment increases BLP's available USDC liquidity
    /// @dev BLP routes repaid USDC to the aToken contract, not itself. LendingPool.sol:280 does
    ///      IERC20(asset).safeTransferFrom(msg.sender, aToken, paybackAmount).
    function test_Repay_IncreasesUSDCVault_AvailableLiquidity() public {
        // Arrange
        (address lsa, DataTypes.LoanData memory loanData) = _createStandardLoanWithData();

        // Capture BLP available USDC liquidity before repayment
        uint256 liquidityBefore = _getBLPAvailableLiquidity(address(usdc));

        // Act: make 1 monthly payment
        _advanceDays(30);
        _repayLoan(lsa, testUser, loanData.estimatedMonthlyPayment);

        // Assert
        uint256 liquidityAfter = _getBLPAvailableLiquidity(address(usdc));
        assertGt(
            liquidityAfter,
            liquidityBefore,
            "repayment must increase BLP available liquidity"
        );
        assertApproxEqAbs(
            liquidityAfter - liquidityBefore,
            loanData.estimatedMonthlyPayment,
            TC.MAX_ROUNDING_LOSS_USDC,
            "liquidity increase must approximate repayment amount"
        );
    }

    // ============ Test 9: USDC Donation Inflates Vault Share Price ============

    /// @notice Verifies that a raw USDC donation to USDCVault inflates share price but does not affect EMI
    /// @dev USDCVault.totalAssets() includes balanceOf(address(this)), so donations are counted.
    ///      If the share price assertion fails, the vault has donation protection (which is good).
    function test_USDCVault_DonationBetweenRepayments_InflatesLPShares() public {
        // Arrange: create loan and make 1 monthly payment
        (address lsa, DataTypes.LoanData memory loanData) = _createStandardLoanWithData();
        uint256 monthlyPayment = loanData.estimatedMonthlyPayment;
        _ensureSufficientUSDC(monthlyPayment, TC.STANDARD_DURATION);

        _advanceDays(30);
        _repayLoan(lsa, testUser, monthlyPayment);

        // Capture share price before donation
        uint256 sharePriceBefore = usdcVault.convertToAssets(1e6);

        // Act: attacker donates USDC directly to USDCVault
        address attacker2 = makeAddr("usdcAttacker");
        _fundUSDC(attacker2, TC.DONATION_AMOUNT_USDC);
        vm.prank(attacker2);
        usdc.transfer(address(usdcVault), TC.DONATION_AMOUNT_USDC);

        // Assert: donation inflates vault share price
        uint256 sharePriceAfter = usdcVault.convertToAssets(1e6);
        assertGt(
            sharePriceAfter,
            sharePriceBefore,
            "USDC donation must inflate vault share price"
        );

        // Capture EMI before second payment
        uint256 emiBefore = loanData.estimatedMonthlyPayment;

        // Make another payment after donation
        _advanceDays(30);
        _repayLoan(lsa, testUser, monthlyPayment);

        // Assert: EMI stored in loan must not change due to vault donation
        DataTypes.LoanData memory updatedData = loanContract.getLoanByLSA(lsa);
        assertEq(
            updatedData.estimatedMonthlyPayment,
            emiBefore,
            "EMI must not change due to vault donation"
        );
    }

    // ============ Test 10: Mass Repayment Same Block ============

    /// @notice Verifies that multiple users repaying in the same block all succeed
    function test_MassRepayment_SameBlock_LiquiditySurge() public {
        // Arrange: create loans for 3 users
        address user2 = _setupAdditionalUser("massRepayUser2");
        address user3 = _setupAdditionalUser("massRepayUser3");

        // Create loans with 1-second gaps for unique CREATE2 salts
        address lsa1 = _createStandardLoan();

        vm.warp(block.timestamp + 1);
        address lsa2 = _createLoanForUser(user2, TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        vm.warp(block.timestamp + 1);
        address lsa3 = _createLoanForUser(user3, TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        // Get loan data for monthly payments
        DataTypes.LoanData memory loanData1 = loanContract.getLoanByLSA(lsa1);
        DataTypes.LoanData memory loanData2 = loanContract.getLoanByLSA(lsa2);
        DataTypes.LoanData memory loanData3 = loanContract.getLoanByLSA(lsa3);

        // Ensure all users have sufficient USDC
        _ensureSufficientUSDC(loanData1.estimatedMonthlyPayment, 1);
        uint256 user2Balance = usdc.balanceOf(user2);
        if (user2Balance < loanData2.estimatedMonthlyPayment) {
            _fundUSDC(user2, loanData2.estimatedMonthlyPayment - user2Balance);
        }
        uint256 user3Balance = usdc.balanceOf(user3);
        if (user3Balance < loanData3.estimatedMonthlyPayment) {
            _fundUSDC(user3, loanData3.estimatedMonthlyPayment - user3Balance);
        }

        // Record debt before
        uint256 debt1Before = _getDebtBalanceUSDC(lsa1);
        uint256 debt2Before = _getDebtBalanceUSDC(lsa2);
        uint256 debt3Before = _getDebtBalanceUSDC(lsa3);

        // Advance to next payment window
        _advanceDays(30);

        // Act: all 3 repay in the same block (no time advancement between them)
        _repayLoan(lsa1, testUser, loanData1.estimatedMonthlyPayment);
        _repayLoan(lsa2, user2, loanData2.estimatedMonthlyPayment);
        _repayLoan(lsa3, user3, loanData3.estimatedMonthlyPayment);

        // Assert: all 3 debts decreased
        assertLt(_getDebtBalanceUSDC(lsa1), debt1Before, "user1 debt must decrease after repay");
        assertLt(_getDebtBalanceUSDC(lsa2), debt2Before, "user2 debt must decrease after repay");
        assertLt(_getDebtBalanceUSDC(lsa3), debt3Before, "user3 debt must decrease after repay");

        // Assert: all 3 loans have duration decremented
        DataTypes.LoanData memory updated1 = loanContract.getLoanByLSA(lsa1);
        DataTypes.LoanData memory updated2 = loanContract.getLoanByLSA(lsa2);
        DataTypes.LoanData memory updated3 = loanContract.getLoanByLSA(lsa3);

        assertEq(
            updated1.duration,
            TC.STANDARD_DURATION - 1,
            "user1 duration must decrease by 1"
        );
        assertEq(
            updated2.duration,
            TC.STANDARD_DURATION - 1,
            "user2 duration must decrease by 1"
        );
        assertEq(
            updated3.duration,
            TC.STANDARD_DURATION - 1,
            "user3 duration must decrease by 1"
        );
    }
}
