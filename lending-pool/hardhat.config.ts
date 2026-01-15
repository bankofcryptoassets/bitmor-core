import { defineConfig } from "hardhat/config";
import hardhatToolboxMochaEthers from "@nomicfoundation/hardhat-toolbox-mocha-ethers";
import hardhatEthers from "@nomicfoundation/hardhat-ethers";
import hardhatMocha from "@nomicfoundation/hardhat-mocha";
import hardhatTypechain from "@nomicfoundation/hardhat-typechain";
import { accounts } from './test-wallets.js';
import { BUIDLEREVM_CHAINID } from './helpers/buidler-constants.js';
import { NETWORKS_RPC_URL, NETWORKS_DEFAULT_GAS } from './helper-hardhat-config.js';
import { eBaseNetwork } from './helpers/types.js';

const SKIP_LOAD = process.env.SKIP_LOAD === 'true';
const UNLIMITED_BYTECODE_SIZE = process.env.UNLIMITED_BYTECODE_SIZE === 'true';
const DEFAULT_BLOCK_GAS_LIMIT = 8000000;
const MNEMONIC = process.env.MNEMONIC || '';
const MNEMONIC_PATH = "m/44'/60'/0'/0";

// Import task registration
const tasks = SKIP_LOAD ? [] : (await import("./register-tasks.js")).default;

export default defineConfig({
  plugins: [hardhatEthers, hardhatToolboxMochaEthers, hardhatMocha, hardhatTypechain],
  tasks,
  solidity: {
    compilers: [
      {
        version: '0.6.12',
        settings: {
          optimizer: { enabled: true, runs: 200 },
          evmVersion: 'istanbul',
        },
      }
    ]
  },
  networks: {
    sepolia: {
      type: 'http',
      url: NETWORKS_RPC_URL[eBaseNetwork.sepolia],
      chainId: 84532,
      accounts: {
        mnemonic: MNEMONIC,
        path: MNEMONIC_PATH,
        initialIndex: 0,
        count: 20,
      },
    },
    localhost: {
      type: 'http',
      url: 'http://127.0.0.1:8545',
      chainId: BUIDLEREVM_CHAINID,
      timeout: 60000,
    },
    hardhat: {
      type: 'edr-simulated',
      hardfork: 'berlin',
      blockGasLimit: DEFAULT_BLOCK_GAS_LIMIT,
      allowUnlimitedContractSize: UNLIMITED_BYTECODE_SIZE,
      chainId: BUIDLEREVM_CHAINID,
      accounts: accounts.map(({ secretKey, balance }: { secretKey, balance: string }) => ({
        privateKey: secretKey,
        balance,
      })),
    },
    default: {
      type: 'edr-simulated',
      hardfork: 'berlin',
      blockGasLimit: DEFAULT_BLOCK_GAS_LIMIT,
      allowUnlimitedContractSize: UNLIMITED_BYTECODE_SIZE,
      chainId: BUIDLEREVM_CHAINID,
      accounts: accounts.map(({ secretKey, balance }) => ({
        privateKey: secretKey,
        balance,
      })),
    },
  },
  paths: {
    tests: "./test-suites"
  },
  typechain: {
    outDir: 'types/ethers-contracts',
  },
  test: {
    mocha: {
      timeout: 0,
    }
  }
});
