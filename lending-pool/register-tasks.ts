import { bitmorSepolia } from './tasks/migrations/bitmor.sepolia.js';
import { printConfigTask } from "./tasks/misc/print-config.js";
import { verifySc } from "./tasks/misc/verify-sc.js";
import { setDRETask } from "./tasks/misc/set-bre.js";

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

// const __filename = fileURLToPath(import.meta.url);
// const __dirname = path.dirname(__filename);

// const folders = ['misc', 'migrations', 'dev', 'full', 'verifications', 'deployments', 'helpers'];

// for (const folder of folders) {
//   const tasksPath = path.join(__dirname, 'tasks', folder);
//   if (fs.existsSync(tasksPath)) {
//     const files = fs.readdirSync(tasksPath).filter((pth) => pth.includes('.ts') || pth.includes('.js'));
//     for (const file of files) {
//       await import(`${tasksPath}/${file}`);
//     }
//   }
// }

export default [
  bitmorSepolia,
  printConfigTask,
  verifySc,
  setDRETask,
  deployAddressProviderRegistry,
  deployAddressProvider,
  deployLendingPool,
  deployOracles,
  deployDataProvider,
  deployWethGateway,
  initializeLendingPool,
  deployUiPoolDataProviderV2V3Task,
  deployUiIncentiveDataProviderV2V3Task,
];
