import { bitmorSepolia } from './tasks/migrations/bitmor.sepolia.js';
import { bitmorDev } from './tasks/migrations/bitmor.dev.js';
import { printConfigTask } from "./tasks/misc/print-config.js";
import { verifySc } from "./tasks/misc/verify-sc.js";
import { setDRETask } from "./tasks/misc/set-bre.js";
import { deployBitmorMockTokensTask } from "./tasks/dev/deploy-bitmor-mock-tokens.js";
import { devInitializeLendingPoolTask } from "./tasks/dev/5_initialize.js";

// Import full deployment tasks
import { deployAddressProviderRegistry } from "./tasks/full/0_address_provider_registry.js";
import { deployAddressProvider } from "./tasks/full/1_address_provider.js";
import { deployLendingPool } from "./tasks/full/2_lending_pool.js";
import { deployOracles } from "./tasks/full/3_oracles.js";
import { deployDataProvider } from "./tasks/full/4_data-provider.js";
import { deployWethGateway } from "./tasks/full/5-deploy-wethGateWay.js";
import { initializeLendingPool } from "./tasks/full/6-initialize.js";

// Import UI helper deployment tasks
import { deployUiPoolDataProviderV2V3Task } from "./tasks/deployments/deploy-UiPoolDataProviderV2V3.js";
import { deployUiIncentiveDataProviderV2V3Task } from "./tasks/deployments/deploy-UiIncentiveDataProviderV2V3.js";
import { addMarketToRegistryTask } from "./tasks/deployments/add-market-to-registry-v3.js";

export default [
  bitmorSepolia,
  bitmorDev,
  printConfigTask,
  verifySc,
  setDRETask,
  deployBitmorMockTokensTask,
  devInitializeLendingPoolTask,
  deployAddressProviderRegistry,
  deployAddressProvider,
  deployLendingPool,
  deployOracles,
  deployDataProvider,
  deployWethGateway,
  initializeLendingPool,
  deployUiPoolDataProviderV2V3Task,
  deployUiIncentiveDataProviderV2V3Task,
  addMarketToRegistryTask,
];
