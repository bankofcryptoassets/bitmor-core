import { defineConfig } from "hardhat/config";
import hardhatToolboxMochaEthers from "@nomicfoundation/hardhat-toolbox-mocha-ethers";
import hardhatEthers from "@nomicfoundation/hardhat-ethers";
import hardhatMocha from "@nomicfoundation/hardhat-mocha";
import hardhatTypechain from "@nomicfoundation/hardhat-typechain";
import { accounts } from './test-wallets.js';
import { BUIDLEREVM_CHAINID } from './helpers/buidler-constants.js';

const UNLIMITED_BYTECODE_SIZE = process.env.UNLIMITED_BYTECODE_SIZE === 'true';
const DEFAULT_BLOCK_GAS_LIMIT = 8000000;

export default defineConfig({
  plugins: [ hardhatEthers, hardhatToolboxMochaEthers, hardhatMocha, hardhatTypechain],
  solidity: {
    compilers: [
      {
        version: '0.8.30',
        settings: {
          optimizer: { enabled: true, runs: 200 },
        },
      },
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
    hardhat: {
      type: 'edr-simulated',
      hardfork: 'berlin',
      blockGasLimit: DEFAULT_BLOCK_GAS_LIMIT,
      allowUnlimitedContractSize: UNLIMITED_BYTECODE_SIZE,
      chainId: BUIDLEREVM_CHAINID,
      accounts: accounts.map(({ secretKey, balance }: { secretKey: string; balance: string }) => ({
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
