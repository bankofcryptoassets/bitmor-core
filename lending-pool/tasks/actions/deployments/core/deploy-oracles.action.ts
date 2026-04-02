import type { HardhatRuntimeEnvironment } from 'hardhat/types/hre';
import { getParamPerNetwork, getContractAddress } from '../../../../helpers/contracts-helpers.js';
import { deployAaveOracle, deployLendingRateOracle, deployPythPriceOracleGetter } from '../../../../helpers/contracts-deployments.js';
import { setInitialMarketRatesInRatesOracleByHelper } from '../../../../helpers/oracles-helpers.js';
import { ICommonConfiguration, eNetwork, SymbolMap } from '../../../../helpers/types.js';
import { waitForTx, notFalsyOrZeroAddress } from '../../../../helpers/misc-utils.js';
import {
  ConfigNames,
  loadPoolConfig,
  getGenesisPoolAdmin,
  getLendingRateOracles,
  getQuoteCurrency,
  getBcbBTCAddress,
  getBvBTCAddress,
  getUSDCAddress,
} from '../../../../helpers/configuration.js';
import {
  getAaveOracle,
  getLendingPoolAddressesProvider,
  getLendingRateOracle,
  getPairsTokenAggregator,
} from '../../../../helpers/contracts-getters.js';
import { AaveOracle, LendingRateOracle } from '../../../../types/ethers-contracts/index.js';

type Args = {
  verify: boolean;
  pool: string;
};

