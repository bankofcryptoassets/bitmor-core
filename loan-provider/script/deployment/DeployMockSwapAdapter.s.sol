// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {MockUniswapV4SwapAdapter} from "../../test/mock/MockUniswapV4SwapAdapter.sol";

/**
 * @title DeployMockSwapAdapter
 * @notice Deploys the MockUniswapV4SwapAdapter for local testing
 * @dev Only used for local/test deployments, not for production
 */
contract DeployMockSwapAdapter is Script {
    HelperConfig config;

    function run() public {
        config = new HelperConfig();

        address oracle = config.getOracle();
        address btc = config.getCbBTC();
        address usdc = config.getDebtAsset();

        vm.broadcast();
        new MockUniswapV4SwapAdapter(oracle, btc, usdc);
    }
}
