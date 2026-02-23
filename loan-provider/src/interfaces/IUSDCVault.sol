// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IUSDCVault
 * @author Bitmor Protocol
 * @notice Interface for the USDCVault's BLP deposit functionality used by USDCStrategy
 * @dev Exposes only the `depositToBLP` function needed by the strategy to route
 * deposits through the vault instead of calling the LendingPool directly.
 */
interface IUSDCVault {
    /**
     * @notice Deposits `amount` of the underlying asset into the Bitmor Lending Pool on behalf of `onBehalfOf`
     * @dev Called by USDCStrategy to route BLP deposits through the vault, which is the
     * authorized caller on the LendingPool. The vault pulls assets from the caller via
     * `safeTransferFrom`, so the caller must have approved the vault beforehand.
     * @param amount The amount of underlying asset to deposit into BLP
     * @param onBehalfOf The address that will receive the aTokens from the BLP deposit
     */
    function depositToBLP(uint256 amount, address onBehalfOf) external;
}
