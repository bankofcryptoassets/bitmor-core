import { eBaseNetwork, IBitmorConfiguration } from '../../helpers/types';
import { BitmorCommonsConfig } from './commons';
import { strategyUSDC, strategyCBBTC } from './reservesConfigs';

export const BitmorConfig: IBitmorConfiguration = {
  ...BitmorCommonsConfig,
  MarketId: 'Bitmor Lending Market',
  ProviderId: 100,
  ReservesConfig: {
    USDC: strategyUSDC,
    cbBTC: strategyCBBTC,
  },
  ReserveAssets: {
    [eBaseNetwork.base]: {},
    [eBaseNetwork.sepolia]: {
      USDC: '0x562937072309F8c929206a58e72732dFCA5b67D6',
      cbBTC: '0x39eF420a0467F8705D15065d4D542bC80ceA0356',
    },
  },
};

export default BitmorConfig;
