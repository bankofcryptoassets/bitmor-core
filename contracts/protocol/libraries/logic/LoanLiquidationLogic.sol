// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {SafeMath} from '../../../dependencies/openzeppelin/contracts/SafeMath.sol';
import {IERC20} from '../../../dependencies/openzeppelin/contracts/IERC20.sol';
import {PercentageMath} from '../math/PercentageMath.sol';
import {DataTypes} from '../types/DataTypes.sol';
import {IPriceOracleGetter} from '../../../interfaces/IPriceOracleGetter.sol';
import {ReserveConfiguration} from '../configuration/ReserveConfiguration.sol';
import {GenericLogic} from './GenericLogic.sol';

library LoanLiquidationLogic {
  using SafeMath for uint256;
  using PercentageMath for uint256;
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

  struct LiquidationVars {
    uint256 cbBTCDecimals;
    uint256 usdcDecimals;
    address usdcVariableDebtTokenAddress;
    uint256 cbBTCUnitPrice;
    uint256 usdcUnitPrice;
    uint256 collateralValueInUSD;
    uint256 currentDebtBalance;
    uint256 amountToBeDeducted;
    uint256 totalAmtToBeDeducted;
    uint256 amountToBeDeductedInUSD;
    uint256 remainingCollateralInUSD;
    uint256 debtBalanceAfter;
    uint256 guardAmount;
    uint256 guardAmountInUSD;
  }

  /**
   * @dev Calculates which type of Liquidation can be done for a user
   * It can return 0,1 and 2
   * 0 => No Liquidation
   * 1 => Full Liquidation in which case Liquidator can call `liquidationCall` function to liquidate complete position of the user
   * 2 => MicroLiquidate in which case Liquidator can `microLiquidationCall` function to micro liquidate user.
   * @param user The address of the LSA
   * @param reservesData Data of all the reserves
   * @param hf Health Factor of the user
   * @param reserves The list of the available reserves
   * @param oracle The price oracle address
   * @param bitmorLoan The Bitmor Protocol Loan provider address
   */
  function checkTypeOfLiquidation(
    address user,
    mapping(address => DataTypes.ReserveData) storage reservesData,
    uint256 hf,
    mapping(uint256 => address) storage reserves,
    address oracle,
    address bitmorLoan
  ) internal view returns (uint256) {
    // TODO: Have IBitmorLoan implemented.
    // DataTypes.LoanData memory loanData = bitmorLoan.getLoanByLSA(user);
    DataTypes.LoanData memory loanData = DataTypes.LoanData({
      borrower: address(0),
      depositAmount: 0,
      loanAmount: 0,
      collateralAmount: 0,
      estimatedMonthlyPayment: 0,
      duration: 0,
      createdAt: 0,
      insuranceID: 1,
      nextDueTimestamp: 0,
      lastDueTimestamp: 0,
      status: DataTypes.LoanStatus.Active
    });

    // TODO: Implement this function in the Loan Provider
    // uint256 bufferBPS = bitmorLoan.getLiquidationBufferBPS();
    uint256 bufferBPS = 50;

    // If user is uninsured AND HF < threshold → full liquidation
    if (!(loanData.insuranceID > 0) && !(hf >= GenericLogic.HEALTH_FACTOR_LIQUIDATION_THRESHOLD)) {
      return 1;
    }

    // If the EMI is not overdue → no liquidation
    if (!(loanData.nextDueTimestamp < block.timestamp)) {
      return 0;
    }

    // Working variables packed in a memory struct to avoid "stack too deep"
    LiquidationVars memory v;

    // reserves
    // TODO: Implement a constant variable to have the cbBTC reserve.
    (v.cbBTCDecimals, v.usdcDecimals, v.usdcVariableDebtTokenAddress) = _getDecimals(
      reservesData,
      reserves[0],
      reserves[1]
    );

    // TODO: confirm if the IPriceOracleGetter returns with the reserve address or the underlying asset address.
    // TODO: IPriceOracleGetter currently provides price in ETH we will require in USD.
    v.cbBTCUnitPrice = IPriceOracleGetter(oracle).getAssetPrice(reserves[0]);
    v.usdcUnitPrice = IPriceOracleGetter(oracle).getAssetPrice(reserves[1]);

    // collateral value in quote (USD if your oracle is USD)
    v.collateralValueInUSD = loanData.collateralAmount.mul(v.cbBTCUnitPrice).div(
      10 ** v.cbBTCDecimals
    );

    // current debt = balance of VARIABLE debt token
    v.currentDebtBalance = IERC20(v.usdcVariableDebtTokenAddress).balanceOf(user);

    // compute capped principal payment for this micro-liq
    v.amountToBeDeducted = _min(loanData.estimatedMonthlyPayment, v.currentDebtBalance);

    // total USDC leaving user’s position (principal paid + bonus to liquidator), but never exceed debt + bonus policy
    v.totalAmtToBeDeducted = v.amountToBeDeducted.add(v.amountToBeDeducted.percentMul(bufferBPS));

    // convert the outflow to USD (or quote)
    v.amountToBeDeductedInUSD = v.totalAmtToBeDeducted.mul(v.usdcUnitPrice).div(
      10 ** v.usdcDecimals
    );

    // If the collateral cannot even cover this micro-liq outflow → full liquidation
    if (v.collateralValueInUSD <= v.amountToBeDeductedInUSD) {
      return 1;
    }

    // remaining collateral value after selling BTC to cover (principal + bonus)
    v.remainingCollateralInUSD = v.collateralValueInUSD.sub(v.amountToBeDeductedInUSD);

    // new debt after paying ONLY the principal part
    v.debtBalanceAfter = v.currentDebtBalance.sub(v.amountToBeDeducted);

    // guard = debtAfter * (1 + bufferBPS)
    v.guardAmount = v.debtBalanceAfter.add(v.debtBalanceAfter.percentMul(bufferBPS));
    v.guardAmountInUSD = v.guardAmount.mul(v.usdcUnitPrice).div(10 ** v.usdcDecimals);

    if (v.remainingCollateralInUSD >= v.guardAmountInUSD) {
      // type 2 := micro-liquidation is sufficient
      return 2;
    } else {
      // full liquidation path — bonus based on remaining full debt
      return 1;
    }
  }

  function _min(uint256 a, uint256 b) private pure returns (uint256) {
    return a < b ? a : b;
  }

  function _getDecimals(
    mapping(address => DataTypes.ReserveData) storage reservesData,
    address cbBTCReserveAddress,
    address usdcReserveAddress
  ) internal view returns (uint256, uint256, address) {
    // reserveData
    DataTypes.ReserveData storage cbBTCReserve = reservesData[cbBTCReserveAddress];
    DataTypes.ReserveData storage usdcReserve = reservesData[usdcReserveAddress];

    uint256 cbBTCDecimals = cbBTCReserve.configuration.getDecimals();
    uint256 usdcDecimals = usdcReserve.configuration.getDecimals();

    return (cbBTCDecimals, usdcDecimals, usdcReserve.variableDebtTokenAddress);
  }
}
