import { eBaseNetwork, IBitmorConfiguration } from '../../helpers/types';
import { BitmorCommonsConfig } from './commons';
import { strategyUSDC, strategyCBBTC } from './reservesConfigs';
import { getDb } from '../../helpers/misc-utils';

// Helper function to get address from deployed-contracts.json with fallback
const getTokenAddress = (symbol: string, network: string, fallback: string) => {
  try {
    const db = getDb();
    return db.get(`${symbol}.${network}`).value()?.address || fallback;
  } catch {
    return fallback;
  }
};

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
      bUSDC: getTokenAddress('bUSDC', 'sepolia', '0x562937072309F8c929206a58e72732dFCA5b67D6'),
      bcbBTC: getTokenAddress('bcbBTC', 'sepolia', '0x39eF420a0467F8705D15065d4D542bC80ceA0356'),
    },
  },
};

export default BitmorConfig;
