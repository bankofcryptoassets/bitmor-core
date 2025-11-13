// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {Script} from 'forge-std/Script.sol';
import {HelperConfig} from '../HelperConfig.s.sol';

contract AddressProvider_SetBitmorLoan is Script {
  HelperConfig config;

  function _setBitmorLoanWithConfig(address addressesProvider, address loan) internal {
    vm.broadcast();
    (bool success, ) = addressesProvider.call(
      abi.encodeWithSignature('setBitmorLoan(address)', loan)
    );
    require(success, 'ERR: SET BITMOR LOAN FAILED');
  }

  function _setBitmorLoan() internal {
    config = new HelperConfig();

    address addressesProvider = config.getAddressesProvider();
    address loan = config.getLoan();

    _setBitmorLoanWithConfig(addressesProvider, loan);
  }

  function run() public {
    _setBitmorLoan();
  }
}
