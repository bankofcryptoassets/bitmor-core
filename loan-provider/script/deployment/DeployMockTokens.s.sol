// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {Script} from 'forge-std/Script.sol';
import {console2} from 'forge-std/console2.sol';
import {MockUSDC, MockCbBTC} from '@bitmor/mocks/MintableERC20.sol';

contract DeployMockTokens is Script {
  function _deployMockTokens() internal {
    vm.startBroadcast();
    address usdc = address(new MockUSDC());
    address cbBTC = address(new MockCbBTC());
    vm.stopBroadcast();

    console2.log('Mock USDC', usdc);
    console2.log('Mock cbBTC', cbBTC);
  }

  function run() public {
    _deployMockTokens();
  }
}
