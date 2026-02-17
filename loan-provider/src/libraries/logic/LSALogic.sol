// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {ERC4626} from "@solady/tokens/ERC4626.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

import {ILendingPool} from "../../interfaces/ILendingPool.sol";
import {ILoanVault} from "../../interfaces/ILoanVault.sol";

import {DataTypes} from "../types/DataTypes.sol";

import {BTCVaultLogic} from "./BTCVaultLogic.sol";
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

        require(variableDebtToken != address(0), "LSALogic: invalid debt token");

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
        bytes memory withdrawData =
            abi.encodeWithSelector(ILendingPool.withdraw.selector, collateralAsset, MAX_U256, recipient);

        bytes memory result = ILoanVault(lsa).execute(bitmorPool, withdrawData);

        // Decode the actual amount withdrawn
        amountWithdrawn = abi.decode(result, (uint256));
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
