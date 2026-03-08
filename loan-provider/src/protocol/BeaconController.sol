// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IBeaconController} from "@bitmor/interfaces/IBeaconController.sol";

/**
 * @title BeaconController
 * @author Bitmor Protocol
 * @notice AccessManaged wrapper around UpgradeableBeacon for LoanVault upgrades
 * @dev Bridges Ownable-based UpgradeableBeacon with AccessManager role system.
 * The UpgradeableBeacon uses `onlyOwner` for `upgradeTo()`, so this controller
 * owns the beacon and gates upgrades through the AccessManager `restricted` modifier.
 *
 * @custom:security Requires appropriate role with delay via AccessManager
 */
contract BeaconController is IBeaconController, AccessManaged {
    /// @dev Stored as UpgradeableBeacon type for direct `.upgradeTo()` calls
    UpgradeableBeacon private immutable _beacon;

    /**
     * @notice Initializes the controller with an AccessManager and beacon
     * @param _manager The AccessManager contract address
     * @param beacon_ The UpgradeableBeacon contract address
     */
    constructor(address _manager, address beacon_) AccessManaged(_manager) {
        _beacon = UpgradeableBeacon(beacon_);
    }

    /// @inheritdoc IBeaconController
    function getBeacon() external view returns (address) {
        return address(_beacon);
    }

    /**
     * @notice Upgrades the LoanVault implementation across all beacon proxies
     * @param newImplementation Address of the new LoanVault implementation
     * @custom:access Requires appropriate role via AccessManager
     */
    function upgradeBeacon(address newImplementation) external restricted {
        _beacon.upgradeTo(newImplementation);
    }
}
