// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {USDCVault} from "@usdcVault/USDCVault.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {HelperConfig} from "../HelperConfig.s.sol";

/// @title DeployUSDCVault
/// @notice Deploys USDCVault - requires LendingPool to be deployed first (Phase 3)
/// @dev USDCVault needs AccessManager, USDC, and Bitmor LendingPool addresses
contract DeployUSDCVault is Script {
    function run() external returns (address usdcVault) {
        // Read USDC from previous deployment (mock for local)
        address usdc = _getRequiredAddress("MockUSDC", "DeployMockTokens.s.sol");

        // Read AccessManager and LendingPool from HelperConfig (consistent source)
        HelperConfig helperConfig = new HelperConfig();
        address accessManager = helperConfig.getAccessManager();
        require(accessManager != address(0), "DeployUSDCVault: AccessManager not deployed");

        address bitmorPool = helperConfig.getBitmorPool();
        require(bitmorPool != address(0), "DeployUSDCVault: LendingPool not deployed yet");

        console2.log("=== Deploying USDCVault ===");
        console2.log("AccessManager:", accessManager);
        console2.log("USDC (asset):", usdc);
        console2.log("Bitmor LendingPool:", bitmorPool);

        vm.startBroadcast();

        USDCVault vault = new USDCVault(accessManager, usdc, bitmorPool);

        vm.stopBroadcast();

        usdcVault = address(vault);

        console2.log("=== USDCVault Deployed ===");
        console2.log("USDCVault:", usdcVault);

        return usdcVault;
    }

    function _getRequiredAddress(string memory contractName, string memory scriptName) internal view returns (address) {
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
