// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

import {ILendingPool} from '../../interfaces/ILendingPool.sol';
import {DataTypes} from '../types/DataTypes.sol';
import {ILoanVault} from '../../interfaces/ILoanVault.sol';

/**
 * @title LSALogic
 * @notice Handles LSA credit delegation (for Aave V2 borrowing)
 */
library LSALogic {
  /**
   * @notice Approve credit delegation on LSA before borrowing
   * @dev This MUST be called BEFORE Protocol borrows on behalf of LSA
   *      Uses the existing execute() function in LoanVault
   * @param lsa The LSA address
   * @param aaveV2Pool Aave V2 lending pool
   * @param debtAsset USDC address
   * @param amount Amount to delegate
   * @param delegatee Address that can borrow (Protocol address)
   */
  function approveCreditDelegation(
    address lsa,
    address aaveV2Pool,
    address debtAsset,
    uint256 amount,
    address delegatee
  ) internal {
    // Get variable debt token address from Aave V2
    DataTypes.ReserveData memory reserveData = ILendingPool(aaveV2Pool).getReserveData(debtAsset);
    address variableDebtToken = reserveData.variableDebtTokenAddress;

    require(variableDebtToken != address(0), 'LSALogic: invalid debt token');

    // Encode the approveDelegation call
    bytes memory data = abi.encodeWithSignature(
      'approveDelegation(address,uint256)',
      delegatee,
      amount
    );

    // Use LSA's execute() function to call variableDebtToken.approveDelegation()
    ILoanVault(lsa).execute(variableDebtToken, data);
  }
}
