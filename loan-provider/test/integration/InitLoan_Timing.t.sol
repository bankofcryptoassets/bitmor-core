// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IntegrationTestBase} from "../base/IntegrationTestBase.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";

/// @title InitLoan_TimingTest
/// @author Bitmor Protocol
/// @notice Adversarial integration tests for timing-related edge cases during loan lifecycle
/// @dev Failing tests = security findings, NOT test bugs. Do NOT weaken assertions.
contract InitLoan_TimingTest is IntegrationTestBase {
    // ============ Constants ============

    uint256 constant SHARE_PRICE_IMPACT_TOLERANCE = 0.01e18; // 1%

    // ============ Setup ============

    function setUp() public override {
        super.setUp();
        _setupTestUser();
    }

    // ============ Test 29: Concurrent Flash Loans - Aave Pool Drain ============

    /// @notice Two users create loans in rapid succession (same block window). If the Aave V3
    ///         pool cannot service both flash loans, or if the second loan inherits state from
    ///         the first (e.g., stale reserves), one or both loans could be born unhealthy.
    function test_Timing_ConcurrentFlashLoans_AavePoolDrain() public {
        // Arrange - set up second user
        address user2 = _setupSecondUser();

        // Act - User A creates standard loan
        address lsaA = _createStandardLoan();

        // Advance 1 second so CREATE2 salt differs (timestamp-based)
        vm.warp(block.timestamp + 1);

        // User B creates standard loan in the next second
        address lsaB = _createLoanForUser(user2, TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        // Assert - both loans must be healthy and distinct
        (, , uint256 healthFactorA) = _getUserAccountData(lsaA);
        (, , uint256 healthFactorB) = _getUserAccountData(lsaB);

        assertGt(healthFactorA, 1e18, "first loan health factor must be > 1");
        assertGt(healthFactorB, 1e18, "second loan health factor must be > 1");
        assertGt(lsaA.code.length, 0, "first loan LSA must have code");
        assertTrue(lsaA != lsaB, "LSAs must be distinct");
    }

    // ============ Test 30: Back-to-Back Loans - Same User Same BTC ============

    /// @notice Same user creates two loans in quick succession. The second loan must NOT
    ///         benefit from the first loan's collateral (each LSA is isolated). If the
    ///         factory reuses addresses or the lending pool conflates positions, one loan
    ///         could be over/under-collateralized at the expense of the other.
    function test_Timing_BackToBackLoans_SameUser_SameBTC() public {
        // Act - create first loan
        address lsa1 = _createLoan(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        // Advance 1 second for unique CREATE2 salt
        vm.warp(block.timestamp + 1);

        // Create second loan with identical parameters
        address lsa2 = _createLoan(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        // Assert - LSAs must be distinct
        assertTrue(lsa1 != lsa2, "LSAs must be distinct");

        // Assert - user must have both loans tracked
        DataTypes.LoanData[] memory userLoans = loanContract.getUserAllLoans(testUser);
        assertEq(userLoans.length, 2, "user must have 2 loans tracked");

        // Assert - each loan's BLP debt should be approximately equal (isolated positions)
        (, uint256 debt1, ) = _getUserAccountData(lsa1);
        (, uint256 debt2, ) = _getUserAccountData(lsa2);
        assertApproxEqRel(
            debt1,
            debt2,
            SHARE_PRICE_IMPACT_TOLERANCE,
            "second loan must not benefit from first loan's collateral"
        );
    }

    // ============ Test 31: BTCVault Exit Fee Change Between Init And Close ============

    /// @notice Admin changes BTCVault exit fee after loan creation. The loan must still close
    ///         successfully. If the close-loan flow does not account for a higher exit fee
    ///         (e.g., insufficient flash loan amount or slippage), the close reverts and
    ///         the user's collateral is trapped.
    function test_BTCVault_ExitFeeChange_BetweenInitAndClose() public {
        // Arrange - create loan
        (address lsa, DataTypes.LoanData memory loanData) =
            _createLoanWithData(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        // Change BTCVault exit fee via admin (ADMIN role, no delay in deployed system)
        // setExitFee is `restricted` and defaults to ADMIN role (role 0) since BVM_SLOW
        // selectors are not mapped to BTCVault in the deployment scripts.
        uint256 newExitFee = 500; // 5% exit fee (was likely 0 or lower)
        bytes memory setExitFeeData = abi.encodeCall(btcVault.setExitFee, (newExitFee));

        // ADMIN role (id=0) has no delay, so _scheduleAndExecute executes immediately
        uint64 adminRoleId = 0;
        _scheduleAndExecute(address(btcVault), admin, adminRoleId, setExitFeeData);

        // Verify exit fee was updated
        assertEq(btcVault.getExitFee(), newExitFee, "exit fee must be updated to new value");

        // Do 1 repayment so loan has activity
        _advanceDays(30);
        vm.prank(testUser);
        loanContract.repay(lsa, loanData.estimatedMonthlyPayment);

        // Ensure user has enough USDC for closing (generous buffer for fees + flash loan repayment)
        _fundUSDC(testUser, loanData.loanAmount * 2);
        vm.prank(testUser);
        usdc.approve(address(loanContract), type(uint256).max);

        // Act - close the loan with the new (higher) exit fee in effect
        vm.prank(testUser);
        loanContract.closeLoan(lsa, false);

        // Assert - loan must close successfully despite exit fee change
        DataTypes.LoanData memory finalData = loanContract.getLoanByLSA(lsa);
        assertEq(
            uint256(finalData.status),
            uint256(DataTypes.LoanStatus.Completed),
            "loan must close successfully even after exit fee change"
        );
    }
}