export default async function deployOraclesAction(
  { verify, pool }: Args,
  hre: HardhatRuntimeEnvironment
) {
  try {
    await hre.tasks.getTask('set-DRE').run({});

    // Validate pool name
    if (!pool || !Object.values(ConfigNames).includes(pool as ConfigNames)) {
      throw new Error(
        `Invalid --pool "${pool}". Supported: ${Object.values(ConfigNames).join(', ')}`
      );
    }

    const conn = await hre.network.connect();
    // Map localhost to hardhat for config lookups
    const network = (process.env.FORK || (conn.networkName === 'localhost' ? 'hardhat' : conn.networkName)) as eNetwork;
    const poolConfig = loadPoolConfig(pool as ConfigNames);
    const {
      ProtocolGlobalParams: { UsdAddress },
      ReserveAssets,
      FallbackOracle,
      ChainlinkAggregator,
    } = poolConfig as ICommonConfiguration;
    const lendingRateOracles = getLendingRateOracles(poolConfig);
    const addressesProvider = await getLendingPoolAddressesProvider();
    const admin = await getGenesisPoolAdmin(poolConfig);
    const aaveOracleAddress = getParamPerNetwork(poolConfig.AaveOracle, network);
    const lendingRateOracleAddress = getParamPerNetwork(poolConfig.LendingRateOracle, network);
    const fallbackOracleAddress = await getParamPerNetwork(FallbackOracle, network);
    let reserveAssets = await getParamPerNetwork(ReserveAssets, network);

    // For localhost/hardhat, dynamically load token addresses from deployed-contracts.json
    if (network === 'hardhat' && !process.env.FORK && Object.keys(reserveAssets).length === 0) {
      const { getDb } = await import('../../../../helpers/misc-utils.js');
      const db = getDb();
      const actualNetwork = conn.networkName; // Use actual network name for DB lookup
      const USDC = db.get(`USDC.${actualNetwork}`).value()?.address;
      const bcbBTC = db.get(`bcbBTC.${actualNetwork}`).value()?.address;
      if (USDC && bcbBTC) {
        reserveAssets = { USDC, bcbBTC };
      }
    }

    // Dynamically populate USDC address from loan-provider deployment
    if (reserveAssets['USDC'] === '') {
      try {
        const usdcAddress = await getUSDCAddress(poolConfig, network);
        reserveAssets = { ...reserveAssets, USDC: usdcAddress };
        console.log(`USDC address loaded from loan-provider: ${usdcAddress}`);
      } catch (error) {
        console.warn(`Could not load USDC address: ${error}`);
      }
    }

    // Dynamically populate bvBTC address from loan-provider deployment
    if (reserveAssets['bvBTC'] === '') {
      try {
        const bvBTCAddress = await getBvBTCAddress(poolConfig, network);
        reserveAssets = { ...reserveAssets, bvBTC: bvBTCAddress };
        console.log(`bvBTC address loaded from loan-provider: ${bvBTCAddress}`);
      } catch (error) {
        console.warn(`Could not load bvBTC address: ${error}`);
      }
    }

    const chainlinkAggregators = await getParamPerNetwork(ChainlinkAggregator, network);

    const tokensToWatch: SymbolMap<string> = {
      ...reserveAssets,
      USD: UsdAddress,
    };
    const [tokens, aggregators] = getPairsTokenAggregator(
      tokensToWatch,
      chainlinkAggregators,
      poolConfig.OracleQuoteCurrency
    );

    // --- Pyth fallback oracle ---
    const pythAddress = poolConfig.PythAddress
      ? await getParamPerNetwork(poolConfig.PythAddress, network)
      : undefined;

    let resolvedFallbackOracleAddress = fallbackOracleAddress;

    if (pythAddress && notFalsyOrZeroAddress(pythAddress)) {
      const pythFeedIds = poolConfig.PythPriceFeedIds
        ? await getParamPerNetwork(poolConfig.PythPriceFeedIds, network)
        : {};

      const bcbBTCAddress = await getBcbBTCAddress(poolConfig, network);
      const bvBTCAddress = await getBvBTCAddress(poolConfig, network);

      // Build parallel arrays of assets and their Pyth feed IDs.
      // IMPORTANT: Include cbBTC explicitly — AaveOracle prices bvBTC via s_btc (cbBTC).
      // If Chainlink for cbBTC goes stale, the fallback must have a cbBTC source too.
      const pythAssets: string[] = [];
      const pythFeeds: string[] = [];

      // 1. Map reserve asset symbols to addresses, matching against configured Pyth feed IDs
      const { USD, ...reserveAssetsOnly } = tokensToWatch;
      for (const [symbol, address] of Object.entries(reserveAssetsOnly)) {
        const feedId = pythFeedIds[symbol]
          || (symbol === 'bcbBTC' ? pythFeedIds['cbBTC'] : undefined);

        if (feedId && address) {
          pythAssets.push(address);
          pythFeeds.push(feedId);
        }
      }

      // 2. Ensure cbBTC (s_btc) has a Pyth source — needed for bvBTC fallback pricing
      //    AaveOracle.getAssetPrice(bvBTC) → _getAssetPrice(s_btc) → fallback needs cbBTC source
      if (pythFeedIds['cbBTC'] && !pythAssets.includes(bcbBTCAddress)) {
        pythAssets.push(bcbBTCAddress);
        pythFeeds.push(pythFeedIds['cbBTC']);
      }

      if (pythAssets.length > 0) {
        console.log('Deploying PythPriceOracleGetter as fallback oracle...');
        console.log('  Pyth contract: %s', pythAddress);
        console.log('  Assets: %s', pythAssets.join(', '));

        const pythOracle = await deployPythPriceOracleGetter(
          [
            pythAddress,
            pythAssets,
            pythFeeds,
            bcbBTCAddress,
            bvBTCAddress,
            await getQuoteCurrency(poolConfig),
            poolConfig.OracleQuoteUnit,
          ],
          verify
        );

        resolvedFallbackOracleAddress = getContractAddress(pythOracle);
        console.log('PythPriceOracleGetter deployed at: %s', resolvedFallbackOracleAddress);
      } else {
        console.log('Pyth address configured but no feed IDs matched reserve assets — skipping fallback');
      }
    }
    // --- End Pyth fallback oracle ---

    let aaveOracle: AaveOracle;
    let lendingRateOracle: LendingRateOracle;

    if (notFalsyOrZeroAddress(aaveOracleAddress)) {
      aaveOracle = await getAaveOracle(aaveOracleAddress);
      await waitForTx(await aaveOracle.setAssetSources(tokens, aggregators));

      const bcbBTCAddress = await getBcbBTCAddress(poolConfig, network);
      const bvBTCAddress = await getBvBTCAddress(poolConfig, network);

      await waitForTx(await aaveOracle.setBTC(bcbBTCAddress));
      await waitForTx(await aaveOracle.setbvBTC(bvBTCAddress));
    } else {
      const bcbBTCAddress = await getBcbBTCAddress(poolConfig, network);
      const bvBTCAddress = await getBvBTCAddress(poolConfig, network);

      aaveOracle = await deployAaveOracle(
        [
          tokens,
          aggregators,
          bcbBTCAddress,
          bvBTCAddress,
          resolvedFallbackOracleAddress,
          await getQuoteCurrency(poolConfig),
          poolConfig.OracleQuoteUnit,
        ],
        verify
      );
      await waitForTx(await aaveOracle.setAssetSources(tokens, aggregators));
    }

    if (notFalsyOrZeroAddress(lendingRateOracleAddress)) {
      lendingRateOracle = await getLendingRateOracle(lendingRateOracleAddress);
    } else {
      lendingRateOracle = await deployLendingRateOracle(verify);
      const { USD, ...tokensAddressesWithoutUsd } = tokensToWatch;
      await setInitialMarketRatesInRatesOracleByHelper(
        lendingRateOracles,
        tokensAddressesWithoutUsd,
        lendingRateOracle,
        admin
      );
    }

    console.log('Aave Oracle: %s', getContractAddress(aaveOracle));
    console.log('Lending Rate Oracle: %s', getContractAddress(lendingRateOracle));

    // Register the proxy price provider on the addressesProvider
    await waitForTx(await addressesProvider.setPriceOracle(getContractAddress(aaveOracle)));
    await waitForTx(await addressesProvider.setLendingRateOracle(getContractAddress(lendingRateOracle)));
  } catch (error) {
    const conn = await hre.network.connect();
    if (conn.networkName.includes('tenderly')) {
      const tenderlyAny = (hre as any).tenderly;
      const configAny = (hre.config as any).tenderly;
      if (tenderlyAny?.network && configAny?.username && configAny?.project) {
        try {
          const transactionLink = `https://dashboard.tenderly.co/${configAny.username}/${
            configAny.project
          }/fork/${tenderlyAny.network().getFork()}/simulation/${tenderlyAny.network().getHead()}`;
          console.error('Check tx error:', transactionLink);
        } catch (e) {
          // Ignore if tenderly network methods fail
        }
      }
    }
    throw error;
  }
}
