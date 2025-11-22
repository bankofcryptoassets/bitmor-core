// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {LoanVaultFactory} from "@bitmor/loan/LoanVaultFactory.sol";

contract DeployLoanVaultFactory is Script {
    HelperConfig config;

    function _deployLoanVaultFactoryUsingConfig(address implementation, address loan) internal {
        vm.broadcast();
        new LoanVaultFactory(implementation, loan);
    }

    function _deployLoanVaultFactory() internal {
        config = new HelperConfig();

        address implementation = config.getLoanVaultImplementation();
        address loan = config.getLoan();

        _deployLoanVaultFactoryUsingConfig(implementation, loan);
    }

    function run() public {
        _deployLoanVaultFactory();
    }
}
