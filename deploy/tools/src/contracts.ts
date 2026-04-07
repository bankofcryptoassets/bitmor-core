/**
 * Maps broadcast contractName -> registry key path.
 *
 * Arrays handle duplicate names (e.g., multiple ERC1967Proxy deploys).
 * Keys are assigned to the Nth occurrence in deployment order.
 *
 * Dot-separated paths (e.g., "loanProvider.loan") map into the nested JSON.
 */

export interface PhaseMapping {
  [contractName: string]: string | string[];
}

export const PHASE1_LOCAL: PhaseMapping = {
  BitmorAccessManager: "loanProvider.accessManager",
  MockUSDC: "tokens.usdc",
  MockCbBTC: "tokens.cbBTC",
  MockChainlinkOracle: ["external.btcOracle", "external.usdcOracle"],
  // MockAaveV3Pool saves to BOTH aaveV3Pool and aaveAddressesProvider (same address, see DeployPhase1Local.s.sol:148-152)
  MockAaveV3Pool: ["external.aaveV3Pool", "external.aaveAddressesProvider"],
  BTCVault: "loanProvider.btcVaultImpl",
  ERC1967Proxy: ["loanProvider.btcVault"],
  // Ignored: HelperConfig (not a deployed contract we track)
};

export const PHASE1_TESTNET: PhaseMapping = {
  BitmorAccessManager: "loanProvider.accessManager",
  MockUSDC: "tokens.usdc",
  MockCbBTC: "tokens.cbBTC",
  MockChainlinkOracle: ["external.btcOracle", "external.usdcOracle"],
  // Testnet also deploys MockAaveV3Pool, saved to both keys (see DeployPhase1Testnet.s.sol:105,149)
  MockAaveV3Pool: ["external.aaveV3Pool", "external.aaveAddressesProvider"],
  BTCVault: "loanProvider.btcVaultImpl",
  ERC1967Proxy: ["loanProvider.btcVault"],
};

export const PHASE1_FORK: PhaseMapping = {
  BitmorAccessManager: "loanProvider.accessManager",
  BTCVault: "loanProvider.btcVaultImpl",
  ERC1967Proxy: ["loanProvider.btcVault"],
};

export const PHASE1_MAINNET: PhaseMapping = {
  BitmorAccessManager: "loanProvider.accessManager",
  BTCVault: "loanProvider.btcVaultImpl",
  ERC1967Proxy: ["loanProvider.btcVault"],
};

export const LIBRARIES: PhaseMapping = {
  LoanLogic: "loanProvider.libraries.loanLogic",
  RepayLogic: "loanProvider.libraries.repayLogic",
  CloseLoanLogic: "loanProvider.libraries.closeLoanLogic",
  FlashLoanLogic: "loanProvider.libraries.flashLoanLogic",
};

export const PHASE3_LOCAL: PhaseMapping = {
  USDCVault: "loanProvider.usdcVaultImpl",
  Loan: "loanProvider.loanImpl",
  AutoRepayment: "loanProvider.autoRepaymentImpl",
  BitmorAddressesProvider: "loanProvider.addressesProviderImpl",
  LoanVault: "loanProvider.loanVaultImpl",
  UpgradeableBeacon: "loanProvider.beacon",
  BeaconController: "loanProvider.beaconController",
  LoanVaultFactory: "loanProvider.loanVaultFactory",
  MockUniswapV4SwapAdapter: "loanProvider.swapper",
  AaveTokenizedStrategy: "loanProvider.aaveStrategy",
  USDCStrategy: "loanProvider.usdcStrategy",
  // ERC1967Proxy order must match actual deployment order in DeployPhase3Local.s.sol:
  // 1. USDCVault, 2. BitmorAddressesProvider, 3. Loan, 4. AutoRepayment
  ERC1967Proxy: [
    "loanProvider.usdcVault",
    "loanProvider.addressesProvider",
    "loanProvider.loan",
    "loanProvider.autoRepayment",
  ],
  // Ignored: HelperConfig, RolesData, MockAToken (not tracked in registry)
};

export const PHASE3_TESTNET: PhaseMapping = {
  ...PHASE3_LOCAL,
  // Testnet also deploys MockUniswapV4SwapAdapter
};

