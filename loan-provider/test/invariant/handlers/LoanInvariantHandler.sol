// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {LoanFuzzTestBase} from "../../fuzz/base/LoanFuzzTestBase.sol";
import {FuzzConstants as FC} from "../../fuzz/helpers/FuzzConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";

/**
 * @title LoanInvariantHandler
 * @author Bitmor Protocol
 * @notice Handler contract for invariant testing of Loan lifecycle
 * @dev Provides 5 handler functions with ghost state tracking for loan invariants.
 *      Extends `LoanFuzzTestBase` for full loan infrastructure with mock lending pool.
 *      Multi-actor: rotates through 3 users with EXECUTOR role.
 *      All operations use `try/catch` for graceful failure on boundary conditions.
 *
 * @custom:audit-category Invariant Testing, Loan Lifecycle
 */
contract LoanInvariantHandler is LoanFuzzTestBase {
    // ============ LoanGhost Struct ============

    /// @dev Per-loan ghost state for tracking invariants
    struct LoanGhost {
        address borrower;
        uint256 collateral;
        uint256 deposit;
        uint256 initialLoanAmount;
        uint256 initialDuration;
        uint256 totalRepaid;
        uint256 repayCount;
        uint256 lastKnownDuration;
        bool wasCreated;
    }

    // ============ Global Ghost Counters ============

    /// @dev Total number of successfully created loans
    uint256 public ghost_loanCount;

    /// @dev Total number of loans that have been closed or completed
    uint256 public ghost_closedCount;

    /// @dev Total number of successful repay operations
    uint256 public ghost_repayCount;

    /// @dev Total number of all handler operations (for observability)
    uint256 public ghost_totalOps;

    // ============ Per-User Ghost State ============

    /// @dev Per-user loan count for INV-LOAN-01
    mapping(address => uint256) public ghost_userLoanCount;

    // ============ LSA Tracking ============

    /// @dev All LSAs ever created (never shrinks)
    address[] internal _allLSAs;

    /// @dev Currently active LSAs (swap-and-pop on close/complete)
    address[] internal _activeLSAs;

    /// @dev Whether an LSA is currently active
    mapping(address => bool) public isActive;

    /// @dev Per-LSA ghost state
    mapping(address => LoanGhost) internal _loanGhosts;

    // ============ User Management ============

    /// @dev Array of users for round-robin rotation
    address[] internal _users;

    /// @dev Index for round-robin user selection
    uint256 internal _userIndex;

    /// @notice Second test user
    address public user2;

    /// @notice Third test user
    address public user3;

    // ============ setUp ============

    /// @notice Deploys full loan infrastructure and configures 3 users with EXECUTOR role
    function setUp() public override {
        super.setUp();

        user2 = makeAddr("loanInvUser2");
        user3 = makeAddr("loanInvUser3");

        // Cache role ID before prank to avoid consuming it
        uint64 executorRoleId = EXECUTOR_ID();
        // address(this) is admin in fuzz base pattern — no prank needed
        manager.grantRole(executorRoleId, user2, NO_DELAY);
        manager.grantRole(executorRoleId, user3, NO_DELAY);

        // user already has EXECUTOR from LoanFuzzTestBase._configureLoanRoles()
        _users.push(user);
        _users.push(user2);
        _users.push(user3);
    }

    // ============ Handler Functions ============

    /**
     * @notice Handler for loan initialization
     * @dev Rotates users via _nextUser(). Bounds collateral/deposit/duration to valid ranges.
     *      Funds actor with deposit + premium + buffer. Uses try/catch for graceful failure.
     * @param collateralSeed Seed for bounded collateral amount
     * @param depositSeed Seed for bounded deposit amount
     * @param durationSeed Seed for bounded duration
     * @param premiumSeed Seed for bounded premium amount
     */
    function handler_initializeLoan(
        uint256 collateralSeed,
        uint256 depositSeed,
        uint256 durationSeed,
        uint256 premiumSeed
    ) external {
        address actor = _nextUser();

        uint256 collateral = _boundCollateral(collateralSeed);
        uint256 duration = _boundDuration(durationSeed);
        uint256 premium = bound(premiumSeed, 0, 100_000e6);

        (uint256 deposit,) = _boundValidDeposit(collateral, duration, depositSeed);

        uint256 fundAmount = deposit + premium + FC.MAX_USDC_AMOUNT;
        _fundUSDCAndApprove(actor, address(loan), fundAmount);

        vm.prank(actor);
        try loan.initializeLoan(deposit, premium, collateral, duration, "") returns (address lsa) {
            DataTypes.LoanData memory data = loan.getLoanByLSA(lsa);

            ghost_loanCount++;
            ghost_userLoanCount[actor]++;
            ghost_totalOps++;

            _allLSAs.push(lsa);
            _activeLSAs.push(lsa);
            isActive[lsa] = true;

            _loanGhosts[lsa] = LoanGhost({
                borrower: actor,
                collateral: collateral,
                deposit: deposit,
                initialLoanAmount: data.loanAmount,
                initialDuration: duration,
                totalRepaid: 0,
                repayCount: 0,
                lastKnownDuration: duration,
                wasCreated: true
            });
        } catch {
            // Graceful failure on boundary conditions
        }
    }

    /**
     * @notice Handler for partial loan repayment
     * @dev Picks a random active LSA. Bounds amount to [MIN_USDC_AMOUNT, debt-1] for partial repay.
     *      Advances time 30 days. Uses stored borrower as msg.sender.
     * @param lsaIndexSeed Seed for random active LSA selection
     * @param amountSeed Seed for bounded repayment amount
     */
    function handler_repay(uint256 lsaIndexSeed, uint256 amountSeed) external {
        if (_activeLSAs.length == 0) return;

        uint256 idx = bound(lsaIndexSeed, 0, _activeLSAs.length - 1);
        address lsa = _activeLSAs[idx];
        LoanGhost storage ghost = _loanGhosts[lsa];

        uint256 debt = _getDebtBalance(lsa);
        if (debt <= FC.MIN_USDC_AMOUNT) return;

        uint256 amount = bound(amountSeed, FC.MIN_USDC_AMOUNT, debt - 1);

        _advanceDays(30);

        _fundUSDCAndApprove(ghost.borrower, address(loan), amount);

        vm.prank(ghost.borrower);
        try loan.repay(lsa, amount) returns (uint256 repaid) {
            ghost.totalRepaid += repaid;
            ghost.repayCount++;
            ghost_repayCount++;
            ghost_totalOps++;

            DataTypes.LoanData memory data = loan.getLoanByLSA(lsa);
            ghost.lastKnownDuration = data.duration;

            if (data.status == DataTypes.LoanStatus.Completed) {
                _deactivateLSA(lsa);
                ghost_closedCount++;
            }
        } catch {
            // Graceful failure
        }
    }

    /**
     * @notice Handler for full loan repayment
     * @dev Picks a random active LSA. Repays full debt balance. Advances time 30 days.
     * @param lsaIndexSeed Seed for random active LSA selection
     */
    function handler_repayFull(uint256 lsaIndexSeed) external {
        if (_activeLSAs.length == 0) return;

        uint256 idx = bound(lsaIndexSeed, 0, _activeLSAs.length - 1);
        address lsa = _activeLSAs[idx];
        LoanGhost storage ghost = _loanGhosts[lsa];

        uint256 debt = _getDebtBalance(lsa);
        if (debt == 0) return;

        _advanceDays(30);

        _fundUSDCAndApprove(ghost.borrower, address(loan), debt);

        vm.prank(ghost.borrower);
        try loan.repay(lsa, debt) returns (uint256 repaid) {
            ghost.totalRepaid += repaid;
            ghost.repayCount++;
            ghost_repayCount++;
            ghost_totalOps++;

            DataTypes.LoanData memory data = loan.getLoanByLSA(lsa);
            ghost.lastKnownDuration = data.duration;

            if (data.status == DataTypes.LoanStatus.Completed) {
                _deactivateLSA(lsa);
                ghost_closedCount++;
            }
        } catch {
            // Graceful failure
        }
    }

    /**
     * @notice Handler for closing a loan via flash loan
     * @dev Picks a random active LSA. Must prank as stored borrower (CloseLoanLogic:120
     *      checks msg.sender == borrower). Funds borrower with debt + buffer as safety margin.
     * @param lsaIndexSeed Seed for random active LSA selection
     * @param withdrawInBtc Whether borrower receives surplus in BTC or USDC
     */
    function handler_closeLoan(uint256 lsaIndexSeed, bool withdrawInBtc) external {
        if (_activeLSAs.length == 0) return;

        uint256 idx = bound(lsaIndexSeed, 0, _activeLSAs.length - 1);
        address lsa = _activeLSAs[idx];
        LoanGhost storage ghost = _loanGhosts[lsa];

        uint256 debt = _getDebtBalance(lsa);
        uint256 buffer = (debt / 10) + FC.MAX_USDC_AMOUNT;
        _fundUSDCAndApprove(ghost.borrower, address(loan), debt + buffer);

        vm.prank(ghost.borrower);
        try loan.closeLoan(lsa, withdrawInBtc) {
            ghost_closedCount++;
            ghost_totalOps++;
            _deactivateLSA(lsa);
        } catch {
            // Graceful failure
        }
    }

    /**
     * @notice Handler for time advancement without loan interaction
     * @dev Warps block.timestamp forward by 1-90 days
     * @param daysSeed Seed for bounded number of days
     */
    function handler_advanceTime(uint256 daysSeed) external {
        uint256 d = bound(daysSeed, 1, 90);
        vm.warp(block.timestamp + d * 1 days);
        ghost_totalOps++;
    }

    // ============ Internal Helpers ============

    /// @dev Swap-and-pop removal from activeLSAs + mark inactive
    function _deactivateLSA(address lsa) internal {
        isActive[lsa] = false;
        for (uint256 i = 0; i < _activeLSAs.length; i++) {
            if (_activeLSAs[i] == lsa) {
                _activeLSAs[i] = _activeLSAs[_activeLSAs.length - 1];
                _activeLSAs.pop();
                break;
            }
        }
    }

    /// @dev Round-robin user selection
    function _nextUser() internal returns (address) {
        address u = _users[_userIndex % _users.length];
        _userIndex++;
        return u;
    }

    // ============ View Helpers ============

    /// @notice Returns the total number of LSAs ever created
    function getAllLSACount() external view returns (uint256) {
        return _allLSAs.length;
    }

    /// @notice Returns the number of currently active LSAs
    function getActiveLSACount() external view returns (uint256) {
        return _activeLSAs.length;
    }

    /// @notice Returns the LSA address at index i in the all-LSAs array
    function getAllLSAAt(uint256 i) external view returns (address) {
        return _allLSAs[i];
    }

    /// @notice Returns the LSA address at index i in the active-LSAs array
    function getActiveLSAAt(uint256 i) external view returns (address) {
        return _activeLSAs[i];
    }

    /// @notice Returns the ghost state for a given LSA
    function getLoanGhost(address lsa) external view returns (LoanGhost memory) {
        return _loanGhosts[lsa];
    }

    /// @notice Returns the total number of users in the rotation
    function getUserCount() external view returns (uint256) {
        return _users.length;
    }

    /// @notice Returns the user address at index i
    function getUserAt(uint256 i) external view returns (address) {
        return _users[i];
    }
}
