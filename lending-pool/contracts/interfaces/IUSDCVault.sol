// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.6.12;

import { IERC4626 } from "./IERC4626.sol";

/**
 * @title IUSDCVault
 * @author Bitmor Protocol
 * @notice Interface for the USDCVault's BLP deposit functionality used by USDCStrategy
 * @dev Exposes only the `depositToBLP` function needed by the strategy to route
 * deposits through the vault instead of calling the LendingPool directly.
 */
interface IUSDCVault is IERC4626 {
    /**
     * @notice Emitted when the strategy contract is updated
     * @param newStrategy The new strategy contract address
     */
    event USDCVault__StrategyUpdated(address newStrategy);

    event USDCVault__AssetsReallocated();

    event USDCVault__AssetsDepositedToBLP(uint256 amount, address onBehalfOf);

    /**
     * @notice Deposits `amount` of the underlying asset into the Bitmor Lending Pool on behalf of `onBehalfOf`
     * @dev Called by USDCStrategy to route BLP deposits through the vault, which is the
     * authorized caller on the LendingPool. The vault pulls assets from the caller via
     * `safeTransferFrom`, so the caller must have approved the vault beforehand.
     * @param amount The amount of underlying asset to deposit into BLP
     * @param onBehalfOf The address that will receive the aTokens from the BLP deposit
     */
    function depositToBLP(uint256 amount, address onBehalfOf) external;

    /**
     * @notice Updates the strategy contract used for yield generation
     * @dev Withdraws funds from current strategy before switching to new one
     * @param newStrategy The address of the new strategy contract (cannot be zero address)
     * @custom:access Requires UVC role (1-day delay)
     */
    function setStrategy(address newStrategy) external;

    /**
     * @notice Triggers reallocation of assets between Aave and BLP to match target ratios
     * @dev USDC Vault invariants:
     * - MUST only be callable by the USDC Vault allocator role (UVA)
     * - Allocation MUST follow the target ratio set for Aave (`s_externalAllocation`),
     *   unlike BTC Vault which uses manual per-strategy configuration
     * - bvUSDC.totalAssets() before reallocateAssets() MUST equal
     *   bvUSDC.totalAssets() after reallocateAssets()
     * @custom:access Requires UVA role
     */
    function reallocateAssets() external;

    /**
     * @notice Reallocates assets by withdrawing `amountToWithdraw` from Aave to BLP
     * @dev Only callable by the Bitmor Lending Pool to maintain liquidity reserves
     * @param amountToWithdraw The amount of assets to move from Aave into BLP
     * @custom:access Requires UVA role and caller must be `blp`
     */
    function reallocateAssets(uint256 amountToWithdraw) external;

    /**
     * @notice Updates the minimum delta threshold for triggering asset reallocation
     * @param newMinimumDeltaRequired The new minimum delta in basis points
     * @custom:access Requires UVC role
     */
    function updateMinimumDeltaRequired(uint256 newMinimumDeltaRequired) external;

    /**
     * @notice Updates the external allocation ratio for external protocol.
     * @param newExternalAllocation The new external allocation in basis points.
     * @custom:access Requires UVC role
     */
    function updateExternalAllocation(uint256 newExternalAllocation) external;

    /**
     * @notice Pauses all vault operations in case of emergency
     * @custom:access Requires UVM_FAST role
     */
    function pause() external;

    /**
     * @notice Resumes vault operations after an emergency pause
     * @custom:access Requires UVM_SLOW role (1-day delay)
     */
    function unpause() external;
}
