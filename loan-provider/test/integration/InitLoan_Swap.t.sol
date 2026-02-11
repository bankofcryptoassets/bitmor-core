// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IntegrationTestBase} from "../base/IntegrationTestBase.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {MockSwapAdapter} from "../mock/MockSwapAdapter.sol";

/// @title InitLoan_SwapTest
/// @notice Adversarial integration tests for swap behavior during loan initialization.
///         Failing tests indicate security findings, not test bugs.
contract InitLoan_SwapTest is IntegrationTestBase {
    uint256 constant SHARE_PRICE_IMPACT_TOLERANCE = 0.01e18; // 1%

    function setUp() public override {
        super.setUp();
        _setupTestUser();
    }

    // ============ Test 17: Worst-Case Slippage Solvency ============

    /// @notice Verifies protocol solvency when swap executes at maximum allowed slippage
    /// @dev Security property: even at worst-case slippage (50 bps), the resulting loan
    ///      must be healthy AND remain healthy if the oracle corrects to the execution price.
    function test_Swap_WorstCaseSlippage_LoanAndProtocolStillSolvent() public {
        // Arrange - configure swap adapter for worst-case slippage
        MockSwapAdapter(swapper).setSlippage(TC.SLIPPAGE_SWAP);

        // Act - create loan under worst-case swap conditions
        address lsa = _createLoan(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        // Assert - loan must be healthy immediately after creation
        (,, uint256 healthFactor) = _getUserAccountData(lsa);
        assertGt(healthFactor, 1e18, "loan must be healthy even at worst-case slippage");

        // Simulate oracle correcting down to match the execution price (~1% to be conservative)
        _dropOraclePrice(1);

        // Assert - protocol must remain solvent after oracle correction
        (,, uint256 healthFactorAfterDrop) = _getUserAccountData(lsa);
        assertGt(healthFactorAfterDrop, 1e18, "protocol must remain solvent if oracle corrects to execution price");
    }

    // ============ Test 18: Leftover USDC Isolation Between Loans ============

    /// @notice Verifies that USDC leftovers from loan A do not leak into or subsidize loan B
    /// @dev Security property: each loan must be independently funded. Leftover dust in the
    ///      Loan contract from a previous initialization must not affect subsequent loans.
    function test_Swap_LeftoverUSDC_IsolatedBetweenLoans() public {
        // Arrange + Act - create loan A
        (address lsaA, DataTypes.LoanData memory loanDataA) =
            _createLoanWithData(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);
        uint256 loanContractBalAfterA = usdc.balanceOf(address(loanContract));

        // Advance 1 second so CREATE2 salt differs
        vm.warp(block.timestamp + 1);

        // Act - create loan B with identical parameters
        (address lsaB, DataTypes.LoanData memory loanDataB) =
            _createLoanWithData(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);
        uint256 loanContractBalAfterB = usdc.balanceOf(address(loanContract));

        // Assert - second loan amount must be independent of first loan leftovers
        assertApproxEqRel(
            loanDataB.loanAmount,
            loanDataA.loanAmount,
            SHARE_PRICE_IMPACT_TOLERANCE,
            "second loan amount must be independent of first loan leftovers"
        );

        // Assert - Loan contract USDC balance must not decrease (no leftover consumption)
        assertGe(
            loanContractBalAfterB,
            loanContractBalAfterA,
            "Loan contract USDC balance must not decrease between loan initializations"
        );
    }
}
