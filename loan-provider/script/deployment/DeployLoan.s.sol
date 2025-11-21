// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {Loan} from "@bitmor/loan/Loan.sol";

contract DeployLoan is Script {
    function _deployLoanUsingConfig(
        address bitmorPool,
        address aaveV3Pool,
        address aaveAddressesProvider,
        address oracle,
        address collateralAsset,
        address debtAsset,
        address swapAdapter,
        address zQuoter,
        address premiumCollector,
        uint256 preClosureFee
    ) internal {
        vm.startBroadcast();
        new Loan(
            aaveV3Pool,
            aaveAddressesProvider,
            bitmorPool,
            oracle,
            collateralAsset,
            debtAsset,
            swapAdapter,
            zQuoter,
            premiumCollector,
            preClosureFee
        );
        vm.stopBroadcast();
    }

    function _deployLoan() internal {
        HelperConfig config = new HelperConfig();
        (
            address bitmorPool,
            address aaveV3Pool,
            address aaveAddressesProvider,
            address oracle,
            address collateralAsset,
            address debtAsset,
            address swapAdapter,
            address zQuoter,
            address premiumCollector,
            uint256 preClosureFee
        ) = config.networkConfig();
        _deployLoanUsingConfig(
            bitmorPool,
            aaveV3Pool,
            aaveAddressesProvider,
            oracle,
            collateralAsset,
            debtAsset,
            swapAdapter,
            zQuoter,
            premiumCollector,
            preClosureFee
        );
    }

    function run() public {
        _deployLoan();
    }
}
