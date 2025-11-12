// // SPDX-License-Identifier: SEE LICENSE IN LICENSE
// pragma solidity 0.8.30;

// import {Script} from 'forge-std/Script.sol';

// contract HelperConfig is Script {
//   struct NetworkConfig {
//     address bitmorPool;
//     address aaveV3Pool;
//     address aaveAddressProvider;
//     address collateralAsset;
//     address debtAsset;
//     address swapAdapter;
//     address zQuoter;
//     uint256 maxLoanAmount;
//   }

//   NetworkConfig public networkConfig;

//   uint256 constant CHAIN_ID_BASE_SEPOLIA = 84532;

//   constructor() {
//     if (block.chainId == CHAIN_ID_BASE_SEPOLIA) {
//       networkConfig = getBaseSepoliaNetworkConfig();
//     }
//   }

//   function getBaseSepoliaNetworkConfig() public returns (NetworkConfig config) {
//     config = NetworkConfig({bitmorPool: getBitmorPool(), aaveV3Pool: getAaveV3Pool()});
//   }
// }
