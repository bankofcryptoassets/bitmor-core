// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {LoanVault} from "@bitmor/protocol/LoanVault.sol";

contract DeployLoanVault is Script {
    function _deployLoanVault() internal {
        vm.broadcast();
        new LoanVault();
    }

    function run() public {
        _deployLoanVault();
    }
}
