// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {ILendingPool} from "../../interfaces/ILendingPool.sol";
import {DataTypes} from "../types/DataTypes.sol";

/**
 * @title BitmorLendingPoolLogic
 * @author Bitmor Protocol
 * @notice Library for interacting with the Bitmor Lending Pool (Aave V2 fork)
 * @dev Provides standardized functions for deposit, borrow, repay, and position queries.
 *
 * ## Supported Operations
 * - Depositing collateral (bvBTC) on behalf of LSAs
 * - Borrowing debt (USDC) on behalf of LSAs
 * - Repaying debt positions
 * - Querying user positions and token balances
 *
 * ## Interest Rate Mode
 * All borrow operations use variable rate mode (RATE_MODE = 2).
 * Stable rate borrowing is not supported in this implementation.
 *
 * @custom:security All operations require proper approvals to be set before execution
 */
library BitmorLendingPoolLogic {
    /// @dev Variable interest rate mode for Aave V2 borrows
    uint256 constant RATE_MODE = 2;

    /// @dev Referral code for Aave operations (0 = no referral)
    uint16 constant REFERRAL = 0;

    /**
     * @notice Returns the amount of variable debt tokens (vdtTokens) held by an LSA
     * @dev Queries the variable debt token balance directly from the debt token contract
     * @param bitmorPool Bitmor Lending Pool address for reserve data lookup
     * @param debtAsset Debt asset token address (USDC)
     * @param lsa The Loan Specific Address to query
     * @return vdtTokenAmount The amount of variable debt tokens representing outstanding debt
     */
    function getVDTTokenAmount(address bitmorPool, address debtAsset, address lsa)
        internal
        view
        returns (uint256 vdtTokenAmount)
    {
        DataTypes.ReserveData memory data = ILendingPool(bitmorPool).getReserveData(debtAsset);

        vdtTokenAmount = IERC20(data.variableDebtTokenAddress).balanceOf(lsa);
    }

    /**
     * @notice Returns the amount of aTokens (collateral tokens) held by an LSA
     * @dev Queries the aToken balance directly from the aToken contract
     * @param bitmorPool Bitmor Lending Pool address for reserve data lookup
     * @param collateralAsset Collateral asset token address (bvBTC)
     * @param lsa The Loan Specific Address to query
     * @return aTokenAmount The amount of aTokens representing deposited collateral
     */
    function getATokenAmount(address bitmorPool, address collateralAsset, address lsa)
        internal
        view
        returns (uint256 aTokenAmount)
    {
        DataTypes.ReserveData memory data = ILendingPool(bitmorPool).getReserveData(collateralAsset);

        aTokenAmount = IERC20(data.aTokenAddress).balanceOf(lsa);
    }

    /**
     * @notice Retrieves the current USD-denominated positions for an LSA
     * @dev Calls `getUserAccountData` on the Bitmor Lending Pool to get aggregate position values
     * @param bitmorPool Bitmor Lending Pool address
     * @param lsa The Loan Specific Address to query
     * @return totalCollateralUSD Total collateral value in USD (8 decimals)
     * @return totalDebtUSD Total debt value in USD (8 decimals)
     */
    function getUserPositions(address bitmorPool, address lsa)
        internal
        view
        returns (uint256 totalCollateralUSD, uint256 totalDebtUSD)
    {
        (totalCollateralUSD, totalDebtUSD,,,,) = ILendingPool(bitmorPool).getUserAccountData(lsa);
    }

    /**
     * @notice Deposits collateral to Aave V2 on behalf of LSA
     * @dev LSA receives aTokens (abvBTC), Protocol holds bvBTC before deposit
     * @param bitmorPool Bitmor Lending Pool address
     * @param asset Collateral asset (bvBTC)
     * @param amount Amount to deposit (8 decimals)
     * @param onBehalfOf LSA address that receives aTokens
     */
    function depositCollateral(address bitmorPool, address asset, uint256 amount, address onBehalfOf) internal {
        ILendingPool(bitmorPool).deposit(asset, amount, onBehalfOf, REFERRAL);
    }

    /**
     * @notice Borrows debt from Aave V2 on behalf of LSA
     * @dev Protocol receives USDC, LSA receives variable debt tokens
     * @param bitmorPool Bitmor Lending Pool address
     * @param asset Debt asset (USDC)
     * @param amount Amount to borrow (6 decimals)
     * @param onBehalfOf LSA address that receives debt tokens
     */
    function borrowDebt(address bitmorPool, address asset, uint256 amount, address onBehalfOf) internal {
        // Borrow from Aave V2 - onBehalfOf receives debt, caller receives USDC
        ILendingPool(bitmorPool).borrow(asset, amount, RATE_MODE, REFERRAL, onBehalfOf);
    }

    /**
     * @notice Executes loan repayment on Aave V2 and updates loan state
     * @dev Updates loanAmount, lastPaymentTimestamp, nextDueTimestamp, and status. Marks loan as Completed if fully repaid.
     * @param bitmorPool Bitmor Lending Pool address
     * @param debtAsset USDC token address (debt asset)
     * @param lsa Loan Specific Address (the borrower address on Aave)
     * @param amount Maximum amount to repay (actual repaid may be less if debt is smaller)
     * @return finalAmountRepaid Actual amount repaid to Aave
     */
    function executeLoanRepayment(address bitmorPool, address debtAsset, address lsa, uint256 amount)
        internal
        returns (uint256 finalAmountRepaid)
    {
        // NOTE: Allowance must be set by the caller (Loan.sol) that holds the funds.
        // Aave V2 will pull up to `amount` from the caller (Loan.sol) during `repay`.
        finalAmountRepaid = ILendingPool(bitmorPool).repay(debtAsset, amount, RATE_MODE, lsa);
    }
}
