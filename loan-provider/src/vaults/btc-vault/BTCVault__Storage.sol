// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {DataTypes} from "../../libraries/types/DataTypes.sol";
import {Errors} from "../../libraries/helpers/Errors.sol";

/**
 * @title BTCVault__Storage
 * @author Bitmor Protocol
 * @notice Storage contract for BTCVault containing state variables, events, and constants
 * @dev Implements the separated storage pattern for:
 * - Clear state variable organization
 * - Gas optimization through immutable variables
 * - Potential future upgradeability support
 *
 * ## Storage Layout
 * - `i_asset`: Immutable underlying asset address
 * - `s_vault`: Vault configuration (fees, recipient)
 * - `s_strategy`: Strategy management state (strategies array, queues)
 *
 * ## Constants
 * - `BASIS_POINT_SCALE`: 10,000 (100% = 10000 bps)
 * - `MAX_FEE_BPS`: 1,000 (10% maximum fee)
 */
contract BTCVault__Storage {
    /**
     * @notice Emitted when the entry fee is updated
     * @param newEntryFee The new entry fee in basis points
     */
    event BTCVault__EntryFeeUpdated(uint256 indexed newEntryFee);

    /**
     * @notice Emitted when the exit fee is updated
     * @param newExitFee The new exit fee in basis points
     */
    event BTCVault__ExitFeeUpdated(uint256 indexed newExitFee);

    /**
     * @notice Emitted when the fee recipient address is updated
     * @param newFeeRecipient The new address that will receive fees
     */
    event BTCVault__FeeRecipientUpdated(address indexed newFeeRecipient);

    /**
     * @notice Emitted when the strategy contract is updated
     * @param newStrategy The new strategy contract address
     */
    event BTCVault__StrategyUpdated(address indexed newStrategy);

    /**
     * @notice Emitted when a new tokenized strategy is added to the vault
     * @param strategy The address of the added strategy
     * @param cap The allocation cap set for the strategy
     */
    event BTCVault__TokenizedStrategyAdded(address indexed strategy, uint256 indexed cap);

    /**
     * @notice Emitted when a strategy's allocation cap is updated
     * @param strategy The address of the strategy
     * @param newCap The new allocation cap
     */
    event BTCVault__CapUpdated(address indexed strategy, uint256 indexed newCap);

    /**
     * @notice Emitted when funds are reallocated across strategies
     */
    event BTCVault__FundsReallocated();

    /**
     * @notice Emitted when the minimum idle assets threshold is updated
     * @param newMinimumIdleAssets The new minimum idle assets amount
     */
    event BTCVault__MinimumIdleAssetsUpdated(uint256 indexed newMinimumIdleAssets);

    /**
     * @notice Emitted when emergency withdrawal of all funds is executed
     */
    event BTCVault__EmergencyWithdrawFunds();

    /**
     * @notice Emitted when a strategy withdrawal fails during reallocation and is skipped
     * @param strategyIndex The index of the strategy that failed
     * @param amount The amount that was attempted to withdraw
     * @param reason The revert reason bytes from the failed call
     */
    event BTCVault__StrategyWithdrawFailed(uint256 indexed strategyIndex, uint256 amount, bytes reason);

    /**
     * @notice Emitted when a strategy withdrawal fails during emergency withdraw and is skipped
     * @param strategyIndex The index of the strategy that failed
     * @param reason The revert reason bytes from the failed call
     */
    event BTCVault__EmergencyWithdrawFailed(uint256 indexed strategyIndex, bytes reason);

    /**
     * @notice Emitted when the supply queue order is updated
     * @param newSupplyQueue The new supply queue array with strategy indices
     */
    event BTCVault__SupplyQueueUpdated(uint256[] indexed newSupplyQueue);

    /**
     * @notice Emitted when the withdraw queue order is updated
     * @param newWithdrawQueue The new withdraw queue array with strategy indices
     */
    event BTCVault__WithdrawQueueUpdated(uint256[] indexed newWithdrawQueue);

    /**
     * @notice Emitted when funds are withdrawn from a specific strategy
     * @param strategyIndex The index of the strategy funds were withdrawn from
     * @param amountWithdrawn The amount of assets withdrawn
     */
    event BTCVault__WithdrewFromStrategy(uint256 indexed strategyIndex, uint256 indexed amountWithdrawn);

    /**
     * @notice Emitted when funds are deposited into a specific strategy
     * @param strategyIndex The index of the strategy funds were deposited into
     * @param amountDeposited The amount of assets deposited
     */
    event BTCVault__DepositedInStrategy(uint256 indexed strategyIndex, uint256 indexed amountDeposited);

    /**
     * @notice Emitted when the maximum number of strategies is updated
     * @param newMaxStrategies The new maximum strategies limit
     */
    event BTCVault__MaxStrategiesUpdated(uint256 indexed newMaxStrategies);

    // ============ Immutable Storage ============

    /**
     * @notice The underlying asset that the vault accepts (cbBTC)
     * @dev Set once in constructor and cannot be changed
     */
    address internal immutable i_asset;

    // ============ Constants ============

    /**
     * @notice Scale factor for basis points calculations (10,000 = 100%)
     * @dev Used for fee calculations: fee = amount * feeBps / BASIS_POINT_SCALE
     */
    uint256 internal constant BASIS_POINT_SCALE = 1e4;

    /**
     * @notice Maximum allowed fee in basis points (10%)
     * @dev Entry and exit fees cannot exceed this value
     */
    uint256 internal constant MAX_FEE_BPS = 10_00;

    /**
     * @notice Minimum amount of assets that must be deposited into strategies per vault deposit
     * @dev Prevents the tiny-shares scenario where Solady's virtual offset causes
     *      disproportionate rounding. 10,000 sat = 0.0001 BTC provides 110x safety margin
     *      over the theoretical threshold (~91 sat for <0.01% orphaned fraction).
     */
    uint256 internal constant MIN_STRATEGY_DEPOSIT = 10_000;

    // ============ Mutable Storage ============

    /**
     * @notice Vault configuration state including fees and recipient
     * @dev Contains entryFee, exitFee, feeRecipient, maxStrategies
     */
    DataTypes.VaultState internal s_vault;

    /**
     * @notice Complete strategy management state including strategies array and queues
     * @dev Contains strategies mapping, supplyQueue, withdrawQueue, totalStrategies
     */
    DataTypes.StrategyState internal s_strategy;

    // ============ Constructor ============

    /**
     * @notice Initializes the storage contract with the underlying asset
     * @param asset_ The address of the ERC20 token to be used as the underlying asset
     */
    constructor(address asset_) {
        if (asset_ == address(0)) revert Errors.ZeroAddress();
        i_asset = asset_;
    }
}
