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

  function withdrawCollateral(
    address bitmorPool,
    address lsa,
    address collateralAsset,
    address recipient
  ) internal returns (uint256 amountWithdrawn) {
    bytes memory withdrawData = abi.encodeWithSignature(
      'withdraw(address,uint256,address)',
      collateralAsset,
      MAX_U256,
      recipient
    );

    bytes memory result = ILoanVault(lsa).execute(bitmorPool, withdrawData);

    // Decode the actual amount withdrawn
    amountWithdrawn = abi.decode(result, (uint256));
  }
}
