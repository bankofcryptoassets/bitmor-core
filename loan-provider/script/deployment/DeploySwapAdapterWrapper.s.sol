// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {UniswapV4SwapAdapterWrapper} from "../../src/adapters/UniswapV4SwapAdapterWrapper.sol";

contract DeploySwapAdapterWrapper is Script {
    HelperConfig config;

    function _deploySwapAdapterWrapperUsingConfigs(address _swapAdapter) internal {
        vm.broadcast();
        new UniswapV4SwapAdapterWrapper(_swapAdapter);
    }

    function _deploySwapAdapterWrapper() internal {
        config = new HelperConfig();
        _deploySwapAdapterWrapperUsingConfigs(config.getSwapAdapter());
    }

    function run() public {
        _deploySwapAdapterWrapper();
    }
}
