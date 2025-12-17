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
  baseLTVAsCollateral: '7000',
  liquidationThreshold: '7500',
  liquidationBonus: '10300', // 103% => 3% liquidation bonus
  borrowingEnabled: true,
  stableBorrowRateEnabled: false,
  reserveDecimals: '8',
  aTokenImpl: eContractid.AToken,
  reserveFactor: '2000',
};