// Fork/mainnet do NOT deploy a swapper in Phase 3.
// Fork: swapper set via `bitmor-deploy set` after Phase 0 (swap-routers)
// Mainnet: swapper comes from HelperConfig constant, not registry
export const PHASE3_FORK: PhaseMapping = {
  USDCVault: "loanProvider.usdcVaultImpl",
  Loan: "loanProvider.loanImpl",
  AutoRepayment: "loanProvider.autoRepaymentImpl",
  BitmorAddressesProvider: "loanProvider.addressesProviderImpl",
  LoanVault: "loanProvider.loanVaultImpl",
  UpgradeableBeacon: "loanProvider.beacon",
  BeaconController: "loanProvider.beaconController",
  LoanVaultFactory: "loanProvider.loanVaultFactory",
  AaveTokenizedStrategy: "loanProvider.aaveStrategy",
  USDCStrategy: "loanProvider.usdcStrategy",
  // Same proxy order as PHASE3_LOCAL
  ERC1967Proxy: [
    "loanProvider.usdcVault",
    "loanProvider.addressesProvider",
    "loanProvider.loan",
    "loanProvider.autoRepayment",
  ],
};

export const PHASE3_MAINNET: PhaseMapping = {
  ...PHASE3_FORK,
  // Mainnet same as fork -- no swapper deployed in Phase 3
};

/**
 * Resolve phase+environment to the correct mapping.
 */
export function getMapping(phase: string, env: string): PhaseMapping {
  const key = `${phase}_${env}`.toUpperCase();
  const mappings: Record<string, PhaseMapping> = {
    PHASE1_LOCAL: PHASE1_LOCAL,
    PHASE1_TESTNET: PHASE1_TESTNET,
    PHASE1_FORK: PHASE1_FORK,
    PHASE1_MAINNET: PHASE1_MAINNET,
    LIBRARIES_LOCAL: LIBRARIES,
    LIBRARIES_TESTNET: LIBRARIES,
    LIBRARIES_FORK: LIBRARIES,
    LIBRARIES_MAINNET: LIBRARIES,
    PHASE3_LOCAL: PHASE3_LOCAL,
    PHASE3_TESTNET: PHASE3_TESTNET,
    PHASE3_FORK: PHASE3_FORK,
    PHASE3_MAINNET: PHASE3_MAINNET,
  };
  const mapping = mappings[key];
  if (!mapping) throw new Error(`Unknown phase/env combination: ${key}`);
  return mapping;
}

/**
 * Apply a phase mapping to a list of deployed contracts.
 * Returns a flat map of dot-paths -> addresses.
 *
 * Array semantics:
 * - Multiple occurrences of contractName in broadcast -> index-based (Nth occurrence -> Nth key)
 *   Example: MockChainlinkOracle deployed twice -> ["external.btcOracle", "external.usdcOracle"]
 * - Single occurrence of contractName -> fan-out to ALL keys in array
 *   Example: MockAaveV3Pool deployed once -> ["external.aaveV3Pool", "external.aaveAddressesProvider"]
 */
export function applyMapping(
  contracts: { name: string; address: string }[],
  mapping: PhaseMapping
): Record<string, string> {
  const result: Record<string, string> = {};

  // Pre-count occurrences to determine fan-out vs index-based behavior
  const occurrences: Record<string, number> = {};
  for (const c of contracts) {
    occurrences[c.name] = (occurrences[c.name] ?? 0) + 1;
  }

  const counters: Record<string, number> = {};

  for (const contract of contracts) {
    const target = mapping[contract.name];
    if (!target) continue;

    if (typeof target === "string") {
      result[target] = contract.address;
    } else if (Array.isArray(target)) {
      const count = occurrences[contract.name] ?? 0;
      if (count === 1) {
        // Single occurrence: fan-out to ALL keys
        for (const key of target) {
          result[key] = contract.address;
        }
      } else {
        // Multiple occurrences: index-based
        const idx = counters[contract.name] ?? 0;
        if (idx < target.length) {
          result[target[idx]] = contract.address;
        }
      }
      counters[contract.name] = (counters[contract.name] ?? 0) + 1;
    }
  }

  return result;
}
