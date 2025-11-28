// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {Loan} from "@bitmor/protocol/Loan.sol";

contract DeployLoan is Script {
    function _deployLoanUsingConfig(
        address bitmorPool,
        address aaveV3Pool,
        address aaveAddressesProvider,
        address oracle,
        address collateralAsset,
        address debtAsset,
        address swapAdapterWrapper,
        address zQuoter,
        address premiumCollector,
        uint256 preClosureFee,
        uint256 gracePeriod
    ) internal {
        vm.startBroadcast();
        new Loan(
            aaveV3Pool,
            aaveAddressesProvider,
            bitmorPool,
            oracle,
            collateralAsset,
            debtAsset,
            swapAdapterWrapper,
            zQuoter,
            premiumCollector,
            preClosureFee,
            gracePeriod
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
            address swapAdapterWrapper,
            address zQuoter,
            address premiumCollector,
            uint256 preClosureFee,
            uint256 gracePeriod
        ) = config.networkConfig();
        _deployLoanUsingConfig(
            bitmorPool,
            aaveV3Pool,
            aaveAddressesProvider,
            oracle,
            collateralAsset,
            debtAsset,
            swapAdapterWrapper,
            zQuoter,
            premiumCollector,
            preClosureFee,
            gracePeriod
        );
    }

    function run() public {
        _deployLoan();
    }
}
