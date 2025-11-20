// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {DataTypes} from '../types/DataTypes.sol';
import {ILoan} from '../../interfaces/ILoan.sol';
import {Errors} from '../helpers/Errors.sol';
import {BitmorLendingPoolLogic} from './BitmorLendingPoolLogic.sol';
import {IERC20} from '../../dependencies/openzeppelin/IERC20.sol';
import {IERC20Metadata} from '../../dependencies/openzeppelin/IERC20Metadata.sol';
import {SafeERC20} from '../../dependencies/openzeppelin/SafeERC20.sol';
import {IPriceOracleGetter} from '../../interfaces/IPriceOracleGetter.sol';
import {AavePoolLogic} from './AavePoolLogic.sol';

library CloseLoanLogic {
  using SafeERC20 for IERC20;

  uint256 private constant PRICE_PRECISION = 1e8;
  uint256 private constant BASIS_POINTS = 100_00;

  struct LocalVarsCloseLoan {
    uint256 totalCollateralUSD;
    uint256 totalDebtUSD;
    uint256 collateralAssetPrice;
    uint256 debtAssetPrice;
    uint256 collateralAssetDecimals;
    uint256 debtAssetDecimals;
    uint256 collateralAmt;
    uint256 preClosureFee;
    uint256 preClosureFeeUSD;
    uint256 debtAmt;
    uint256 flashLoanPremiumBps;
    uint256 flashLoanPremiumAmount;
    uint256 flashLoanPremiumAmountUSD;
    uint256 totalCollateralAmtToSwapUSD;
    uint256 totalCollateralAmtToSwap;
  }

  function executeCloseLoan(
    DataTypes.ExecuteCloseLoanContext memory ctx,
    DataTypes.ExecuteCloseLoanParams memory params,
    mapping(address => DataTypes.LoanData) storage loansByLSA
  ) internal {
    LocalVarsCloseLoan memory vars;

    if (params.lsa == address(0)) revert Errors.ZeroAddress();

    DataTypes.LoanData memory loan = loansByLSA[params.lsa];

    if (loan.borrower == address(0)) revert Errors.LoanDoesNotExists();

    (vars.totalCollateralUSD, vars.totalDebtUSD) = BitmorLendingPoolLogic.getUserPositions(
      ctx.bitmorPool,
      params.lsa
    );

    vars.collateralAssetPrice = IPriceOracleGetter(ctx.oracle).getAssetPrice(ctx.collateralAsset);
    vars.debtAssetPrice = IPriceOracleGetter(ctx.oracle).getAssetPrice(ctx.debtAsset);

    vars.collateralAssetDecimals = 10 ** (IERC20Metadata(ctx.collateralAsset).decimals());
    vars.debtAssetDecimals = 10 ** (IERC20Metadata(ctx.debtAsset).decimals());

    vars.collateralAmt = BitmorLendingPoolLogic.getATokenAmount(
      ctx.bitmorPool,
      ctx.collateralAsset,
      params.lsa
    );

    vars.preClosureFee = (vars.collateralAmt * ctx.preClosureFeeBps) / BASIS_POINTS;

    vars.preClosureFeeUSD =
      (vars.preClosureFee * vars.collateralAssetPrice) /
      vars.collateralAssetDecimals;

    vars.debtAmt = BitmorLendingPoolLogic.getVDTTokenAmount(
      ctx.bitmorPool,
      ctx.debtAsset,
      params.lsa
    );

    vars.flashLoanPremiumBps = AavePoolLogic.getFlashLoanPremium(ctx.aavePool);

    vars.flashLoanPremiumAmount = (vars.debtAmt * vars.flashLoanPremiumBps) / BASIS_POINTS;
    vars.flashLoanPremiumAmountUSD =
      (vars.flashLoanPremiumAmount * vars.debtAssetPrice) /
      vars.debtAssetDecimals;

    if (
      vars.preClosureFeeUSD + vars.flashLoanPremiumAmountUSD + vars.totalDebtUSD >=
      vars.totalCollateralUSD
    ) revert Errors.InsufficientCollateral();

    vars.totalCollateralAmtToSwapUSD = vars.flashLoanPremiumAmountUSD + vars.totalDebtUSD;

    if (params.withdrawInCollateralAsset) {
      vars.totalCollateralAmtToSwap =
        (vars.totalCollateralAmtToSwapUSD * vars.collateralAssetDecimals) /
        (vars.collateralAssetPrice);
    } else {
      vars.totalCollateralAmtToSwap = vars.collateralAmt - vars.preClosureFee;
    }

    bool initializingLoan = false;

    bytes memory flData = abi.encode(
      params.lsa,
      params.withdrawInCollateralAsset,
      vars.totalCollateralAmtToSwap,
      vars.preClosureFee
    );
    bytes memory paramsForFL = abi.encode(initializingLoan, flData);

    AavePoolLogic.executeFlashLoan(
      ctx.aavePool,
      address(this),
      ctx.debtAsset,
      vars.debtAmt,
      paramsForFL
    );

    emit ILoan.Loan__ClosedLoan(params.lsa);
  }
}
