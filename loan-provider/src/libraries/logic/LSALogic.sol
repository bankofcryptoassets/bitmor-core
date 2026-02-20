// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {ERC4626} from "@solady/tokens/ERC4626.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

import {ILendingPool} from "../../interfaces/ILendingPool.sol";
import {ILoanVault} from "../../interfaces/ILoanVault.sol";

import {DataTypes} from "../types/DataTypes.sol";

import {BTCVaultLogic} from "./BTCVaultLogic.sol";
import {BitmorLendingPoolLogic} from "./BitmorLendingPoolLogic.sol";
import {Errors} from "../helpers/Errors.sol";

/**
 * @title LSALogic
 * @author Bitmor Protocol
 * @notice Library for Loan Specific Address (LSA) operations and credit delegation
 * @dev Handles interactions between the Loan contract and individual LoanVault instances.
 *
 * ## Responsibilities
 * - Credit delegation approval for borrowing on behalf of LSAs
 * - Collateral withdrawal from Bitmor Lending Pool via LSAs
 *
 * ## Credit Delegation Flow
 * 1. LSA approves Protocol (Loan contract) as delegatee via `approveCreditDelegation`
 * 2. Protocol borrows from Bitmor Pool on behalf of LSA
 * 3. LSA receives variable debt tokens, Protocol receives borrowed funds
 *
 * @custom:security All operations are executed through the LSA's `execute()` function
 */
