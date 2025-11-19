// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {DataTypes} from '../types/DataTypes.sol';
import {ILoan} from '../../interfaces/ILoan.sol';
import {Errors} from '../helpers/Errors.sol';
import {BitmorLendingPoolLogic} from './BitmorLendingPoolLogic.sol';
import {IERC20} from '../../dependencies/openzeppelin/IERC20.sol';
import {SafeERC20} from '../../dependencies/openzeppelin/SafeERC20.sol';
import {IPriceOracleGetter} from '../../interfaces/IPriceOracleGetter.sol';

library CloseLoanLogic {
  using SafeERC20 for IERC20;

  uint256 private constant PRICE_PRECISION = 1e8;
  uint256 private constant BASIS_POINTS = 100_00;

  function executeCloseLoanWithFlashLoan(
    DataTypes.CloseLoanWithFLContext memory ctx,
    DataTypes.CloseLoanWithFLParams memory params,
    DataTypes.LoanData storage loan
  ) internal {
    (uint256 totalCollateralAmt, uint256 totalDebtAmt) = BitmorLendingPoolLogic.getUserPositions(
      ctx.bitmorPool,
      params.lsa
    );

    uint256 collateralAssetPrice = IPriceOracleGetter(ctx.oracle).getAssetPrice(
      ctx.collateralAsset
    );
    uint256 debtAssetPrice = IPriceOracleGetter(ctx.oracle).getAssetPrice(ctx.debtAsset);

    uint256 collateralValueUSD = (totalCollateralAmt * collateralAssetPrice) / PRICE_PRECISION;
    uint256 debtValueUSD = (totalDebtAmt * debtAssetPrice) / PRICE_PRECISION;

    uint256 preClosureFee = (totalCollateralAmt * ctx.preClosureFeeBps) / BASIS_POINTS;

    uint256 flashLoanAmt;

    if (params.withdrawInCollateralAsset) {
      // TODO!: Flash loan amount for the required amount
    } else {
      // TODO!: Flash loan amount for all the collateral value
    }

    // TODO!: Get flash loan premium amount
    uint256 flashLoanPremium = 10;
  }
}
