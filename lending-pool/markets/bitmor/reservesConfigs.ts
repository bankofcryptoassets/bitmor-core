import { eContractid, IReserveParams } from '../../helpers/types';
import { rateStrategyUSDC, rateStrategyCBBTC } from './rateStrategies';

export const strategyUSDC: IReserveParams = {
  strategy: rateStrategyUSDC,
  baseLTVAsCollateral: '8000',
  liquidationThreshold: '8500',
  liquidationBonus: '10300', // 103% => 3% liquidation bonus
  borrowingEnabled: true,
  stableBorrowRateEnabled: false,
  reserveDecimals: '6',
  aTokenImpl: eContractid.AToken,
  reserveFactor: '1000',
};



export const strategyCBBTC: IReserveParams = {
  strategy: rateStrategyCBBTC,
  baseLTVAsCollateral: '9000', // Borrow can borrow upto 90% of the collateral value.
  liquidationThreshold: '9479', // Collateral Value * 94.79% > Borrowed Value
  liquidationBonus: '10500', // 105% => 5% liquidation bonus
  borrowingEnabled: false,
  stableBorrowRateEnabled: false,
  reserveDecimals: '8',
  aTokenImpl: eContractid.AToken,
  reserveFactor: '0000',
};
/// Protocol Fee (5 bps ) + Liquidation Bonus (500 bps)
/// LTV = 1 / (1+Protocol Fee + Liquidation bonus) = 1/(1+ 0.005 + 0.05) =   0.9478672986 ~ 9479 bps
