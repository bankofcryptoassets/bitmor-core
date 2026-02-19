import { LendingPool } from '../../../../types/ethers-contracts/index.js';
import { ReserveData, UserReserveData } from './interfaces/index.js';
import {
  getLendingRateOracle,
  getIErc20Detailed,
  getMintableERC20,
  getAToken,
  getStableDebtToken,
  getVariableDebtToken,
} from '../../../../helpers/contracts-getters.js';
import { tEthereumAddress } from '../../../../helpers/types.js';
import BigNumber from "bignumber.js";
import { getDb, DRE } from '../../../../helpers/misc-utils.js';
import { getContractAddress } from '../../../../helpers/contracts-helpers.js';
import { AaveProtocolDataProvider } from '../../../../types/ethers-contracts/index.js';

export const getReserveData = async (
  helper: AaveProtocolDataProvider,
  reserve: tEthereumAddress
): Promise<ReserveData> => {
  const [reserveData, tokenAddresses, rateOracle, token] = await Promise.all([
    helper.getReserveData(reserve),
    helper.getReserveTokensAddresses(reserve),
    getLendingRateOracle(),
    getIErc20Detailed(reserve),
  ]);

  const stableDebtToken = await getStableDebtToken(tokenAddresses.stableDebtTokenAddress);
  const variableDebtToken = await getVariableDebtToken(tokenAddresses.variableDebtTokenAddress);

  const { 0: principalStableDebt } = await stableDebtToken.getSupplyData();
  const totalStableDebtLastUpdated = await stableDebtToken.getTotalSupplyLastUpdated();

  const scaledVariableDebt = await variableDebtToken.scaledTotalSupply();

  const rate = (await rateOracle.getMarketBorrowRate(reserve)).toString();
  const symbol = await token.symbol();
  const decimals = new BigNumber(await token.decimals());

  const totalLiquidity = new BigNumber(reserveData.availableLiquidity.toString())
    .plus(reserveData.totalStableDebt.toString())
    .plus(reserveData.totalVariableDebt.toString());

  const utilizationRate = new BigNumber(
    totalLiquidity.eq(0)
      ? 0
      : new BigNumber(reserveData.totalStableDebt.toString())
          .plus(reserveData.totalVariableDebt.toString())
          .rayDiv(totalLiquidity)
  );

  return {
    totalLiquidity,
    utilizationRate,
    availableLiquidity: new BigNumber(reserveData.availableLiquidity.toString()),
    totalStableDebt: new BigNumber(reserveData.totalStableDebt.toString()),
    totalVariableDebt: new BigNumber(reserveData.totalVariableDebt.toString()),
    liquidityRate: new BigNumber(reserveData.liquidityRate.toString()),
    variableBorrowRate: new BigNumber(reserveData.variableBorrowRate.toString()),
    stableBorrowRate: new BigNumber(reserveData.stableBorrowRate.toString()),
    averageStableBorrowRate: new BigNumber(reserveData.averageStableBorrowRate.toString()),
    liquidityIndex: new BigNumber(reserveData.liquidityIndex.toString()),
    variableBorrowIndex: new BigNumber(reserveData.variableBorrowIndex.toString()),
    lastUpdateTimestamp: new BigNumber(reserveData.lastUpdateTimestamp),
    totalStableDebtLastUpdated: new BigNumber(totalStableDebtLastUpdated),
    principalStableDebt: new BigNumber(principalStableDebt.toString()),
    scaledVariableDebt: new BigNumber(scaledVariableDebt.toString()),
    address: reserve,
    aTokenAddress: tokenAddresses.aTokenAddress,
    symbol,
    decimals,
    marketStableRate: new BigNumber(rate),
  };
};

export const getUserData = async (
  pool: LendingPool,
  helper: AaveProtocolDataProvider,
  reserve: string,
  user: tEthereumAddress,
  sender?: tEthereumAddress
): Promise<UserReserveData> => {
  const [userData, scaledATokenBalance] = await Promise.all([
    helper.getUserReserveData(reserve, user),
    getATokenUserData(reserve, user, helper),
  ]);

  const token = await getMintableERC20(reserve);
  const walletBalance = new BigNumber((await token.balanceOf(sender || user)).toString());

  return {
    scaledATokenBalance: new BigNumber(scaledATokenBalance),
    currentATokenBalance: new BigNumber(userData.currentATokenBalance.toString()),
    currentStableDebt: new BigNumber(userData.currentStableDebt.toString()),
    currentVariableDebt: new BigNumber(userData.currentVariableDebt.toString()),
    principalStableDebt: new BigNumber(userData.principalStableDebt.toString()),
    scaledVariableDebt: new BigNumber(userData.scaledVariableDebt.toString()),
    stableBorrowRate: new BigNumber(userData.stableBorrowRate.toString()),
    liquidityRate: new BigNumber(userData.liquidityRate.toString()),
    usageAsCollateralEnabled: userData.usageAsCollateralEnabled,
    stableRateLastUpdated: new BigNumber(userData.stableRateLastUpdated.toString()),
    walletBalance,
  };
};

export const getReserveAddressFromSymbol = async (symbol: string) => {
  const dbEntry = await getDb().get(`${symbol}.${DRE.network.networkName}`).value();

  if (!dbEntry) {
    throw `Could not find database entry for token ${symbol} in network ${DRE.network.networkName}`;
  }

  if (!dbEntry.address || dbEntry.address === '' || dbEntry.address === '0x') {
    throw `Invalid or missing address for token ${symbol} in network ${DRE.network.networkName}. Address: ${dbEntry.address}`;
  }

  // Directly return the address from the database entry instead of trying to instantiate and call getContractAddress
  return dbEntry.address;
};

const getATokenUserData = async (
  reserve: string,
  user: string,
  helpersContract: AaveProtocolDataProvider
) => {
  const aTokenAddress: string = (await helpersContract.getReserveTokensAddresses(reserve))
    .aTokenAddress;

  const aToken = await getAToken(aTokenAddress);

  const scaledBalance = await aToken.scaledBalanceOf(user);
  return scaledBalance.toString();
};

export const getReserveFactorFromData = (data: BigNumber): BigNumber => {
  // In Aave, reserve factor occupies 16 bits starting at bit 64:
  // reserveFactor = (data & ~RESERVE_FACTOR_MASK) >> 64
  // which is equivalent to: (data >> 64) & ((1 << 16) - 1)
  const SHIFT = new BigNumber(2).pow(64);    // 2^64
  const WIDTH = new BigNumber(2).pow(16);    // 2^16

  // Use BigNumber arithmetic instead of JS bitwise operators (which truncate to 32 bits).
  // floor(data / 2^64) % 2^16
  const shifted = data.dividedToIntegerBy(SHIFT);
  return shifted.mod(WIDTH);
};
