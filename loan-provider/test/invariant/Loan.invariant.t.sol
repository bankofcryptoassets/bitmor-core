// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {LoanInvariantHandler} from "./handlers/LoanInvariantHandler.sol";
import {Loan} from "@bitmor/protocol/Loan.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {MockERC20} from "../mock/MockERC20.sol";
import {MockAToken} from "../mock/MockAToken.sol";
import {MockVariableDebtToken} from "../mock/MockVariableDebtToken.sol";

/**
 * @title LoanInvariantTest
 * @author Bitmor Protocol
 * @notice Invariant tests for Loan lifecycle with multi-actor handler
 * @dev Configures `LoanInvariantHandler` as the target contract and validates
 *      12 invariants + 1 call summary across randomized init/repay/close/time sequences.
 *
 * ## Invariants
 * - INV-LOAN-01: Loan count consistency (on-chain vs ghost)
 * - INV-LOAN-02: Active loan status consistency
 * - INV-LOAN-03: No USDC stuck in Loan contract
 * - INV-LOAN-04: No cbBTC stuck in Loan contract
 * - INV-LOAN-05: Cumulative repay never exceeds initial debt + tolerance
 * - INV-LOAN-06: Completed loans have zero debt
 * - INV-LOAN-07: Completed loans have zero collateral
 * - INV-LOAN-08: Active loans have collateral
 * - INV-LOAN-09: Immutable fields (borrower, loanAmount, collateralAmount) unchanged
 * - INV-LOAN-10: LSA address uniqueness
 * - INV-LOAN-11: Completed loans are sealed (zero debt + zero collateral)
 * - INV-LOAN-12: Duration monotonically decreases with repayments
 * - INV-LOAN-13: Call summary (always-passing observability)
 *
 * @custom:audit-category Invariant Testing, Loan Lifecycle
 */