library LSALogic {
    using BTCVaultLogic for address;
    using FixedPointMathLib for uint256;
    using BitmorLendingPoolLogic for address;

    /// @dev Maximum uint256 value used for max withdrawal amounts
    uint256 internal constant MAX_U256 = type(uint256).max;

    /// @dev Basis points denominator (10,000 = 100%) for slippage calculations
    uint256 internal constant BASIS_POINT_SCALE = 100_00;

    /**
     * @notice Approve credit delegation on LSA before borrowing
     * @dev This MUST be called BEFORE Protocol borrows on behalf of LSA
     *      Uses the existing execute() function in LoanVault
     * @param lsa The LSA address
     * @param bitmorPool Bitmor Lending Pool
     * @param debtAsset USDC address
     * @param amount Amount to delegate
     * @param delegatee Address that can borrow (Protocol address)
     */
    function approveCreditDelegation(
        address lsa,
        address bitmorPool,
        address debtAsset,
        uint256 amount,
        address delegatee
    ) internal {
        // Get variable debt token address from Aave V2
        DataTypes.ReserveData memory reserveData = ILendingPool(bitmorPool).getReserveData(debtAsset);
        address variableDebtToken = reserveData.variableDebtTokenAddress;

        if (variableDebtToken == address(0)) revert Errors.LSALogic__InvalidDebtToken();

        // Encode the approveDelegation call
        bytes memory data = abi.encodeWithSignature("approveDelegation(address,uint256)", delegatee, amount);

        // Use LSA's execute() function to call variableDebtToken.approveDelegation()
        ILoanVault(lsa).execute(variableDebtToken, data);
    }

    /**
     * @notice Withdraws all collateral from the Bitmor Lending Pool on behalf of an LSA
     * @dev Uses MAX_U256 to withdraw the entire aToken balance. Executes withdrawal
     * through the LSA's execute function to maintain proper accounting.
     *
     * ## Execution Flow
     * 1. Encodes withdraw call with MAX_U256 amount
     * 2. LSA executes the call on Bitmor Pool
     * 3. Collateral is transferred to the specified recipient
     * 4. Returns actual amount withdrawn (decoded from call result)
     *
     * @param bitmorPool Bitmor Lending Pool address
     * @param lsa The Loan Specific Address holding the collateral position
     * @param collateralAsset Collateral asset address (cbBTC)
     * @param recipient Address to receive the withdrawn collateral
     * @return amountWithdrawn The actual amount of collateral withdrawn
     */
    function withdrawCollateral(address lsa, address bitmorPool, address collateralAsset, address recipient)
        internal
        returns (uint256 amountWithdrawn)
    {
        amountWithdrawn = _withdrawMaxCollateral(lsa, bitmorPool, collateralAsset, recipient);
    }

    /**
     * @notice Redeems bvBTC shares from the BTC Vault via the LSA, returning cbBTC to `recipient`
     * @dev Executes the ERC-4626 `redeem` call through the LSA's `execute()` function.
     * Validates received assets against a minimum receivable computed from `slippage_sharesToAsset`.
     * @param lsa The Loan Specific Address holding the bvBTC shares
     * @param collateralAsset Address of the BTC Vault (bvBTC) contract
     * @param sharesAmount Amount of bvBTC shares to redeem
     * @param recipient Address to receive the underlying cbBTC assets
     * @param slippage_sharesToAsset Acceptable slippage in basis points for shares-to-asset conversion
     * @return assetsReceived Actual amount of cbBTC assets received from the redemption
     */
    function redeemBTC(
        address lsa,
        address collateralAsset,
        uint256 sharesAmount,
        address recipient,
        uint256 slippage_sharesToAsset
    ) internal returns (uint256 assetsReceived) {
        assetsReceived = _redeemBTC(lsa, collateralAsset, sharesAmount, recipient, slippage_sharesToAsset);
    }

    /**
     * @notice Claims all remaining collateral from the Bitmor Lending Pool and redeems it to the `borrower`
     * @dev Used after liquidation/completion to return leftover collateral.
     * Reverts if the LSA still has outstanding variable debt.
     * Withdraws all aToken collateral to the LSA, then redeems bvBTC shares to the borrower.
     * @param lsa The Loan Specific Address holding the collateral position
     * @param bitmorPool Bitmor Lending Pool address
     * @param collateralAsset Address of the BTC Vault (bvBTC) contract
     * @param debtAsset Address of the debt asset (USDC) for debt balance check
     * @param borrower Address of the loan borrower to receive the collateral
     * @param slippage_sharesToAsset Acceptable slippage in basis points for shares-to-asset conversion
     */
    function claimRemainingCollateral(
        address lsa,
        address bitmorPool,
        address collateralAsset,
        address debtAsset,
        address borrower,
        uint256 slippage_sharesToAsset
    ) internal {
        /// @dev Revert if the LSA still has outstanding variable debt
        if (bitmorPool.getVDTTokenAmount(debtAsset, lsa) != 0) {
            revert Errors.LSALogic__OutstandingDebtExists();
        }

        /// @dev Check if there is any collateral to claim
        if (bitmorPool.getATokenAmount(collateralAsset, lsa) == 0) return;

        /// @dev Withdraw all the collateral, `bvBTC` shares from the BLP to the LSA.
        _withdrawMaxCollateral(lsa, bitmorPool, collateralAsset, lsa);

        /// @dev Calculate the maximum redeemable amount of `bvBTC` shares from the `bvBTC` vault.
        uint256 maxRedeemable = collateralAsset.maxRedeem(lsa);

        /// @dev Guard: nothing to redeem (e.g., vault paused or zero shares after withdrawal)
        if (maxRedeemable == 0) return;

        /// @dev Redeem all the `bvBTC` shares from the `bvBTC` vault to the `borrower`.
        _redeemBTC(lsa, collateralAsset, maxRedeemable, borrower, slippage_sharesToAsset);
    }

    /// @dev Withdraws all collateral from the Bitmor Lending Pool via the LSA using `MAX_U256`.
    function _withdrawMaxCollateral(address lsa, address bitmorPool, address collateralAsset, address recipient)
        private
        returns (uint256 amountWithdrawn)
    {
        bytes memory withdrawData =
            abi.encodeWithSelector(ILendingPool.withdraw.selector, collateralAsset, MAX_U256, recipient);

        bytes memory result = ILoanVault(lsa).execute(bitmorPool, withdrawData);

        // Decode the actual amount withdrawn
        amountWithdrawn = abi.decode(result, (uint256));
    }

    /// @dev Redeems bvBTC shares via the LSA, validates received assets against slippage tolerance.
    function _redeemBTC(
        address lsa,
        address collateralAsset,
        uint256 sharesAmount,
        address recipient,
        uint256 slippage_sharesToAsset
    ) private returns (uint256 assetsReceived) {
        uint256 estimatedReceivable = collateralAsset.convertToAssets(sharesAmount);

        uint256 minimumReceivable =
            estimatedReceivable.mulDiv(BASIS_POINT_SCALE - slippage_sharesToAsset, BASIS_POINT_SCALE);

        bytes memory redeemData = abi.encodeWithSelector(ERC4626.redeem.selector, sharesAmount, recipient, lsa);

        bytes memory result = ILoanVault(lsa).execute(collateralAsset, redeemData);

        // Decode the actual amount redeemed.
        assetsReceived = abi.decode(result, (uint256));

        if (assetsReceived < minimumReceivable) {
            revert Errors.SlippageExceededWhileConvertingToAssets();
        }
    }
}
