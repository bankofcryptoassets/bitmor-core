// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {ILendingPool} from "../../interfaces/ILendingPool.sol";
import {DataTypes} from "../types/DataTypes.sol";
import {ILoanVault} from "../../interfaces/ILoanVault.sol";

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
    /**
     * @dev Maximum uint256 value used for max withdrawal amounts
     */
    uint256 internal constant MAX_U256 = type(uint256).max;

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
    function withdrawCollateral(address bitmorPool, address lsa, address collateralAsset, address recipient)
        internal
        returns (uint256 amountWithdrawn)
    {
        bytes memory withdrawData =
            abi.encodeWithSignature("withdraw(address,uint256,address)", collateralAsset, MAX_U256, recipient);

        bytes memory result = ILoanVault(lsa).execute(bitmorPool, withdrawData);

        // Decode the actual amount withdrawn
        amountWithdrawn = abi.decode(result, (uint256));
    }
}