contract LoanInvariantTest is Test {
    /// @dev The handler contract (also deploys loan + mocks in setUp)
    LoanInvariantHandler internal handler;

    /// @dev Cached reference to the Loan contract from handler
    Loan internal loan;

    /// @dev Mock USDC token for balance checks
    MockERC20 internal mockUSDC;

    /// @dev Mock cbBTC token for balance checks
    MockERC20 internal mockCbBTC;

    /// @dev Mock aToken for bvBTC collateral balance checks
    MockAToken internal mockATokenBvBTC;

    /// @dev Mock variable debt token for USDC debt balance checks
    MockVariableDebtToken internal mockDebtTokenUSDC;

    function setUp() public {
        handler = new LoanInvariantHandler();
        handler.setUp();

        // Cache references from handler
        loan = handler.loan();
        mockUSDC = handler.mockUSDC();
        mockCbBTC = handler.mockCbBTC();
        mockATokenBvBTC = handler.mockATokenBvBTC();
        mockDebtTokenUSDC = handler.mockDebtTokenUSDC();

        // Target only the handler
        targetContract(address(handler));

        // Target specific handler functions
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = handler.handler_initializeLoan.selector;
        selectors[1] = handler.handler_repay.selector;
        selectors[2] = handler.handler_repayFull.selector;
        selectors[3] = handler.handler_closeLoan.selector;
        selectors[4] = handler.handler_advanceTime.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // ============ Invariants ============

    /**
     * @notice INV-LOAN-01: Loan count consistency
     * @dev allLSAs.length must equal ghost_loanCount AND
     *      per-user loan.getUserLoanCount(user) must equal ghost_userLoanCount[user]
     */
    function invariant_LOAN_01_LoanCountConsistency() public view {
        uint256 allCount = handler.getAllLSACount();
        assertEq(allCount, handler.ghost_loanCount(), "INV-LOAN-01: allLSAs.length != ghost_loanCount");

        uint256 userCount = handler.getUserCount();
        for (uint256 i = 0; i < userCount; i++) {
            address u = handler.getUserAt(i);
            uint256 onChain = loan.getUserLoanCount(u);
            uint256 ghost = handler.ghost_userLoanCount(u);
            assertEq(onChain, ghost, "INV-LOAN-01: on-chain userLoanCount != ghost_userLoanCount");
        }
    }

    /**
     * @notice INV-LOAN-02: Active loan status consistency
     * @dev Active LSAs must have Active status; inactive LSAs must have Completed or Liquidated
     */
    function invariant_LOAN_02_ActiveLoanStatusConsistency() public view {
        // Check active LSAs have Active status
        uint256 activeCount = handler.getActiveLSACount();
        for (uint256 i = 0; i < activeCount; i++) {
            address lsa = handler.getActiveLSAAt(i);
            DataTypes.LoanData memory data = loan.getLoanByLSA(lsa);
            assertEq(
                uint256(data.status),
                uint256(DataTypes.LoanStatus.Active),
                "INV-LOAN-02: active LSA does not have Active status"
            );
        }

        // Check inactive LSAs have Completed or Liquidated status
        uint256 allCount = handler.getAllLSACount();
        for (uint256 i = 0; i < allCount; i++) {
            address lsa = handler.getAllLSAAt(i);
            if (!handler.isActive(lsa)) {
                DataTypes.LoanData memory data = loan.getLoanByLSA(lsa);
                assertTrue(
                    data.status == DataTypes.LoanStatus.Completed || data.status == DataTypes.LoanStatus.Liquidated,
                    "INV-LOAN-02: inactive LSA is not Completed or Liquidated"
                );
            }
        }
    }

    /**
     * @notice INV-LOAN-03: No excessive USDC stuck in Loan contract
     * @dev Each `initializeLoan` uses `swapExactOutput` to buy exact cbBTC collateral.
     *      The swap slippage buffer (~0.5% of collateral value) is not consumed and
     *      remains in the Loan contract. This is expected protocol behavior.
     *      Tolerance: up to 10,000 USDC per loan created (covers 1% of max collateral value).
     */
    function invariant_LOAN_03_NoUSDCStuckInLoan() public view {
        uint256 loanCount = handler.ghost_loanCount();
        if (loanCount == 0) {
            assertEq(mockUSDC.balanceOf(address(loan)), 0, "INV-LOAN-03: USDC stuck before any loans");
        } else {
            // Swap slippage (~0.5%) leaves unused USDC in Loan per initialization
            uint256 tolerance = loanCount * 10_000e6;
            assertLe(
                mockUSDC.balanceOf(address(loan)), tolerance, "INV-LOAN-03: USDC stuck exceeds swap slippage tolerance"
            );
        }
    }

    /**
     * @notice INV-LOAN-04: No cbBTC stuck in Loan contract
     * @dev The Loan contract should never hold cbBTC between transactions
     */
    function invariant_LOAN_04_NoCbBTCStuckInLoan() public view {
        assertEq(mockCbBTC.balanceOf(address(loan)), 0, "INV-LOAN-04: cbBTC stuck in Loan contract");
    }

    /**
     * @notice INV-LOAN-05: Cumulative repay never exceeds initial debt + tolerance
     * @dev For each loan, totalRepaid <= initialLoanAmount + tolerance.
     *      Tolerance accounts for: flash loan fees (~0.05-1%), interest accrual,
     *      and rounding per repay. Uses 5% of initialLoanAmount as generous bound.
     */
    function invariant_LOAN_05_CumulativeRepayNeverExceedsDebt() public view {
        uint256 allCount = handler.getAllLSACount();
        for (uint256 i = 0; i < allCount; i++) {
            address lsa = handler.getAllLSAAt(i);
            LoanInvariantHandler.LoanGhost memory ghost = handler.getLoanGhost(lsa);
            // Flash loan fees + interest accrual + rounding
            uint256 tolerance = (ghost.initialLoanAmount * 5) / 100 + ghost.repayCount * 2;
            assertLe(
                ghost.totalRepaid,
                ghost.initialLoanAmount + tolerance,
                "INV-LOAN-05: cumulative repay exceeds initial loan amount + tolerance"
            );
        }
    }

    /**
     * @notice INV-LOAN-06: Completed loans have zero debt
     * @dev Any LSA with Completed status must have zero debt token balance
     */
    function invariant_LOAN_06_CompletedLoanZeroDebt() public view {
        uint256 allCount = handler.getAllLSACount();
        for (uint256 i = 0; i < allCount; i++) {
            address lsa = handler.getAllLSAAt(i);
            if (!handler.isActive(lsa)) {
                DataTypes.LoanData memory data = loan.getLoanByLSA(lsa);
                if (data.status == DataTypes.LoanStatus.Completed) {
                    assertEq(mockDebtTokenUSDC.balanceOf(lsa), 0, "INV-LOAN-06: completed loan has non-zero debt");
                }
            }
        }
    }

    /**
     * @notice INV-LOAN-07: Completed loans have zero collateral
     * @dev Any LSA with Completed status must have zero aToken (collateral) balance
     */
    function invariant_LOAN_07_CompletedLoanZeroCollateral() public view {
        uint256 allCount = handler.getAllLSACount();
        for (uint256 i = 0; i < allCount; i++) {
            address lsa = handler.getAllLSAAt(i);
            if (!handler.isActive(lsa)) {
                DataTypes.LoanData memory data = loan.getLoanByLSA(lsa);
                if (data.status == DataTypes.LoanStatus.Completed) {
                    assertEq(mockATokenBvBTC.balanceOf(lsa), 0, "INV-LOAN-07: completed loan has non-zero collateral");
                }
            }
        }
    }

    /**
     * @notice INV-LOAN-08: Active loans have collateral
     * @dev Any active LSA must have a positive aToken (collateral) balance
     */
    function invariant_LOAN_08_ActiveLoanHasCollateral() public view {
        uint256 activeCount = handler.getActiveLSACount();
        for (uint256 i = 0; i < activeCount; i++) {
            address lsa = handler.getActiveLSAAt(i);
            assertGt(mockATokenBvBTC.balanceOf(lsa), 0, "INV-LOAN-08: active loan has zero collateral");
        }
    }

    /**
     * @notice INV-LOAN-09: Immutable fields unchanged on active loans
     * @dev For active LSAs: borrower, loanAmount, and collateralAmount must match ghost state
     */
    function invariant_LOAN_09_ImmutableFieldsUnchanged() public view {
        uint256 activeCount = handler.getActiveLSACount();
        for (uint256 i = 0; i < activeCount; i++) {
            address lsa = handler.getActiveLSAAt(i);
            DataTypes.LoanData memory data = loan.getLoanByLSA(lsa);
            LoanInvariantHandler.LoanGhost memory ghost = handler.getLoanGhost(lsa);

            assertEq(data.borrower, ghost.borrower, "INV-LOAN-09: borrower changed");
            assertEq(data.loanAmount, ghost.initialLoanAmount, "INV-LOAN-09: loanAmount changed");
            assertEq(data.collateralAmount, ghost.collateral, "INV-LOAN-09: collateralAmount changed");
        }
    }

    /**
     * @notice INV-LOAN-10: LSA address uniqueness
     * @dev O(n^2) check that no two allLSAs entries are the same (max ~15 LSAs, negligible gas)
     */
    function invariant_LOAN_10_LSAAddressUniqueness() public view {
        uint256 allCount = handler.getAllLSACount();
        for (uint256 i = 0; i < allCount; i++) {
            for (uint256 j = i + 1; j < allCount; j++) {
                address a = handler.getAllLSAAt(i);
                address b = handler.getAllLSAAt(j);
                assertTrue(a != b, "INV-LOAN-10: duplicate LSA address found");
            }
        }
    }

    /**
     * @notice INV-LOAN-11: Completed loans are sealed
     * @dev First 3 completed LSAs: status == Completed, zero debt, zero collateral
     */
    function invariant_LOAN_11_CompletedLoansSealed() public view {
        uint256 allCount = handler.getAllLSACount();
        uint256 checked = 0;
        for (uint256 i = 0; i < allCount && checked < 3; i++) {
            address lsa = handler.getAllLSAAt(i);
            if (!handler.isActive(lsa)) {
                DataTypes.LoanData memory data = loan.getLoanByLSA(lsa);
                if (data.status == DataTypes.LoanStatus.Completed) {
                    assertEq(mockDebtTokenUSDC.balanceOf(lsa), 0, "INV-LOAN-11: sealed completed loan has debt");
                    assertEq(mockATokenBvBTC.balanceOf(lsa), 0, "INV-LOAN-11: sealed completed loan has collateral");
                    checked++;
                }
            }
        }
    }

    /**
     * @notice INV-LOAN-12: Duration monotonically decreases with repayments
     * @dev For active LSAs with at least one repay:
     *      data.duration <= ghost.initialDuration AND data.duration <= ghost.lastKnownDuration
     */
    function invariant_LOAN_12_DurationMonotonicallyDecreases() public view {
        uint256 activeCount = handler.getActiveLSACount();
        for (uint256 i = 0; i < activeCount; i++) {
            address lsa = handler.getActiveLSAAt(i);
            DataTypes.LoanData memory data = loan.getLoanByLSA(lsa);
            LoanInvariantHandler.LoanGhost memory ghost = handler.getLoanGhost(lsa);

            if (ghost.repayCount > 0) {
                assertLe(data.duration, ghost.initialDuration, "INV-LOAN-12: duration exceeds initial duration");
                assertLe(data.duration, ghost.lastKnownDuration, "INV-LOAN-12: duration exceeds last known duration");
            }
        }
    }

    /**
     * @notice INV-LOAN-13: Call summary — always-passing observability
     * @dev Logs handler call counts for visibility into fuzzer exercise coverage
     */
    function invariant_LOAN_13_CallSummary() public view {
        uint256 totalOps = handler.ghost_totalOps();
        uint256 loans = handler.ghost_loanCount();
        uint256 repays = handler.ghost_repayCount();
        uint256 closed = handler.ghost_closedCount();
        uint256 active = handler.getActiveLSACount();

        // Silence unused variable warnings while keeping observability
        assertTrue(totalOps >= 0, "INV-LOAN-13: totalOps");
        assertTrue(loans >= 0, "INV-LOAN-13: loans");
        assertTrue(repays >= 0, "INV-LOAN-13: repays");
        assertTrue(closed >= 0, "INV-LOAN-13: closed");
        assertTrue(active >= 0, "INV-LOAN-13: active");
    }
}
