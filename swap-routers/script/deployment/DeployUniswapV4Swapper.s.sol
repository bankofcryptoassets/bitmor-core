// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {UniswapV4Swapper} from "../../src/uniswap/UniswapV4Swapper.sol";

/// @title DeployUniswapV4Swapper
/// @notice Deployment script for UniswapV4Swapper contract
contract DeployUniswapV4Swapper is Script {
    HelperConfig public config;

    /// @notice Deploy UniswapV4Swapper with addresses from HelperConfig
    function run() public returns (UniswapV4Swapper swapper) {
        config = new HelperConfig();

        // Get addresses from config
        address universalRouter = config.getUniversalRouter();
        address v4Quoter = config.getV4Quoter();

        // Get pool configuration
        uint24 fee = config.getPoolFee();
        int24 tickSpacing = config.getPoolTickSpacing();
        address hooks = config.getPoolHooks();

        // Validate addresses
        require(universalRouter != address(0), "Universal Router address is zero");

        console.log("=== Deploying UniswapV4Swapper ===");
        console.log("Network:", config.getCurrentNetworkName());
        console.log("Chain ID:", block.chainid);
        console.log("Universal Router:", universalRouter);
        console.log("V4 Quoter:", v4Quoter);
        console.log("Pool Fee:", fee);
        console.log("Tick Spacing:", uint24(tickSpacing));
        console.log("Hooks:", hooks);

        vm.startBroadcast();

        swapper = new UniswapV4Swapper(universalRouter, v4Quoter, fee, tickSpacing, hooks);

        vm.stopBroadcast();

        console.log("=== Deployment Complete ===");
        console.log("UniswapV4Swapper deployed at:", address(swapper));

        // Auto-save deployed address to deployments.json
        _saveDeployedAddress(address(swapper));

        return swapper;
    }

    /// @notice Saves deployed address to deployments.json
    function _saveDeployedAddress(address swapperAddress) internal {
        string memory path = string.concat(vm.projectRoot(), "/deployments.json");
        string memory jsonPath =
            string.concat(".deployments.", vm.toString(block.chainid), ".contracts.uniswapV4Swapper");

        vm.writeJson(vm.toString(swapperAddress), path, jsonPath);

        console.log("=== Address Saved to deployments.json ===");
    }

    /// @notice Deploy with custom addresses and pool config (for testing or override)
    function deployWithAddresses(
        address universalRouter,
        address v4Quoter,
        uint24 fee,
        int24 tickSpacing,
        address hooks
    ) public returns (UniswapV4Swapper swapper) {
        require(universalRouter != address(0), "Universal Router address is zero");

        console.log("=== Deploying UniswapV4Swapper (custom addresses) ===");
        console.log("Universal Router:", universalRouter);
        console.log("V4 Quoter:", v4Quoter);
        console.log("Pool Fee:", fee);
        console.log("Tick Spacing:", uint24(tickSpacing));
        console.log("Hooks:", hooks);

        vm.startBroadcast();

        swapper = new UniswapV4Swapper(universalRouter, v4Quoter, fee, tickSpacing, hooks);

        vm.stopBroadcast();

        console.log("UniswapV4Swapper deployed at:", address(swapper));

        // Auto-save deployed address to deployments.json
        _saveDeployedAddress(address(swapper));

        return swapper;
    }
}
