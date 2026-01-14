import { eBaseNetwork, IBitmorConfiguration } from '../../helpers/types.js';
import { BitmorCommonsConfig } from './commons.js';
import { strategyUSDC, strategyCBBTC } from './reservesConfigs.js';
import sepoliaBUSDC from '../../deployments/sepolia-busdc.json';
import sepoliaBcbBTC from '../../deployments/sepolia-bcbbtc.json';

export const BitmorConfig: IBitmorConfiguration = {
  ...BitmorCommonsConfig,
  MarketId: 'Bitmor Lending Market',
  ProviderId: 100,
  ReservesConfig: {
    bUSDC: strategyUSDC,
    bcbBTC: strategyCBBTC,
  },
  ReserveAssets: {
    [eBaseNetwork.base]: {},
    [eBaseNetwork.sepolia]: {
      bUSDC: sepoliaBUSDC.address,
      bcbBTC: sepoliaBcbBTC.address,
    },
  },
};

export default BitmorConfig;
