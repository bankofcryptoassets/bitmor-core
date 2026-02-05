// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title ISimpleStrategy
 * @author Bitmor Protocol
 * @notice Interface for vault strategy contracts that manage yield generation across DeFi protocols
 * @dev Defines the standard functions that all strategy implementations must provide.
 * Strategies split assets between Aave and the Bitmor Lending Pool.
 */
interface ISimpleStrategy {
    /**
     * @notice Emitted when the minimum delta threshold for reallocation is updated
     * @param newMinimumDeltaRequired The new minimum delta in basis points
     */
    event SimpleStrategy__MinimumDeltaUpdated(uint256 newMinimumDeltaRequired);

    /**
     * @notice Returns the address of the underlying asset
     * @return The address of the ERC20 token managed by this strategy
     */
    function asset() external view returns (address);

    /**
     * @notice Supplies assets to external protocols for yield generation
     * @param amount The amount of assets to be deployed
     */
    function supply(uint256 amount) external;

    /**
     * @notice Withdraws `amount` from external protocols while maintaining the allocation ratio
     * @param amount The amount of assets to withdraw
     */
    function withdraw(uint256 amount) external;

    /**
     * @notice Withdraws all funds from external protocols back to the vault
     * @dev Called when strategy is being replaced or vault needs full liquidity
     */
    function withdrawAllFunds() external;

    /**
     * @notice Returns the total assets under management across all positions
     * @return balance The total amount of assets managed by this strategy
     */
    function totalAssets() external view returns (uint256 balance);

    /**
     * @notice Returns the total balance currently deployed in external protocol markets
     * @return balance The total amount deployed across Aave and BLP
     */
    function getTotalBalanceInMarkets() external view returns (uint256 balance);

    /**
     * @notice Rebalances assets between protocols to match the configured allocation ratio
     */
    function reallocateAssets() external;

    /**
     * @notice Reallocates assets to ensure BLP has sufficient liquidity for a pending withdrawal
     * @param amountToWithdraw The amount that will be withdrawn from BLP
     */
    function reallocateAssets(uint256 amountToWithdraw) external;

    /**
     * @notice Updates the minimum delta required before a reallocation is triggered
     * @param newMinimumDeltarRequired The new minimum delta in basis points
     */
    function updateMinimumDeltaRequired(uint256 newMinimumDeltarRequired) external;
}
