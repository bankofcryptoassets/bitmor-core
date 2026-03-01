// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {Loan} from "@bitmor/protocol/Loan.sol";

contract DeployLoan is Script {
    struct LoanDeployParams {
        address accessManager;
        address bitmorPool;
        address aaveV3Pool;
        address aaveAddressesProvider;
        address oracle;
        address collateralAsset;
        address debtAsset;
        address btc;
        uint256 preClosureFee;
        uint256 gracePeriod;
    }

    function _deployLoanUsingConfig(LoanDeployParams memory p) internal {
        vm.startBroadcast();
        new Loan(
            p.accessManager,
            p.aaveV3Pool,
            p.aaveAddressesProvider,
            p.bitmorPool,
            p.oracle,
            p.collateralAsset,
            p.debtAsset,
            p.btc,
            p.preClosureFee,
            p.gracePeriod
        );
        vm.stopBroadcast();
    }

    function _deployLoan() internal {
        HelperConfig config = new HelperConfig();
        _deployLoanUsingConfig(
            LoanDeployParams({
                accessManager: config.getAccessManager(),
                bitmorPool: config.getBitmorPool(),
                aaveV3Pool: config.getAaveV3Pool(),
                aaveAddressesProvider: config.getAaveAddressesProvider(),
                oracle: config.getOracle(),
                collateralAsset: config.getCollateralAsset(),
                debtAsset: config.getDebtAsset(),
                btc: config.getCbBTC(),
                preClosureFee: config.getPreClosureFee(),
                gracePeriod: config.getGracePeriod()
            })
        );
    }

    function run() public {
        _deployLoan();
    }
}
