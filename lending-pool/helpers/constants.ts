import BigNumber from "bignumber.js";

// ----------------
// MATH
// ----------------

export const PERCENTAGE_FACTOR = '10000';
export const HALF_PERCENTAGE = '5000';
export const WAD = Math.pow(10, 18).toString();
export const HALF_WAD = new BigNumber(WAD).multipliedBy(0.5).toString();
export const RAY = new BigNumber(10).exponentiatedBy(27).toFixed();
export const HALF_RAY = new BigNumber(RAY).multipliedBy(0.5).toFixed();
export const WAD_RAY_RATIO = Math.pow(10, 9).toString();
export const oneEther = new BigNumber(Math.pow(10, 18));
export const oneUsd = new BigNumber(Math.pow(10, 8));
export const oneRay = new BigNumber(Math.pow(10, 27));
export const MAX_UINT_AMOUNT =
  '115792089237316195423570985008687907853269984665640564039457584007913129639935';
export const ONE_YEAR = '31536000';
export const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
export const ONE_ADDRESS = '0x0000000000000000000000000000000000000001';
// ----------------
// PROTOCOL GLOBAL PARAMS
// ----------------
export const OPTIMAL_UTILIZATION_RATE = new BigNumber(0.8).times(RAY);
export const EXCESS_UTILIZATION_RATE = new BigNumber(0.2).times(RAY);
export const APPROVAL_AMOUNT_LENDING_POOL = '1000000000000000000000000000';
export const TOKEN_DISTRIBUTOR_PERCENTAGE_BASE = '10000';
export const MOCK_USD_PRICE_IN_WEI = '5848466240000000';
export const USD_ADDRESS = '0x10F7Fc1F91Ba351f9C629c5947AD69bD03C05b96';
export const AAVE_REFERRAL = '0';

export const MOCK_CHAINLINK_AGGREGATORS_PRICES = {
  // USD-based price feeds (8 decimals via oneUsd = 1e8)
  AAVE: oneUsd.multipliedBy('100').toFixed(),
  BAT: oneUsd.multipliedBy('0.50').toFixed(),
  BUSD: oneUsd.multipliedBy('1').toFixed(),
  DAI: oneUsd.multipliedBy('1').toFixed(),
  ENJ: oneUsd.multipliedBy('0.50').toFixed(),
  KNC: oneUsd.multipliedBy('1.80').toFixed(),
  LINK: oneUsd.multipliedBy('17').toFixed(),
  MANA: oneUsd.multipliedBy('0.50').toFixed(),
  MKR: oneUsd.multipliedBy('4300').toFixed(),
  REN: oneUsd.multipliedBy('0.10').toFixed(),
  SNX: oneUsd.multipliedBy('3').toFixed(),
  SUSD: oneUsd.multipliedBy('1').toFixed(),
  TUSD: oneUsd.multipliedBy('1').toFixed(),
  UNI: oneUsd.multipliedBy('9').toFixed(),
  USDC: oneUsd.multipliedBy('1').toFixed(),
  USDT: oneUsd.multipliedBy('1').toFixed(),
  WETH: oneUsd.multipliedBy('2500').toFixed(),
  WBTC: oneUsd.multipliedBy('100000').toFixed(),
  YFI: oneUsd.multipliedBy('38000').toFixed(),
  ZRX: oneUsd.multipliedBy('0.20').toFixed(),
  UniDAIWETH: oneUsd.multipliedBy('100').toFixed(),
  UniWBTCWETH: oneUsd.multipliedBy('100').toFixed(),
  UniAAVEWETH: oneUsd.multipliedBy('100').toFixed(),
  UniBATWETH: oneUsd.multipliedBy('100').toFixed(),
  UniDAIUSDC: oneUsd.multipliedBy('100').toFixed(),
  UniCRVWETH: oneUsd.multipliedBy('100').toFixed(),
  UniLINKWETH: oneUsd.multipliedBy('100').toFixed(),
  UniMKRWETH: oneUsd.multipliedBy('100').toFixed(),
  UniRENWETH: oneUsd.multipliedBy('100').toFixed(),
  UniSNXWETH: oneUsd.multipliedBy('100').toFixed(),
  UniUNIWETH: oneUsd.multipliedBy('100').toFixed(),
  UniUSDCWETH: oneUsd.multipliedBy('100').toFixed(),
  UniWBTCUSDC: oneUsd.multipliedBy('100').toFixed(),
  UniYFIWETH: oneUsd.multipliedBy('100').toFixed(),
  BptWBTCWETH: oneUsd.multipliedBy('100').toFixed(),
  BptBALWETH: oneUsd.multipliedBy('100').toFixed(),
  WMATIC: oneUsd.multipliedBy('0.50').toFixed(),
  STAKE: oneUsd.multipliedBy('5').toFixed(),
  xSUSHI: oneUsd.multipliedBy('10').toFixed(),
  WAVAX: oneUsd.multipliedBy('15').toFixed(),
  cbBTC: oneUsd.multipliedBy('100000').toFixed(),
  USD: oneUsd.toFixed(),
};

export const chainlinkAggregatorProxy = {
  main: '0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419',
  kovan: '0x9326BFA02ADD2366b30bacB125260Af641031331',
  matic: '0xAB594600376Ec9fD91F8e885dADF0CE036862dE0',
  mumbai: '0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada',
  avalanche: '0x0A77230d17318075983913bC2145DB16C7366156',
  fuji: '0x5498BB86BC934c8D34FDA08E81D444153d0D06aD',
  tenderly: '0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419',
  'arbitrum-rinkeby': '0x5f0423B1a6935dc5596e7A24d98532b67A0AeFd8',
  arbitrum: '0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612',
  rinkeby: '0x8A753747A1Fa494EC906cE90E9f37563A8AF630e',
  goerli: '0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e',
  sepolia: '0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165',
};

export const chainlinkEthUsdAggregatorProxy = {
  main: '0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419',
  kovan: '0x9326BFA02ADD2366b30bacB125260Af641031331',
  matic: '0xF9680D99D6C9589e2a93a78A04A279e509205945',
  mumbai: '0x0715A7794a1dc8e42615F059dD6e406A6594651A',
  avalanche: '0x976B3D034E162d8bD72D6b9C989d545b839003b0',
  fuji: '0x86d67c3D38D2bCeE722E601025C25a575021c6EA',
  tenderly: '0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419',
  'arbitrum-rinkeby': '0x5f0423B1a6935dc5596e7A24d98532b67A0AeFd8',
  arbitrum: '0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612',
  rinkeby: '0x8A753747A1Fa494EC906cE90E9f37563A8AF630e',
  goerli: '0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e',
  sepolia: '0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1',
};
