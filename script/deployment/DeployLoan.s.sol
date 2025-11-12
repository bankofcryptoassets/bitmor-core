// // SPDX-License-Identifier: SEE LICENSE IN LICENSE
// pragma solidity 0.8.30;

// import {Script} from 'forge-std/Script.sol';
// import {HelperConfig} from '../HelperConfig.s.sol';
// import {Loan} from '@bitmor/loan/Loan.sol';

// contract DeployLoan is Script {
//   function deployLoanUsingConfig() public {
//     vm.startBroadcast();
//     Loan loan = new Loan();
//     vm.stopBroadcast();
//   }

//   function deployLoan() public {
//     HelperConfig config = new HelperConfig();
//     HelperConfig.NetworkConfig networkConfig = config.networkConfig();

//     deployLoanUsingConfig();
//   }

//   function run() public {
//     deployLoan();
//   }
// }
