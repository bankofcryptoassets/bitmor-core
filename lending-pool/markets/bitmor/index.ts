import { eBaseNetwork, eEthereumNetwork, IBitmorConfiguration } from '../../helpers/types.js';
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
    // For hardhat/localhost, addresses are loaded dynamically from deployed-contracts.json
    // This will be populated at runtime by getParamPerNetwork
    [eEthereumNetwork.hardhat]: {},
  },
};

export default BitmorConfig;
