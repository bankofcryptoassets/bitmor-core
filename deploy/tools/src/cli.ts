#!/usr/bin/env node
import { Command } from "commander";
import { readFileSync } from "node:fs";
import { resolve, join } from "node:path";
import { parseBroadcast } from "./broadcast.js";
import { applyMapping, getMapping } from "./contracts.js";
import { readRegistry, writeRegistry, mergeIntoRegistry, createEmptyRegistry } from "./registry.js";
import { parseLendingPool } from "./lending-pool.js";

const program = new Command();

function findRepoRoot(): string {
  // Walk up from cwd to find directory containing deploy/ and loan-provider/
  let dir = process.cwd();
  while (dir !== "/") {
    try {
      const pkg = resolve(dir, "loan-provider/foundry.toml");
      readFileSync(pkg);
      return dir;
    } catch {
      dir = resolve(dir, "..");
    }
  }
  throw new Error("Cannot find repo root (looking for loan-provider/foundry.toml)");
}

const CHAIN_NETWORKS: Record<string, string> = {
  "31337": "localhost",
  "31337-fork": "base-fork",
  "84532": "base-sepolia",
  "8453": "base",
};

program
  .name("bitmor-deploy")
  .description("Bitmor deployment registry CLI");

program
  .command("save")
  .description("Parse Forge broadcast and save to registry")
  .requiredOption("--chain <chainKey>", "Chain key (e.g., 31337, 84532, 31337-fork)")
  .requiredOption("--phase <phase>", "Deployment phase (phase1, libraries, phase3)")
  .requiredOption("--script <name>", "Forge script name (e.g., DeployPhase1Local)")
  .option("--env <env>", "Environment (local, testnet, fork, mainnet)", "local")
  .action((opts) => {
    const root = findRepoRoot();
    const deploymentsDir = join(root, "deployments");

    // For fork chains, broadcast uses the raw chain ID (31337), not "31337-fork"
    const rawChainId = opts.chain.replace("-fork", "");
    const broadcastPath = join(
      root,
      "loan-provider/broadcast",
      `${opts.script}.s.sol`,
      rawChainId,
      "run-latest.json"
    );

    console.log(`[bitmor-deploy] Reading broadcast: ${broadcastPath}`);
    const broadcastJson = JSON.parse(readFileSync(broadcastPath, "utf-8"));
    const broadcast = parseBroadcast(broadcastJson);

    const mapping = getMapping(opts.phase, opts.env);
    const addresses = applyMapping(broadcast.contracts, mapping);

    // Also map libraries if present
    for (const lib of broadcast.libraries) {
      const libMapping = getMapping("libraries", opts.env);
      if (libMapping[lib.name]) {
        addresses[libMapping[lib.name] as string] = lib.address;
      }
    }

    const existing = readRegistry(deploymentsDir, opts.chain);
    const network = CHAIN_NETWORKS[opts.chain] ?? "unknown";

    let updated;
    if (existing) {
      updated = mergeIntoRegistry(existing, addresses, broadcast.timestamp, broadcast.commit, broadcast.deployer);
    } else {
      const fresh = createEmptyRegistry(broadcast.chainId, network, broadcast.deployer);
      updated = mergeIntoRegistry(fresh, addresses, broadcast.timestamp, broadcast.commit);
    }

    writeRegistry(deploymentsDir, opts.chain, updated);

    const count = Object.keys(addresses).length;
    console.log(`[bitmor-deploy] Saved ${count} addresses to deployments/${opts.chain}/latest.json`);
  });

program
  .command("save-lp")
  .description("Parse lending-pool deployed-contracts.json and merge into registry")
  .requiredOption("--chain <chainKey>", "Chain key")
  .action((opts) => {
    const root = findRepoRoot();
    const deploymentsDir = join(root, "deployments");
    const lpPath = join(root, "lending-pool/deployed-contracts.json");

    const addresses = parseLendingPool(lpPath, opts.chain);

    const existing = readRegistry(deploymentsDir, opts.chain);
    if (!existing) throw new Error(`No registry for chain ${opts.chain}. Run 'save --phase phase1' first.`);

    const updated = mergeIntoRegistry(existing, addresses, Date.now(), existing.commit);
    writeRegistry(deploymentsDir, opts.chain, updated);

    const count = Object.keys(addresses).length;
    console.log(`[bitmor-deploy] Merged ${count} lending-pool addresses into deployments/${opts.chain}/latest.json`);
  });

