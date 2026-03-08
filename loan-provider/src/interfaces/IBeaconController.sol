// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IBeaconController
 * @author Bitmor Protocol
 * @notice Interface for the AccessManaged wrapper around UpgradeableBeacon
 */
interface IBeaconController {
    /// @notice Upgrades the LoanVault implementation for all beacon proxies
    /// @param newImplementation Address of the new LoanVault implementation
    function upgradeBeacon(address newImplementation) external;

    /// @notice Returns the beacon address
    function getBeacon() external view returns (address);
}
