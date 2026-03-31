import { checkVerification } from "../../../helpers/etherscan-verification.js";
import { ConfigNames, getEmergencyAdmin, loadPoolConfig } from "../../../helpers/configuration.js";
import { printContracts } from "../../../helpers/misc-utils.js";
import { usingTenderly } from "../../../helpers/tenderly-utils.js";
import { getLendingPoolConfiguratorProxy } from "../../../helpers/contracts-getters.js";
import type { HardhatRuntimeEnvironment } from "hardhat/types/hre";
import hre from "hardhat";

type Args = {
    verify: boolean;
    skipRegistry: boolean;
};

export default async function bitmorSepoliaAction(
    { verify, skipRegistry }: Args,
    hre: HardhatRuntimeEnvironment
) {
    const POOL_NAME = ConfigNames.Bitmor;

    await runTask(hre, "set-DRE", {});

    if (verify) {
        checkVerification();
    }
    const conn = await hre.network.connect();
    const { ethers } = conn;

    console.log("Migration started\n");

    console.log("0. Deploy address provider registry");
    await runTask(hre, "full:deploy-address-provider-registry", { pool: POOL_NAME, verify });

    console.log("1. Deploy address provider");
    await runTask(hre, "full:deploy-address-provider", { pool: POOL_NAME, skipRegistry, verify });

    console.log("2. Deploy lending pool");
    await runTask(hre, "full:deploy-lending-pool", { pool: POOL_NAME, verify });

    console.log("3. Deploy oracles");
    await runTask(hre, "full:deploy-oracles", { pool: POOL_NAME, verify });

    console.log("4. Deploy Data Provider");
    await runTask(hre, "full:data-provider", { pool: POOL_NAME, verify });

    // console.log("5. Deploy WETH Gateway");
    // await runTask(hre, "full-deploy-weth-gateway", { pool: POOL_NAME, verify });

    console.log("6. Initialize lending pool");
    await runTask(hre, "full:initialize-lending-pool", { pool: POOL_NAME, verify });

    // console.log("7. Deploy UI helpers");
    // await runTask(hre, "deploy-UiPoolDataProviderV2V3", { verify });
    // await runTask(hre, "deploy-UiIncentiveDataProviderV2V3", { verify });

    const poolConfig = loadPoolConfig(POOL_NAME);
    const emergencyAdmin = await ethers.getSigner(await getEmergencyAdmin(poolConfig));
    const poolConfigurator = await getLendingPoolConfiguratorProxy();
    await poolConfigurator.connect(emergencyAdmin).setPoolPause(false);

    console.log("Finished deployment, unpaused protocol");

    if (verify) {
        printContracts();
        console.log("8. Verifying contracts");
        await runTask(hre, "verify:general", { all: true, pool: POOL_NAME });

        console.log("9. Verifying aTokens and debtTokens");
        await runTask(hre, "verify:tokens", { pool: POOL_NAME });
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

/**
 * Helper for calling other tasks in Hardhat v3.
 *
 * Depending on your exact hardhat v3 minor version, the runner is exposed
 * via the task manager. Use whichever of these exists in your typings:
 * - hre.tasks.getTask("name").run(args, hre?)
 * - hre.tasks.getTask("name").run(args)
 */
async function runTask(hre: HardhatRuntimeEnvironment, name: string, args: any) {
    return hre.tasks.getTask(name).run(args ?? {});
}
