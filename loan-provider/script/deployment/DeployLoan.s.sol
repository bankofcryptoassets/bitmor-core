// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {Loan} from "@bitmor/protocol/Loan.sol";

contract DeployLoan is Script {
    function _deployLoanUsingConfig(
        address accessManager,
        address bitmorPool,
        address aaveV3Pool,
        address aaveAddressesProvider,
        address oracle,
        address collateralAsset,
        address debtAsset,
        address btc,
        address swapAdapterWrapper,
        address zQuoter,
        address premiumCollector,
        uint256 preClosureFee,
        uint256 gracePeriod
    ) internal {
        vm.startBroadcast();
        new Loan(
            accessManager,
            aaveV3Pool,
            aaveAddressesProvider,
            bitmorPool,
            oracle,
            collateralAsset,
            debtAsset,
            btc,
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
        _deployLoanUsingConfig(
            config.getAccessManager(),
            config.getBitmorPool(),
            config.getAaveV3Pool(),
            config.getAaveAddressesProvider(),
            config.getOracle(),
            config.getCollateralAsset(),
            config.getDebtAsset(),
            config.getCbBTC(),
            config.getSwapAdapterWrapper(),
            config.getZQuoter(),
            config.getPremiumCollector(),
            config.getPreClosureFee(),
            config.getGracePeriod()
        );
    }

    function run() public {
        _deployLoan();
    }
}
