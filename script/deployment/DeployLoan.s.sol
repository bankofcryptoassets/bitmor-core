// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {Script} from 'forge-std/Script.sol';
import {HelperConfig} from '../HelperConfig.s.sol';
import {Loan} from '@bitmor/loan/Loan.sol';

contract DeployLoan is Script {
  function _deployLoanUsingConfig(
    address bitmorPool,
    address aaveV3Pool,
    address oracle,
    address collateralAsset,
    address debtAsset,
    address swapAdapter,
    address zQuoter,
    uint256 maxLoanAmount
  ) internal {
    vm.startBroadcast();
    new Loan(
      bitmorPool,
      aaveV3Pool,
      oracle,
      collateralAsset,
      debtAsset,
      swapAdapter,
      zQuoter,
      maxLoanAmount
    );
    vm.stopBroadcast();
  }

  function _deployLoan() internal {
    HelperConfig config = new HelperConfig();
    (
      address bitmorPool,
      address aaveV3Pool,
      address oracle,
      address collateralAsset,
      address debtAsset,
      address swapAdapter,
      address zQuoter,
      uint256 maxLoanAmount
    ) = config.networkConfig();
    _deployLoanUsingConfig(
      bitmorPool,
      aaveV3Pool,
      oracle,
      collateralAsset,
      debtAsset,
      swapAdapter,
      zQuoter,
      maxLoanAmount
    );
  }

  function run() public {
    _deployLoan();
  }
}
