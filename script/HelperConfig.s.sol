// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {Script} from 'forge-std/Script.sol';

contract HelperConfig is Script {
  struct NetworkConfig {
    address bitmorPool;
    address aaveV3Pool;
    address aaveAddressProvider;
    address collateralAsset;
    address debtAsset;
    address swapAdapter;
    address zQuoter;
    uint256 maxLoanAmount;
  }

  NetworkConfig public config;

  function getNetworkConfig() public view returns (NetworkConfig config) {}
}
