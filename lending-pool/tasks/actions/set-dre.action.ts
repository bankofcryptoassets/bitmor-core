import { DRE, setDRE } from "../../helpers/misc-utils.js";
import type { HardhatRuntimeEnvironment } from "hardhat/types/hre";

export default async function setDREAction(
  _args: Record<string, never>,
  hre: HardhatRuntimeEnvironment
) {
  // Only skip if fully initialized
  if ((DRE as any)?.ethers?.getSigners && (DRE as any)?.network?.networkName) return;

  // HH3: get the "connected network" object
  const conn = await hre.network.connect();
  const networkName = conn.networkName;

  const connEthers = (conn as any).ethers;
  if (!connEthers?.getSigners) {
    throw new Error(
      "No hardhat-ethers helpers found on hre.network.connect(). Ensure @nomicfoundation/hardhat-ethers is loaded in hardhat.config.ts"
    );
  }

  // Tenderly support (plugin may not have HH3 typings)
  if (networkName.includes("tenderly") || process.env.TENDERLY === "true") {
    console.log("- Setting up Tenderly provider");

    const tenderly = (hre as any).tenderly;
    const ethersAny = connEthers;

    if (!tenderly?.network || !ethersAny?.providers?.Web3Provider) {
      console.log(
        "- Tenderly integration not found on hre (plugin not installed / not HH3-compatible). Skipping."
      );
    } else {
      const net = tenderly.network();

      if (process.env.TENDERLY_FORK_ID && process.env.TENDERLY_HEAD_ID) {
        console.log("- Connecting to a Tenderly Fork");
        await net.setFork(process.env.TENDERLY_FORK_ID);
        await net.setHead(process.env.TENDERLY_HEAD_ID);
      } else {
        console.log("- Creating a new Tenderly Fork");
        await net.initializeFork();
      }

      const provider = new ethersAny.providers.Web3Provider(net);
      ethersAny.provider = provider;

      console.log("- Initialized Tenderly fork:");
      console.log("  - Fork: ", net.getFork?.());
      console.log("  - Head: ", net.getHead?.());
    }
  }

  console.log("- Environment");
  if (process.env.FORK) {
    console.log("  - Fork Mode activated at network: ", process.env.FORK);

    // HH3 types don't include `forking` on network configs; access defensively
    const maybeForkUrl =
      (hre.config.networks as any)?.hardhat?.forking?.url ??
      (hre.config.networks as any)?.default?.forking?.url;

    if (maybeForkUrl) {
      try {
        console.log("  - Provider URL:", String(maybeForkUrl).split("/")[2]);
      } catch {
        console.log("  - Provider URL:", maybeForkUrl);
      }
    } else {
      console.error(
        `[FORK][Error] Missing Provider URL for fork mode. Check './helper-hardhat-config.ts' or your networks config.`
      );
    }
  }

  console.log("  - Network :", networkName);

  // Build a DRE object that matches your existing helper expectations
  const dre = {
    ...(hre as any),
    network: conn,           // => has networkName + provider
    ethers: connEthers,      // => has getSigners/getContractFactory/provider
  };

  // Your existing helper that sets global DRE
  setDRE(dre);
  return dre;
}
