// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {IPriceOracleGetter} from '../../../interfaces/IPriceOracleGetter.sol';
import {ILendingPoolAddressesProvider} from '../../../interfaces/ILendingPoolAddressesProvider.sol';
import {ILendingPool} from '../../../interfaces/ILendingPool.sol';
import {DataTypes} from '../../../protocol/libraries/types/DataTypes.sol';
import {SafeMath} from '../../../dependencies/openzeppelin/contracts/SafeMath.sol';
import {LoanMath} from './LoanMath.sol';

/**
 * @title LoanLogic
 * @notice Library for loan calculation logic
 * @dev Handles fetching prices and interest rates from Aave V2, delegates math to LoanMath
 */
library LoanLogic {
  using SafeMath for uint256;

  /**
   * @notice Calculates loan amount and monthly payment by fetching current rates from Aave V2
   * @dev Fetch oracle price for the assets
   * @param aaveV2Pool Aave V2 lending pool address
   * @param addressesProvider Aave V2 addresses provider for oracle access
   * @param collateralAsset cbBTC address
   * @param debtAsset USDC address
   * @param depositAmount User's USDC deposit (6 decimals)
   * @param maxLoanAmount Maximum allowed loan amount (6 decimals)
   * @param collateralAmount Desired cbBTC collateral (8 decimals)
   * @param duration Loan duration in months
   * @return exactLoanAmt Calculated loan amount in USDC (6 decimals)
   * @return monthlyPayAmt Estimated monthly payment (6 decimals)
   * @return interestRate Current Aave V2 variable borrow rate (27 decimals - ray)
   */
  function calculateLoanAmountAndMonthlyPayment(
    address aaveV2Pool,
    ILendingPoolAddressesProvider addressesProvider,
    address collateralAsset,
    address debtAsset,
    uint256 depositAmount,
    uint256 maxLoanAmount,
    uint256 collateralAmount,
    uint256 duration
  ) internal view returns (uint256 exactLoanAmt, uint256 monthlyPayAmt, uint256 interestRate) {
    // Get oracle prices
    IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());
    uint256 collateralPriceUSD = oracle.getAssetPrice(collateralAsset);
    uint256 debtPriceUSD = oracle.getAssetPrice(debtAsset);

    // Fetch current variable borrow rate from Aave V2 USDC reserve
    DataTypes.ReserveData memory reserveData = ILendingPool(aaveV2Pool).getReserveData(debtAsset);
    interestRate = reserveData.currentVariableBorrowRate;

    // Calculate loan amount and monthly payment using fetched rate
    (exactLoanAmt, monthlyPayAmt) = LoanMath.calculateLoanAmt(
      depositAmount,
      collateralAmount,
      collateralPriceUSD,
      debtPriceUSD,
      maxLoanAmount,
      interestRate,
      duration
    );

    return (exactLoanAmt, monthlyPayAmt, interestRate);
  }
}
