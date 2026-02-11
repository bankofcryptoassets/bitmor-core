// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IntegrationTestBase} from "../base/IntegrationTestBase.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

/// @title InitLoan_IRMTest
/// @author Bitmor Protocol
/// @notice Adversarial integration tests for interest rate model manipulation during loan initialization
/// @dev Failing tests = security findings, NOT test bugs. Do NOT weaken assertions.
contract InitLoan_IRMTest is IntegrationTestBase {
    // ============ Constants ============

    /// @dev Number of additional loans to create for utilization spiking
    uint256 constant UTILIZATION_SPIKE_LOANS = 3;

    // ============ Setup ============

    function setUp() public override {
        super.setUp();
        _setupTestUser();
    }

    // ============ Test 22: EMI Must Not Be Manipulable Via Utilization ============

    /// @notice Attacker spikes pool utilization to inflate a victim's EMI.
    /// @dev Attack scenario:
    ///      1. Attacker creates many loans to consume BLP USDC liquidity
    ///      2. High utilization drives up the variable borrow rate in the IRM
    ///      3. Victim's loan is created with inflated EMI due to higher rate
    ///      If EMI changes with utilization, an attacker can grief borrowers by
    ///      front-running their loan initialization with high-utilization transactions.
    ///      FINDING if assertEq fails: EMI is utilization-dependent, enabling EMI griefing.
    function test_IRM_MaxRateIsConstant_NotManipulableByUtilization() public {
        // Arrange -- baseline loan at current utilization
        (address lsaA, DataTypes.LoanData memory loanDataA) =
            _createLoanWithData(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);
        uint256 baselineEMI = loanDataA.estimatedMonthlyPayment;

        // Spike utilization: create multiple loans from different users to consume BLP USDC
        address user2 = _setupSecondUser();
        vm.warp(block.timestamp + 1);
        _createLoanForUser(user2, TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        address user3 = makeAddr("integrationTestUser3");
        _setupUserWithoutBLP(user3);
        vm.warp(block.timestamp + 1);
        _createLoanForUser(user3, TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        address user4 = makeAddr("integrationTestUser4");
        _setupUserWithoutBLP(user4);
        vm.warp(block.timestamp + 1);
        _createLoanForUser(user4, TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        // Act -- create loan B with same params as A, after utilization spike
        vm.warp(block.timestamp + 1);
        (, DataTypes.LoanData memory loanDataB) =
            _createLoanWithData(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        // Assert -- EMI must not change with pool utilization
        // If this fails, it means a front-running attacker can inflate victims' monthly payments
        assertEq(
            loanDataB.estimatedMonthlyPayment,
            baselineEMI,
            "EMI must not change with pool utilization -- utilization-dependent EMI enables griefing"
        );
    }

    // ============ Test 23: Pool State Change Between Calc and Borrow ============

    /// @notice Pool reserve indices and utilization change between loan A's creation and loan B's
    ///         creation. Loan B must still succeed and maintain a healthy position despite stale
    ///         index values used during LoanLogic calculation vs actual borrow execution.
    /// @dev Attack scenario:
    ///      1. Loan A is created, changing reserve indices and utilization
    ///      2. Loan B is created immediately after (next second for salt uniqueness)
    ///      3. If LoanLogic uses stale indices for calculation but the borrow uses updated ones,
    ///         loan B could be undercollateralized from inception.
    ///      FINDING if loan B fails or has health factor <= 1: inconsistent index usage.
    function test_IRM_PoolStateChange_BetweenCalcAndBorrow() public {
        // Arrange -- loan A changes pool state (reserve indices, utilization, etc.)
        address lsaA = _createStandardLoan();
        assertTrue(lsaA != address(0), "loan A must succeed as baseline");

        // Act -- loan B created immediately after, pool state has shifted
        vm.warp(block.timestamp + 1);
        address lsaB = _createStandardLoan();

        // Assert -- loan B must succeed despite pool state changes from loan A
        assertTrue(lsaB != address(0), "loan B must succeed despite pool state changes from loan A");
        assertTrue(lsaB != lsaA, "loan B LSA must be distinct from loan A LSA");

        // Assert -- loan B health factor must use consistent index values
        (uint256 collateralB, uint256 debtB, uint256 healthFactorB) = _getUserAccountData(lsaB);
        assertGt(
            healthFactorB,
            TC.PRECISION,
            "loan B health factor must be above 1e18 -- inconsistent index values between calc and borrow"
        );

        // Assert -- loan B must have meaningful collateral and debt (not zero due to rounding)
        assertGt(collateralB, 0, "loan B collateral must be nonzero after pool state change");
        assertGt(debtB, 0, "loan B debt must be nonzero after pool state change");
    }
}
