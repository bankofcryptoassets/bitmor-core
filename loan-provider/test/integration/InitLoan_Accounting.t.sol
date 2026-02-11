// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IntegrationTestBase} from "../base/IntegrationTestBase.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

/// @title InitLoan_AccountingTest
/// @author Bitmor Protocol
/// @notice Adversarial integration tests for accounting edge cases during loan initialization
/// @dev Failing tests = security findings, NOT test bugs. Do NOT weaken assertions.
contract InitLoan_AccountingTest is IntegrationTestBase {
    // ============ Constants ============

    uint256 constant SHARE_PRICE_IMPACT_TOLERANCE = 0.01e18; // 1%

    // ============ Setup ============

    function setUp() public override {
        super.setUp();
        _setupTestUser();
    }

    // ============ Test 19: bvBTC Price Used For Loan Calc But cbBTC Swapped ============

    /// @notice When 1 bvBTC > 1 cbBTC (yield accrued), the protocol must still create a
    ///         healthy loan. If the loan is born undercollateralized, the share-price-to-swap
    ///         amount conversion is miscalculated.
    /// @dev Injects yield by donating cbBTC to the Aave strategy (supply on behalf),
    ///      making each bvBTC share worth more than 1 cbBTC.
    function test_Accounting_bvBTCPriceUsedForLoanCalc_ButCbBTCSwapped() public {
        // Arrange - inject yield so 1 bvBTC > 1 cbBTC
        address strategyAddr = config.getAaveTokenizedStrategy();
        address donator = makeAddr("yieldDonator");
        _fundCbBTC(donator, TC.USER_CBBTC_BALANCE);

        vm.prank(donator);
        cbBTC.approve(aaveV3Pool, TC.USER_CBBTC_BALANCE);

        vm.prank(donator);
        (bool ok,) = aaveV3Pool.call(
            abi.encodeWithSignature(
                "supply(address,uint256,address,uint16)", address(cbBTC), TC.USER_CBBTC_BALANCE, strategyAddr, 0
            )
        );
        require(ok, "supply failed");

        // Act - create loan after share price has shifted above 1:1
        address lsa = _createLoan(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        // Assert - loan must be healthy at birth
        (,, uint256 healthFactor) = _getUserAccountData(lsa);
        assertGe(healthFactor, TC.PRECISION, "loan must not be born undercollateralized when share price > 1:1");
    }

    // ============ Test 20: Flash Loan Premium Creates Hidden Debt ============

    /// @notice The flash loan from Aave V3 charges a premium on top of the borrowed amount.
    ///         This premium becomes part of the BLP debt but may not be reflected in the stored
    ///         loanAmount. If EMI schedule only covers stored loanAmount, the flash loan premium
    ///         creates a hidden debt gap that the borrower can never fully repay via EMIs.
    function test_Accounting_FlashLoanPremiumCreatesHiddenDebt() public {
        // Arrange + Act - create loan and capture all accounting data
        (address lsa, DataTypes.LoanData memory loanData) =
            _createLoanWithData(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        // Assert - actual BLP debt must exist after loan initialization
        (, uint256 totalDebtETH,) = _getUserAccountData(lsa);
        assertGt(totalDebtETH, 0, "actual BLP debt must exist after loan init");

        // Assert - EMI schedule must cover at least the stored loan amount
        uint256 totalRepayment = loanData.duration * loanData.estimatedMonthlyPayment;
        assertGe(totalRepayment, loanData.loanAmount, "EMI schedule must cover at least stored loan amount");

        // Assert - EMI schedule must cover the FULL actual debt including flash loan premium
        // totalDebtETH is in oracle units (8 decimals), usdcPrice is the oracle price for USDC
        // Convert debt from oracle units to USDC terms for comparison
        uint256 usdcPrice = _getOraclePrice(address(usdc));
        uint256 debtInUSDC = (totalDebtETH * 1e6) / usdcPrice;

        // FINDING if totalRepayment < actual debt: EMI schedule does not cover flash loan premium
        assertGe(totalRepayment, debtInUSDC, "EMI schedule must cover full debt including flash loan premium");
    }

    // ============ Test 21: Multi-Loan Same Block - Share Price Shift ============

    /// @notice When two users create identical loans in the same block, the first loan's deposit
    ///         into BTCVault changes the share price. If the second loan gets significantly fewer
    ///         shares for the same collateral amount, it creates an unfair advantage for early
    ///         depositors and the second loan may be born less healthy.
    function test_Accounting_MultiLoanSameBlock_SharePriceShift() public {
        // Arrange - setup second user
        address user2 = _setupSecondUser();

        // Act - User A creates loan
        address lsaA = _createLoan(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        // Act - User B creates identical loan in the same block
        address lsaB =
            _createLoanForUser(user2, TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        // Assert - User B's loan must still be healthy
        (,, uint256 healthFactorB) = _getUserAccountData(lsaB);
        assertGe(healthFactorB, TC.PRECISION, "second same-block loan must not be born undercollateralized");

        // Assert - both users must receive similar share amounts for identical collateral
        uint256 sharesA = btcVault.balanceOf(lsaA);
        uint256 sharesB = btcVault.balanceOf(lsaB);
        assertApproxEqRel(
            sharesA,
            sharesB,
            SHARE_PRICE_IMPACT_TOLERANCE,
            "same-block loans must get similar share amounts"
        );
    }
}
