// SPDX-License-Identifier: SEE LICENSE IN LICENSE
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
        address swapper;
        address premiumCollector;
        uint256 preClosureFee;
        uint256 gracePeriod;
    }

    function _deployLoan() internal {
        HelperConfig config = new HelperConfig();

        LoanDeployParams memory p;
        p.accessManager = config.getAccessManager();
        p.bitmorPool = config.getBitmorPool();
        p.aaveV3Pool = config.getAaveV3Pool();
        p.aaveAddressesProvider = config.getAaveAddressesProvider();
        p.oracle = config.getOracle();
        p.collateralAsset = config.getCollateralAsset();
        p.debtAsset = config.getDebtAsset();
        p.btc = config.getCbBTC();
        p.swapper = config.getSwapper();
        p.premiumCollector = config.getPremiumCollector();
        p.preClosureFee = config.getPreClosureFee();
        p.gracePeriod = config.getGracePeriod();

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
            p.swapper,
            p.premiumCollector,
            p.preClosureFee,
            p.gracePeriod
        );
        vm.stopBroadcast();
    }

    function run() public {
        _deployLoan();
    }
}
