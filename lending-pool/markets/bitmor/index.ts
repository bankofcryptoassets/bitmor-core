import { eBaseNetwork, eEthereumNetwork, IBitmorConfiguration } from '../../helpers/types.js';
import { BitmorCommonsConfig } from './commons.js';
import { strategyUSDC, strategyBVBTC } from './reservesConfigs.js';
import sepoliaBUSDC from '../../deployments/sepolia-busdc.json';

export const BitmorConfig: IBitmorConfiguration = {
  ...BitmorCommonsConfig,
  MarketId: 'Bitmor Lending Market',
  ProviderId: 100,
  ReservesConfig: {
    bUSDC: strategyUSDC,
    bvBTC: strategyBVBTC,
  },
  ReserveAssets: {
    [eBaseNetwork.base]: {
      bUSDC: '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913',
      bvBTC: '', // To be populated from loan-provider deployment
    },
    [eBaseNetwork.sepolia]: {
      bUSDC: sepoliaBUSDC.address,
      bvBTC: '', // To be populated from loan-provider deployment
    },
    // For hardhat/localhost, addresses are loaded dynamically from deployed-contracts.json
    // This will be populated at runtime by getParamPerNetwork
    [eEthereumNetwork.hardhat]: {},
  },
};

export default BitmorConfig;
