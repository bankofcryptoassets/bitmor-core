// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {Upgrades} from "@openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "@openzeppelin-foundry-upgrades/Options.sol";
import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/// @title UpgradeUUPS
/// @notice Schedules and executes UUPS proxy upgrades via AccessManager
/// @dev Two-step process: schedule() deploys new impl + schedules, execute() runs after 48h delay
/// @custom:security Requires UPGRADER role (48h delay) via AccessManager
contract UpgradeUUPS is Script {
    /// @notice Step 1: Deploy new implementation and schedule upgrade via AccessManager
    /// @dev Validates storage layout compatibility via OZ foundry-upgrades
    /// @param proxy The proxy address to upgrade
    /// @param newContractName Fully-qualified artifact name (e.g., "src/protocol/Loan.sol:LoanV2")
    /// @param initData Reinitializer calldata, or empty bytes "" for no reinit
    function schedule(address proxy, string memory newContractName, bytes memory initData) external {
        HelperConfig config = new HelperConfig();
        BitmorAccessManager manager = BitmorAccessManager(config.getAccessManager());

        vm.startBroadcast();

        // Deploy and validate new implementation (checks storage layout compatibility)
        Options memory opts;
        address newImpl = Upgrades.deployImplementation(newContractName, opts);
        console2.log("New implementation deployed:", newImpl);

        // Build upgradeToAndCall calldata
        bytes memory upgradeCall = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (newImpl, initData));

        // Schedule through AccessManager (48h delay + 10min buffer)
        uint48 when = uint48(block.timestamp + 2 days + 10 minutes);
        manager.schedule(proxy, upgradeCall, when);
        console2.log("Upgrade scheduled for proxy:", proxy);
        console2.log("Earliest execution:", when);

        vm.stopBroadcast();
    }

    /// @notice Step 2: Execute the scheduled upgrade after 48h delay
    /// @param proxy The proxy address to upgrade
    /// @param newImpl The new implementation address (from schedule step)
    /// @param initData Same `initData` passed to schedule
    function execute(address proxy, address newImpl, bytes memory initData) external {
        HelperConfig config = new HelperConfig();
        BitmorAccessManager manager = BitmorAccessManager(config.getAccessManager());

        vm.startBroadcast();

        bytes memory upgradeCall = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (newImpl, initData));
        manager.execute(proxy, upgradeCall);
        console2.log("Upgrade executed for proxy:", proxy);

        vm.stopBroadcast();
    }
}
