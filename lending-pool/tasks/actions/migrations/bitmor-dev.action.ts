import { checkVerification } from "../../../helpers/etherscan-verification.js";
import { ConfigNames, getEmergencyAdmin, loadPoolConfig } from "../../../helpers/configuration.js";
import { printContracts } from "../../../helpers/misc-utils.js";
import { usingTenderly } from "../../../helpers/tenderly-utils.js";
import { getLendingPoolConfiguratorProxy } from "../../../helpers/contracts-getters.js";
import type { HardhatRuntimeEnvironment } from "hardhat/types/hre";

type Args = {
  verify: boolean;
  skipRegistry: boolean;
};

export default async function bitmorDevAction(
  { verify, skipRegistry }: Args,
  hre: HardhatRuntimeEnvironment
) {
  const POOL_NAME = ConfigNames.Bitmor;

  await hre.tasks.getTask('set-DRE').run({});

  if (verify) {
    checkVerification();
  }

  const conn = await hre.network.connect();
  const { ethers } = conn;

  console.log("Migration started\n");

  console.log("1. Deploy mock tokens");
  await hre.tasks.getTask('dev:deploy-bitmor-mock-tokens').run({ verify });

  console.log("2. Deploy address provider registry");
  await hre.tasks.getTask('full:deploy-address-provider-registry').run({ pool: POOL_NAME, verify });

  console.log("3. Deploy address provider");
  await hre.tasks.getTask('full:deploy-address-provider').run({ pool: POOL_NAME, skipRegistry, verify });

  console.log("4. Deploy lending pool");
  await hre.tasks.getTask('full:deploy-lending-pool').run({ pool: POOL_NAME, verify });

  console.log("5. Deploy oracles");
  await hre.tasks.getTask('full:deploy-oracles').run({ pool: POOL_NAME, verify });

  console.log("6. Deploy Data Provider");
  await hre.tasks.getTask('full:data-provider').run({ pool: POOL_NAME, verify });

  console.log("7. Deploy WETH Gateway");
  await hre.tasks.getTask('full-deploy-weth-gateway').run({ pool: POOL_NAME, verify });

  console.log("8. Initialize lending pool");
  await hre.tasks.getTask('dev:initialize-lending-pool').run({ verify, pool: POOL_NAME });

  console.log("\nFinished deployment");

  if (verify) {
    printContracts();
    console.log("10. Verifying contracts");
    await hre.tasks.getTask('verify:general').run({ all: true, pool: POOL_NAME });

    console.log("11. Verifying aTokens and debtTokens");
    await hre.tasks.getTask('verify:tokens').run({ pool: POOL_NAME });
  }

  if (usingTenderly()) {
    console.log("Tenderly Info");
    console.log("- Network", conn.networkName);

    const netCfg = (hre.config.networks as any)[conn.networkName];
    const url: string | undefined = netCfg?.url;

    if (url) {
      console.log("- RPC", url);

      const forkId = url.match(/\/fork\/([^/?#]+)/)?.[1];
      const devnetId = url.match(/\/devnet\/([^/?#]+)/)?.[1];

      if (forkId) console.log("- Fork", forkId);
      if (devnetId) console.log("- Devnet", devnetId);
    } else {
      console.log("- RPC", "(no url in hardhat config)");
    }
  }

  console.log("\nFinished migrations");
  printContracts();
}
