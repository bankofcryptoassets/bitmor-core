/**
 * Hardhat v3 Task Registry
 *
 * Purpose:
 * This file serves as the central registry for all Hardhat tasks in the project.
 * It was introduced during the migration from Hardhat v2 to Hardhat v3.
 *
 * Why it exists:
 * - Hardhat v2: Automatically discovered and loaded all task files from the tasks/ directory
 * - Hardhat v3: Requires explicit task registration for better control and ES module support
 *
 * How it works:
 * 1. Task definition files (e.g., tasks/full/1_address_provider.ts) export task instances
 * 2. This file imports all task exports and aggregates them into a single array
 * 3. hardhat.config.ts imports and registers this array via the `tasks` configuration option
 *
 */

// Migration tasks
import { bitmorSepolia } from './tasks/migrations/bitmor.sepolia.js';
import { bitmorDev } from './tasks/migrations/bitmor.dev.js';

// Utility tasks
import { printConfigTask } from "./tasks/misc/print-config.js";
import { verifySc } from "./tasks/misc/verify-sc.js";
import { setDRETask } from "./tasks/misc/set-bre.js";

// Development tasks
import { deployBitmorMockTokensTask } from "./tasks/dev/deploy-bitmor-mock-tokens.js";
import { devInitializeLendingPoolTask } from "./tasks/dev/5_initialize.js";

// Full deployment tasks
import { deployAddressProviderRegistry } from "./tasks/full/0_address_provider_registry.js";
import { deployAddressProvider } from "./tasks/full/1_address_provider.js";
import { deployLendingPool } from "./tasks/full/2_lending_pool.js";
import { deployOracles } from "./tasks/full/3_oracles.js";
import { deployDataProvider } from "./tasks/full/4_data-provider.js";
import { deployWethGateway } from "./tasks/full/5-deploy-wethGateWay.js";
import { initializeLendingPool } from "./tasks/full/6-initialize.js";

// UI helper deployment tasks
import { deployUiPoolDataProviderV2V3Task } from "./tasks/deployments/deploy-UiPoolDataProviderV2V3.js";
import { deployUiIncentiveDataProviderV2V3Task } from "./tasks/deployments/deploy-UiIncentiveDataProviderV2V3.js";
import { addMarketToRegistryTask } from "./tasks/deployments/add-market-to-registry-v3.js";

/**
 * All registered Hardhat tasks
 * This array is imported by hardhat.config.ts and registered with Hardhat
 */
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
