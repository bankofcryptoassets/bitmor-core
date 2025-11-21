// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.30;

/**
 * @title IEscrow
 * @notice Interface for Escrow contract
 */
interface IEscrow {
    /**
     * @notice Lock collateral from LSA into Escrow
     * @param lsa LSA address
     * @param amount Amount to lock
     */
    function lockCollateral(address lsa, uint256 amount) external;

    /**
     * @notice Unlock collateral from Escrow back to LSA
     * @param lsa LSA address
     * @param amount Amount to unlock
     */
    function unlockCollateral(address lsa, uint256 amount) external;

    /**
     * @notice Get locked collateral amount for LSA
     * @param lsa LSA address
     * @return Locked amount
     */
    function getLockedAmount(address lsa) external view returns (uint256);
}
