// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {LoanUnitTestBase} from "../../base/LoanUnitTestBase.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";

/**
 * @title LoanHandler
 * @author Bitmor Protocol
 * @notice Handler contract for stateful fuzz testing of Loan contract
 * @dev Wraps Loan operations with proper setup and state tracking for invariant testing
 *
 * ## Usage
 * This handler is used with Foundry's invariant testing to track state across
 * multiple randomized operations. Each handler function:
 * 1. Bounds inputs to valid ranges using bound helpers
 * 2. Performs necessary setup (funding, approvals)
 * 3. Executes the operation with graceful failure handling
 * 4. Tracks state changes for invariant verification
 */
contract LoanHandler is LoanUnitTestBase {
    // ============ State Tracking ============

    /// @dev Array of all created LSA addresses
    address[] public activeLSAs;

    /// @dev Mapping of LSA to total amount repaid
    mapping(address => uint256) public totalRepaid;

    /// @dev Mapping of LSA to total collateral deposited
    mapping(address => uint256) public totalCollateral;

    /// @dev Counter for successful loan initializations
    uint256 public initializeCount;

    /// @dev Counter for successful repayments
    uint256 public repayCount;

    /// @dev Counter for successful closures
    uint256 public closeCount;

    // ============ Handler Actions ============

    /**
     * @notice Handler for loan initialization
     * @dev Bounds inputs to valid ranges, funds user, and attempts loan creation
     * @param collateralSeed Seed for collateral amount
     * @param depositSeed Seed for deposit amount
     * @param durationSeed Seed for duration
     */
    function handler_initializeLoan(uint256 collateralSeed, uint256 depositSeed, uint256 durationSeed) external {
        // Bound inputs to valid ranges
        uint256 collateral = _boundCollateralFromLoan(collateralSeed);
        uint256 duration = _boundDuration(durationSeed);

        // Get collateral value and bound deposit
        uint256 btcPrice = mockOracle.getAssetPrice(address(mockCbBTC));
        uint256 collateralValueUsd = _getCollateralValueUsd(collateral, btcPrice);
        uint256 deposit = _boundDeposit(collateralValueUsd, depositSeed);

        // Fund user with sufficient USDC (deposit + buffer for fees)
        uint256 totalNeeded = deposit + FC.MAX_USDC_AMOUNT;
        _fundUSDCAndApprove(user, address(loan), totalNeeded);

        // Attempt loan creation with graceful failure handling
        vm.prank(user);
        try loan.initializeLoan(deposit, 0, collateral, duration, "") returns (address lsa) {
            activeLSAs.push(lsa);
            totalCollateral[lsa] = collateral;
            initializeCount++;
        } catch {
            // Graceful failure - don't revert handler
            // This allows invariant testing to continue
        }
    }

    /**
     * @notice Handler for loan repayment
     * @dev Selects a random active LSA and attempts partial repayment
     * @param lsaIndexSeed Seed for selecting LSA from active list
     * @param amountSeed Seed for repayment amount
     */
    function handler_repay(uint256 lsaIndexSeed, uint256 amountSeed) external {
        // Early return if no active loans
        if (activeLSAs.length == 0) return;

        // Select LSA from active list
        uint256 index = lsaIndexSeed % activeLSAs.length;
        address lsa = activeLSAs[index];

        // Check loan is still active
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        if (loanData.status != DataTypes.LoanStatus.Active) return;

        // Get current debt and bound repayment amount
        uint256 debt = _getDebtBalance(lsa);
        if (debt == 0) return;

        uint256 amount = bound(amountSeed, FC.MIN_USDC_AMOUNT, debt);

        // Fund user and attempt repayment
        _fundUSDCAndApprove(user, address(loan), amount);

        // Advance time to allow repayment (past first month)
        vm.warp(block.timestamp + 30 days);

        vm.prank(user);
        try loan.repay(lsa, amount) {
            totalRepaid[lsa] += amount;
            repayCount++;
        } catch {
            // Graceful failure - don't revert handler
        }
    }

    /**
     * @notice Handler for loan closure
     * @dev Selects a random active LSA and attempts full closure
     * @param lsaIndexSeed Seed for selecting LSA from active list
     * @param withdrawInBtc Whether to withdraw remaining collateral in BTC
     */
    function handler_closeLoan(uint256 lsaIndexSeed, bool withdrawInBtc) external {
        // Early return if no active loans
        if (activeLSAs.length == 0) return;

        // Select LSA from active list
        uint256 index = lsaIndexSeed % activeLSAs.length;
        address lsa = activeLSAs[index];

        // Check loan is still active
        DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
        if (loanData.status != DataTypes.LoanStatus.Active) return;

        // Fund user for closure (need to cover remaining debt + fees)
        uint256 debt = _getDebtBalance(lsa);
        _fundUSDCAndApprove(user, address(loan), debt + FC.MAX_USDC_AMOUNT);

        vm.prank(user);
        try loan.closeLoan(lsa, withdrawInBtc) {
            closeCount++;
            _removeFromActive(index);
        } catch {
            // Graceful failure - don't revert handler
        }
    }

    // ============ View Functions ============

    /**
     * @notice Returns count of active loans
     * @return Number of loans currently in the active list
     */
    function getActiveLoanCount() external view returns (uint256) {
        return activeLSAs.length;
    }

    /**
     * @notice Returns LSA at specified index
     * @param index Index in the active LSA array
     * @return LSA address at the given index
     */
    function getLSAAt(uint256 index) external view returns (address) {
        require(index < activeLSAs.length, "Index out of bounds");
        return activeLSAs[index];
    }

    /**
     * @notice Returns total repaid amount for an LSA
     * @param lsa The Loan Specific Address
     * @return Total amount repaid to this loan
     */
    function getTotalRepaid(address lsa) external view returns (uint256) {
        return totalRepaid[lsa];
    }

    /**
     * @notice Returns total collateral deposited for an LSA
     * @param lsa The Loan Specific Address
     * @return Collateral amount deposited at loan creation
     */
    function getTotalCollateral(address lsa) external view returns (uint256) {
        return totalCollateral[lsa];
    }

    // ============ Internal Functions ============

    /**
     * @notice Removes LSA from active list using swap-and-pop
     * @param index Index of LSA to remove
     */
    function _removeFromActive(uint256 index) internal {
        activeLSAs[index] = activeLSAs[activeLSAs.length - 1];
        activeLSAs.pop();
    }

    /**
     * @notice Bounds collateral using Loan contract's actual min/max parameters
     * @param raw The raw fuzzed input
     * @return The bounded collateral amount
     */
    function _boundCollateralFromLoan(uint256 raw) internal view returns (uint256) {
        uint256 maxBTC = loan.getMaxBTCAmount();
        uint256 minBTC = loan.getMinBTCAmount();
        return bound(raw, minBTC, maxBTC);
    }

    /**
     * @notice Bounds raw input to valid loan duration range
     * @param raw The raw fuzzed input
     * @return The bounded duration (1 - 60 months)
     */
    function _boundDuration(uint256 raw) internal pure returns (uint256) {
        return bound(raw, FC.MIN_DURATION, FC.MAX_DURATION);
    }

    /**
     * @notice Calculates collateral value in USD
     * @param collateralAmount BTC amount (8 decimals)
     * @param btcPrice BTC price in USD (8 decimals)
     * @return Collateral value in USD (8 decimals)
     */
    function _getCollateralValueUsd(uint256 collateralAmount, uint256 btcPrice) internal pure returns (uint256) {
        return (collateralAmount * btcPrice) / 1e8;
    }

    /**
     * @notice Bounds raw input to valid deposit range based on collateral value
     * @param collateralValueUsd The collateral value in USD (8 decimals)
     * @param raw The raw fuzzed input
     * @return The bounded deposit amount in USDC (6 decimals)
     */
    function _boundDeposit(uint256 collateralValueUsd, uint256 raw) internal pure returns (uint256) {
        uint256 minDepositUsd = (collateralValueUsd * FC.MIN_DEPOSIT_BPS) / FC.BPS_DENOMINATOR;
        uint256 maxDepositUsd = collateralValueUsd;

        // Convert to USDC (6 decimals) from USD (8 decimals)
        uint256 minDepositUsdc = (minDepositUsd * 1e6) / 1e8;
        uint256 maxDepositUsdc = (maxDepositUsd * 1e6) / 1e8;

        // Ensure min <= max
        if (minDepositUsdc >= maxDepositUsdc) {
            return maxDepositUsdc;
        }

        return bound(raw, minDepositUsdc, maxDepositUsdc);
    }
}
