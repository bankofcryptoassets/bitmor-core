// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {SafeERC20} from '../../../dependencies/openzeppelin/contracts/SafeERC20.sol';
import {IERC20} from '../../../dependencies/openzeppelin/contracts/IERC20.sol';
import {ILendingPool} from '../../../interfaces/ILendingPool.sol';
import {DataTypes} from '../../../protocol/libraries/types/DataTypes.sol';

/**
 * @title AaveV2InteractionLogic
 * @notice Handles deposits and borrows on Aave V2 lending pool
 */
library AaveV2InteractionLogic {
  using SafeERC20 for IERC20;

  /**
   * @notice Deposits collateral to Aave V2 on behalf of LSA
   * @dev LSA receives aTokens (acbBTC), Protocol holds cbBTC before deposit
   * @param aaveV2Pool Aave V2 lending pool address
   * @param asset Collateral asset (cbBTC)
   * @param amount Amount to deposit (8 decimals)
   * @param onBehalfOf LSA address that receives aTokens
   */
  function depositCollateral(
    address aaveV2Pool,
    address asset,
    uint256 amount,
    address onBehalfOf
  ) internal {
    require(amount > 0, 'AaveV2InteractionLogic: invalid deposit amount');
    require(onBehalfOf != address(0), 'AaveV2InteractionLogic: invalid onBehalfOf');

    // Approve Aave V2 pool to spend asset
    IERC20(asset).safeApprove(aaveV2Pool, amount);

    ILendingPool(aaveV2Pool).deposit(asset, amount, onBehalfOf, 0);
  }

  /**
   * @notice Borrows debt from Aave V2 on behalf of LSA
   * @dev Protocol receives USDC, LSA receives variable debt tokens
   * @param aaveV2Pool Aave V2 lending pool address
   * @param asset Debt asset (USDC)
   * @param amount Amount to borrow (6 decimals)
   * @param onBehalfOf LSA address that receives debt tokens
   */
  function borrowDebt(
    address aaveV2Pool,
    address asset,
    uint256 amount,
    address onBehalfOf
  ) internal {
    require(amount > 0, 'AaveV2InteractionLogic: invalid borrow amount');
    require(onBehalfOf != address(0), 'AaveV2InteractionLogic: invalid onBehalfOf');

    // Borrow from Aave V2 - onBehalfOf receives debt, caller receives USDC
    ILendingPool(aaveV2Pool).borrow(asset, amount, 2, 0, onBehalfOf);
  }

  /**
   * @notice Retrieves aToken address for given asset
   * @dev Used to get acbBTC address for collateral locking
   * @param aaveV2Pool Aave V2 lending pool address
   * @param asset Underlying asset (cbBTC)
   * @return aToken address (acbBTC)
   */
  function getATokenAddress(address aaveV2Pool, address asset) internal view returns (address) {
    DataTypes.ReserveData memory reserveData = ILendingPool(aaveV2Pool).getReserveData(asset);
    address aToken = reserveData.aTokenAddress;

    require(aToken != address(0), 'AaveV2InteractionLogic: invalid aToken');
    return aToken;
  }
}