program
  .command("save-swap")
  .description("Parse swap-routers/deployments.json and merge swapper address into registry")
  .requiredOption("--chain <chainKey>", "Chain key")
  .option("--swap-routers-dir <dir>", "Path to swap-routers directory")
  .action((opts) => {
    const root = findRepoRoot();
    const deploymentsDir = join(root, "deployments");
    const swapDir = opts.swapRoutersDir ?? join(root, "swap-routers");
    const swapJson = JSON.parse(readFileSync(join(swapDir, "deployments.json"), "utf-8"));

    // swap-routers uses raw chainId (31337), not "31337-fork"
    const rawChainId = opts.chain.replace("-fork", "");
    const addr = swapJson?.deployments?.[rawChainId]?.contracts?.uniswapV4Swapper;
    if (!addr) throw new Error(`uniswapV4Swapper not found in swap-routers/deployments.json for chain ${rawChainId}`);

    const network = CHAIN_NETWORKS[opts.chain] ?? "unknown";
    const existing = readRegistry(deploymentsDir, opts.chain)
      ?? createEmptyRegistry(parseInt(rawChainId) || 31337, network, "");

    const updated = mergeIntoRegistry(existing, { "loanProvider.swapper": addr }, Date.now(), existing.commit);
    writeRegistry(deploymentsDir, opts.chain, updated);
    console.log(`[bitmor-deploy] Set loanProvider.swapper = ${addr} in deployments/${opts.chain}/latest.json`);
  });

program
  .command("libraries")
  .description("Output --libraries flag for forge from registry")
  .requiredOption("--chain <chainKey>", "Chain key")
  .action((opts) => {
    const root = findRepoRoot();
    const deploymentsDir = join(root, "deployments");
    const reg = readRegistry(deploymentsDir, opts.chain);
    if (!reg) throw new Error(`No registry for chain ${opts.chain}`);

    const libs = reg.loanProvider?.libraries;
    if (!libs) throw new Error(`No libraries in registry for chain ${opts.chain}`);

    const flag = [
      `--libraries src/libraries/logic/LoanLogic.sol:LoanLogic:${libs.loanLogic}`,
      `--libraries src/libraries/logic/RepayLogic.sol:RepayLogic:${libs.repayLogic}`,
      `--libraries src/libraries/logic/CloseLoanLogic.sol:CloseLoanLogic:${libs.closeLoanLogic}`,
      `--libraries src/libraries/logic/FlashLoanLogic.sol:FlashLoanLogic:${libs.flashLoanLogic}`,
    ].join(" ");

    // Output to stdout (captured by shell scripts)
    process.stdout.write(flag);
  });

program
  .command("get")
  .description("Read a single address from registry")
  .requiredOption("--chain <chainKey>", "Chain key")
  .requiredOption("--key <dotPath>", "Dot-path key (e.g., loanProvider.loan)")
  .action((opts) => {
    const root = findRepoRoot();
    const deploymentsDir = join(root, "deployments");
    const reg = readRegistry(deploymentsDir, opts.chain);
    if (!reg) throw new Error(`No registry for chain ${opts.chain}`);

    const parts = opts.key.split(".");
    let current: any = reg;
    for (const part of parts) {
      current = current?.[part];
    }

    if (!current) throw new Error(`Key ${opts.key} not found in registry for chain ${opts.chain}`);
    process.stdout.write(current);
  });

program
  .command("set")
  .description("Set a single address in registry (for externally deployed contracts)")
  .requiredOption("--chain <chainKey>", "Chain key")
  .requiredOption("--key <dotPath>", "Dot-path key (e.g., loanProvider.swapper)")
  .requiredOption("--value <address>", "Address value")
  .action((opts) => {
    const root = findRepoRoot();
    const deploymentsDir = join(root, "deployments");
    const network = CHAIN_NETWORKS[opts.chain] ?? "unknown";

    // Create fresh registry if none exists (e.g., fork Phase 0 runs before Phase 1)
    const existing = readRegistry(deploymentsDir, opts.chain)
      ?? createEmptyRegistry(parseInt(opts.chain) || 31337, network, "");

    const updated = mergeIntoRegistry(existing, { [opts.key]: opts.value }, Date.now(), existing.commit);
    writeRegistry(deploymentsDir, opts.chain, updated);
    console.log(`[bitmor-deploy] Set ${opts.key} = ${opts.value} in deployments/${opts.chain}/latest.json`);
  });

program.parse();
