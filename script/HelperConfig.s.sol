// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {stdJson} from 'forge-std/StdJson.sol';
import {Script} from 'forge-std/Script.sol';
import {DevOpsTools} from 'lib/foundry-devops/src/DevOpsTools.sol';
import {IPriceOracleGetter} from '@bitmor/interfaces/IPriceOracleGetter.sol';

contract HelperConfig is Script {
  using stdJson for string;
  struct NetworkConfig {
    address bitmorPool;
    address aaveV3Pool;
    address oracle;
    address collateralAsset;
    address debtAsset;
    address swapAdapter;
    address zQuoter;
    uint256 maxLoanAmount;
  }

  NetworkConfig public networkConfig;

  uint256 constant CHAIN_ID_BASE_SEPOLIA = 84532;
  // 1e6 is for USDC decimal places
  uint256 constant MAX_LOAN_AMOUNT_BASE_SEPOLIA = 70_000 * 1e6;
  address constant AAVE_V3_POOL_BASE_SEPOLIA = 0xcFc53C27C1b813066F22D2fa70C3D0b4CAa70b7B;
  address constant SWAP_ADAPTER_BASE_SEPOLIA = 0x913336CecD657bB7dA46548bcb1a967EecBEAC62;
  address constant ZQUOTER_BASE_SEPOLIA = address(0);

  constructor() {
    if (block.chainid == CHAIN_ID_BASE_SEPOLIA) {
      networkConfig = getBaseSepoliaNetworkConfig();
    }
  }

  function getBaseSepoliaNetworkConfig() public returns (NetworkConfig memory config) {
    config = NetworkConfig({
      bitmorPool: getBitmorPool(),
      aaveV3Pool: getAaveV3Pool(),
      oracle: getOracle(),
      collateralAsset: getCollateralAsset(),
      debtAsset: getDebtAsset(),
      swapAdapter: getSwapAdapter(),
      zQuoter: getZQuoter(),
      maxLoanAmount: getMaxLoanAmount()
    });
  }

  function getBitmorPool() public returns (address) {
    string memory contractName = 'LendingPool';
    return _readAddress(contractName);
  }

  function getAaveV3Pool() public returns (address) {
    if (block.chainid == CHAIN_ID_BASE_SEPOLIA) {
      return AAVE_V3_POOL_BASE_SEPOLIA;
    }
  }

  function getOracle() public returns (address) {
    string memory contractName = 'AaveOracle';
    return _readAddress(contractName);
  }

  function getCollateralAsset() public returns (address) {
    return _getAddress('MockCbBTC');
  }

  function getDebtAsset() public returns (address) {
    return _getAddress('MockUSDC');
  }

  function getSwapAdapter() public returns (address) {
    if (block.chainid == CHAIN_ID_BASE_SEPOLIA) {
      return SWAP_ADAPTER_BASE_SEPOLIA;
    }
  }

  function getZQuoter() public returns (address) {
    if (block.chainid == CHAIN_ID_BASE_SEPOLIA) {
      return ZQUOTER_BASE_SEPOLIA;
    }
  }

  function getMaxLoanAmount() public returns (uint256) {
    if (block.chainid == CHAIN_ID_BASE_SEPOLIA) {
      return MAX_LOAN_AMOUNT_BASE_SEPOLIA;
    }
  }

  function _getAddress(string memory contractName) internal returns (address) {
    return DevOpsTools.get_most_recent_deployment(contractName, block.chainid);
  }

  function _readAddress(string memory contractName) internal returns (address addr) {
    // Map current chain to the key used in deployed-contracts.json
    string memory network;
    if (block.chainid == CHAIN_ID_BASE_SEPOLIA) {
      // Your JSON uses "sepolia" for Base Sepolia deployments
      network = 'sepolia';
    } else if (block.chainid == 31337 || block.chainid == 1337) {
      network = 'hardhat';
    } else {
      revert('HelperConfig: unsupported chainid for deployed-contracts.json');
    }

    // Read the JSON file from repo root
    string memory path = string.concat(vm.projectRoot(), '/deployed-contracts.json');
    string memory json = vm.readFile(path);

    // Build jsonpath like: .LendingPool.sepolia.address
    string memory key = string.concat('.', contractName, '.', network, '.address');

    // Parse and return
    addr = json.readAddress(key);
    require(addr != address(0), 'HelperConfig: empty address in deployed-contracts.json');
  }
}
