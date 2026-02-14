// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {HelperConfig} from "../HelperConfig.s.sol";

/// @title DeployBTCVault
/// @notice Deploys BTCVault which produces bvBTC (vault shares)
/// @dev BTCVault address IS bvBTC - the ERC-4626 share token used as collateral
contract DeployBTCVault is Script {
    function run() external returns (address btcVault) {
        // Read cbBTC from previous deployment (mock for local)
        address cbBTC = _getRequiredAddress("MockCbBTC", "DeployMockTokens.s.sol");

        // Read AccessManager from HelperConfig (consistent source)
        HelperConfig helperConfig = new HelperConfig();
        address accessManager = helperConfig.getAccessManager();
        require(accessManager != address(0), "DeployBTCVault: AccessManager not deployed");

        console2.log("=== Deploying BTCVault ===");
        console2.log("cbBTC (underlying):", cbBTC);
        console2.log("AccessManager:", accessManager);

        vm.startBroadcast();

        BTCVault vault = new BTCVault(cbBTC, accessManager);

        vm.stopBroadcast();

        btcVault = address(vault);

        console2.log("=== BTCVault Deployed ===");
        console2.log("BTCVault (bvBTC):", btcVault);
        console2.log("Name:", vault.name());
        console2.log("Symbol:", vault.symbol());

        return btcVault;
    }

    function _getRequiredAddress(string memory contractName, string memory scriptName)
        internal
        view
        returns (address)
    {
        string memory broadcastPath = string.concat(
            vm.projectRoot(), "/broadcast/", scriptName, "/", vm.toString(block.chainid), "/run-latest.json"
        );

        try vm.readFile(broadcastPath) returns (string memory) {
            address addr = DevOpsTools.get_most_recent_deployment(contractName, block.chainid);
            require(addr != address(0), string.concat(contractName, " not deployed"));
            return addr;
        } catch {
            revert(string.concat("Broadcast file not found for ", scriptName));
        }
    }
}
