// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {BitmorAccessManager} from "@bitmor/accessManager/BitmorAccessManager.sol";
import {IBeaconController} from "@bitmor/interfaces/IBeaconController.sol";
import {HelperConfig} from "../HelperConfig.s.sol";

/// @title UpgradeBeacon
/// @notice Schedules and executes LoanVault beacon upgrades via AccessManager
/// @dev Atomically upgrades ALL LoanVault proxy instances when beacon implementation changes
/// @custom:security Requires UPGRADER role (48h delay) via AccessManager
contract UpgradeBeacon is Script {
    /// @notice Step 1: Schedule beacon upgrade via AccessManager
    /// @param newLoanVaultImpl Address of the new LoanVault implementation contract
    function schedule(address newLoanVaultImpl) external {
        HelperConfig config = new HelperConfig();
        BitmorAccessManager manager = BitmorAccessManager(config.getAccessManager());
        address beaconController = config.getBeaconController();

        vm.startBroadcast();

        bytes memory call = abi.encodeCall(IBeaconController.upgradeBeacon, (newLoanVaultImpl));
        uint48 when = uint48(block.timestamp + 2 days + 10 minutes);
        manager.schedule(beaconController, call, when);

        console2.log("Beacon upgrade scheduled");
        console2.log("New impl:", newLoanVaultImpl);
        console2.log("BeaconController:", beaconController);
        console2.log("Earliest execution:", when);

        vm.stopBroadcast();
    }

    /// @notice Step 2: Execute the scheduled beacon upgrade after 48h delay
    /// @dev All existing LoanVault BeaconProxy instances are atomically upgraded
    /// @param newLoanVaultImpl Same address passed to schedule
    function execute(address newLoanVaultImpl) external {
        HelperConfig config = new HelperConfig();
        BitmorAccessManager manager = BitmorAccessManager(config.getAccessManager());
        address beaconController = config.getBeaconController();

        vm.startBroadcast();

        bytes memory call = abi.encodeCall(IBeaconController.upgradeBeacon, (newLoanVaultImpl));
        manager.execute(beaconController, call);

        console2.log("Beacon upgrade executed - all LoanVault proxies upgraded");

        vm.stopBroadcast();
    }
}
