// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {MockChainlinkOracle} from "../../test/mock/MockChainlinkOracle.sol";
import {DeploymentConstants} from "./DeploymentConstants.sol";

/// @title DeployMockOracles
/// @notice Deploys mock Chainlink oracles for BTC and USDC price feeds
contract DeployMockOracles is Script {
    function run() external returns (address btcOracle, address usdcOracle) {
        vm.startBroadcast();

        MockChainlinkOracle btc = new MockChainlinkOracle(
            DeploymentConstants.ORACLE_DECIMALS,
            DeploymentConstants.BTC_USD_PRICE,
            DeploymentConstants.BTC_USD_DESCRIPTION
        );

        MockChainlinkOracle usdc = new MockChainlinkOracle(
            DeploymentConstants.ORACLE_DECIMALS,
            DeploymentConstants.USDC_USD_PRICE,
            DeploymentConstants.USDC_USD_DESCRIPTION
        );

        vm.stopBroadcast();

        btcOracle = address(btc);
        usdcOracle = address(usdc);

        console2.log("=== Mock Oracles Deployed ===");
        console2.log("BTC Oracle:", btcOracle);
        console2.log("BTC Price:", uint256(DeploymentConstants.BTC_USD_PRICE));
        console2.log("USDC Oracle:", usdcOracle);
        console2.log("USDC Price:", uint256(DeploymentConstants.USDC_USD_PRICE));

        return (btcOracle, usdcOracle);
    }
}
