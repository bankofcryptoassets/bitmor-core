// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC4626, ERC20} from "@solady/tokens/ERC4626.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "@solady/utils/ReentrancyGuard.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {AccessManaged} from "@openzeppelin/access/manager/AccessManaged.sol";
import {Pausable} from "@openzeppelin/utils/Pausable.sol";

import {Errors} from "../../libraries/helpers/Errors.sol";
import {BTCVault__Validation as Helpers} from "../../libraries/helpers/BTCVault__Validation.sol";
import {DataTypes} from "../../libraries/types/DataTypes.sol";
import {VaultStateLogic} from "../../libraries/logic/VaultStateLogic.sol";
import {StrategyStateLogic} from "../../libraries/logic/StrategyStateLogic.sol";
import {TokenizedStrategyLogic} from "../../libraries/logic/TokenizedStrategyLogic.sol";

import {BTCVault__Storage} from "./BTCVault__Storage.sol";

/**
 * @title BTCVault
 * @author Bitmor Protocol
 * @notice Advanced ERC-4626 compliant vault with modular tokenized strategy support
 * @dev Extends Solady's ERC4626 with role-based access control, multiple strategies,
 * and advanced allocation management for BTC-based assets.
 *
 * ## Features
 * - **ERC-4626 Compliance**: Standard vault interface for deposits/withdrawals
 * - **Multi-Strategy Support**: Configurable strategies with allocation caps
 * - **Fee System**: Entry and exit fees in basis points
 * - **Queue Management**: Separate supply and withdraw queues for strategy priority
 * - **Emergency Controls**: Pause functionality and emergency withdrawal
 *
 * ## Strategy Flow
 * ```
 * Deposit: User -> Vault -> Supply Queue -> Strategies (respecting caps)
 * Withdraw: Strategies -> Withdraw Queue -> Vault -> User (with exit fee)
 * ```
 *
 * ## Access Control
 * Uses OpenZeppelin AccessManaged for role-based permissions:
 * - Deposit/mint requires authorization
 * - Strategy management requires curator/allocator roles
 * - Pause/unpause requires emergency roles
 *
 * @custom:security Uses reentrancy guards and access control for secure operations
 * @custom:security Validates all strategy operations to prevent fund loss
 */
// aderyn-ignore-next-line(centralization-risk)
contract BTCVault is BTCVault__Storage, ERC4626, AccessManaged, ReentrancyGuard, Pausable {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for address;
    using Helpers for DataTypes.StrategyState;
    using StrategyStateLogic for DataTypes.StrategyState;
    using VaultStateLogic for DataTypes.VaultState;
    using TokenizedStrategyLogic for address;
    using TokenizedStrategyLogic for DataTypes.StrategyState;

    /**
     * @notice Initializes the vault with the specified underlying asset
     * @param _asset The address of the ERC20 token to be used as the underlying asset
     * @param _manager Access Manager address.
     */
    constructor(address _asset, address _manager) BTCVault__Storage(_asset) AccessManaged(_manager) {}

    /*
       _____      _                        _   _____                 _   _
      | ____|_  _| |_ ___ _ __ _ __   __ _| | |  ___|   _ _ __   ___| |_(_) ___  _ __  ___
      |  _| \ \/ / __/ _ \ '__| '_ \ / _` | | | |_ | | | | '_ \ / __| __| |/ _ \| '_ \/ __|
      | |___ >  <| ||  __/ |  | | | | (_| | | |  _|| |_| | | | | (__| |_| | (_) | | | \__ \
      |_____/_/\_\\__\___|_|  |_| |_|\__,_|_| |_|   \__,_|_| |_|\___|\__|_|\___/|_| |_|___/
    */

    /**
     * @notice Returns the internal index of a strategy in the strategies array
     * @param strategy The address of the strategy to look up
     * @return index The index of the strategy in the strategies array
     */
    function getStrategyIndex(address strategy) external view returns (uint256 index) {
        return s_strategy.getStrategyIndex(strategy);
    }

    /**
     * @notice Returns the current fee recipient address
     * @return The address that receives collected entry and exit fees
     */
    function getFeeRecipient() external view returns (address) {
        return s_vault.feeRecipient;
    }

    /**
     * @notice Returns the maximum number of strategies allowed in the vault
     * @return The maximum strategies limit
     */
    function getMaxStrategies() external view returns (uint256) {
        return s_vault.maxStrategies;
    }

    /**
     * @notice Returns detailed information about a strategy
     * @param strategyIndex The index of the strategy in the strategies array
     * @return strategy The strategy struct containing address and allocation cap
     */
    function getStrategyDetails(uint256 strategyIndex) external view returns (DataTypes.Strategy memory strategy) {
        strategy = s_strategy.strategies[strategyIndex];
    }

    /**
     * @notice Returns the total number of strategies added to the vault
     * @return The count of strategies currently managed by the vault
     */
    function getTotalStrategies() external view returns (uint256) {
        return s_strategy.totalStrategies;
    }

    /**
     * @notice Returns the amount of assets currently deployed in a specific strategy
     * @param strategy The address of the strategy to query
     * @return assets The amount of underlying assets held by the specified strategy
     */
    function getAssetInStrategy(address strategy) external view returns (uint256 assets) {
        assets = TokenizedStrategyLogic.getAssetBalanceInStrategy(
            s_strategy.strategies[s_strategy.getStrategyIndex(strategy)].strategy
        );
    }

    /**
     * @notice Returns the current supply queue (deposit priority order)
     * @return supplyQueue Array of strategy indices in supply order
     */
    function getSupplyQueue() external view returns (uint256[] memory supplyQueue) {
        supplyQueue = s_strategy.supplyQueue;
    }

    /**
     * @notice Returns the current withdraw queue (withdrawal priority order)
     * @return withdrawQueue Array of strategy indices in withdrawal order
     */
    function getWithdrawQueue() external view returns (uint256[] memory withdrawQueue) {
        withdrawQueue = s_strategy.withdrawQueue;
    }

    /**
     * @notice Returns the number of strategies in the supply queue
     * @return Length of the supply queue array
     */
    function getSupplyQueueLength() external view returns (uint256) {
        return s_strategy.supplyQueue.length;
    }

    /**
     * @notice Returns the number of strategies in the withdraw queue
     * @return Length of the withdraw queue array
     */
    function getWithdrawQueueLength() external view returns (uint256) {
        return s_strategy.withdrawQueue.length;
    }

    /**
     * @notice Sets the entry fee for deposits
     * @param newEntryFee The new entry fee in basis points (e.g., 50 = 0.5%)
     */
    function setEntryFee(uint256 newEntryFee) external restricted {
        if (newEntryFee > MAX_FEE_BPS) revert Errors.ExceedMaxFee();

        s_vault.updateEntryFee(newEntryFee);

        emit BTCVault__EntryFeeUpdated(newEntryFee);
    }

    /**
     * @notice Sets the exit fee for withdrawals
     * @param newExitFee The new exit fee in basis points (e.g., 100 = 1%)
     */
    function setExitFee(uint256 newExitFee) external restricted {
        if (newExitFee > MAX_FEE_BPS) revert Errors.ExceedMaxFee();

        s_vault.updateExitFee(newExitFee);

        emit BTCVault__ExitFeeUpdated(newExitFee);
    }

    /**
     * @notice Sets the address that will receive collected fees
     * @param newFeeRecipient The new fee recipient address (cannot be zero address)
     */
    function setFeeRecipient(address newFeeRecipient) external restricted {
        if (newFeeRecipient == address(0)) revert Errors.ZeroAddress();

        s_vault.updateFeeRecipient(newFeeRecipient);

        emit BTCVault__FeeRecipientUpdated(newFeeRecipient);
    }

    /**
     * @notice Sets the maximum number of strategies the vault can manage
     * @dev Only callable by authorized role
     * @param newMaxStrategies The new maximum strategies limit
     */
    function setMaxStrategies(uint256 newMaxStrategies) external restricted {
        s_vault.maxStrategies = newMaxStrategies;

        emit BTCVault__MaxStrategiesUpdated(newMaxStrategies);
    }

    /**
     * @notice Adds a new tokenized strategy to the vault
     * @dev Only callable by CURATOR role. Strategy must be compatible with vault asset
     * @param strategy The address of the tokenized strategy contract to add
     * @param cap The maximum amount of assets this strategy can hold
     */
    function addStrategy(address strategy, uint256 cap) external restricted {
        s_strategy.validateStrategyAddition(strategy, i_asset, s_vault.maxStrategies);

        s_strategy.addStrategy(strategy, cap);

        i_asset.safeApprove(strategy, type(uint256).max);

        emit BTCVault__TokenizedStrategyAdded(strategy, cap);
    }

    /**
     * @notice Changes the asset allocation cap for an existing strategy
     * @dev Only callable by CURATOR role. Must validate strategy exists
     * @param strategy The address of the strategy to modify
     * @param newCap The new maximum amount of assets this strategy can hold
     */
    function changeStrategyCap(address strategy, uint256 newCap) external restricted {
        s_strategy.validateCapChange(strategy, newCap);

        s_strategy.changeCap(strategy, newCap);

        emit BTCVault__CapUpdated(strategy, newCap);
    }

    /**
     * @notice Reallocates funds across strategies according to specified allocations
     * @dev Only callable by ALLOCATOR role. Validates total allocations and asset availability
     * @param allocations Array of allocation instructions specifying strategy and amount changes
     */
    function reallocateFunds(DataTypes.Allocation[] calldata allocations) external restricted {
        s_strategy.validateReallocateFunds(totalAssets(), i_asset);

        _reallocateFunds(allocations);

        emit BTCVault__FundsReallocated();
    }

    /**
     * @notice Emergency function to withdraw all funds from all strategies back to the vault
     * @dev Only callable by MANAGER role. Used in emergency situations to secure assets
     */
    function emergencyWithdrawFunds() external restricted {
        s_strategy.emergencyWithdraw();

        emit BTCVault__EmergencyWithdrawFunds();
    }

    /**
     * @notice Updates the order in which strategies receive deposits
     * @dev Only callable by ALLOCATOR role. Queue determines priority for fund deployment
     * @param newSupplyQueue Array of strategy indices in desired supply order
     */
    function updateSupplyQueue(uint256[] memory newSupplyQueue) external restricted {
        s_strategy.validateNewSupplyQueue(newSupplyQueue, s_vault.maxStrategies);

        s_strategy.updateSupplyQueue(newSupplyQueue);

        emit BTCVault__SupplyQueueUpdated(newSupplyQueue);
    }

    /**
     * @notice Updates the order in which strategies are drained for withdrawals
     * @dev Only callable by ALLOCATOR role. Queue determines priority for fund withdrawal
     * @param newWithdrawQueue Array of strategy indices in desired withdrawal order
     */
    function updateWithdrawQueue(uint256[] memory newWithdrawQueue) external restricted {
        s_strategy.validateNewWithdrawQueue(newWithdrawQueue);

        s_strategy.updateWithdrawQueue(newWithdrawQueue);

        emit BTCVault__WithdrawQueueUpdated(newWithdrawQueue);
    }

    /**
     * @notice Pauses all vault operations in case of emergency
     * @dev Only callable by authorized emergency role when vault is not paused
     */
    function pause() external whenNotPaused restricted {
        _pause();
    }

    /**
     * @notice Resumes vault operations after an emergency pause
     * @dev Only callable by authorized role when vault is paused
     */
    function unpause() external whenPaused restricted {
        _unpause();
    }

    /*
       ____        _     _ _        _____                 _   _
      |  _ \ _   _| |__ | (_) ___  |  ___|   _ _ __   ___| |_(_) ___  _ __  ___
      | |_) | | | | '_ \| | |/ __| | |_ | | | | '_ \ / __| __| |/ _ \| '_ \/ __|
      |  __/| |_| | |_) | | | (__  |  _|| |_| | | | | (__| |_| | (_) | | | \__ \
      |_|    \__,_|_.__/|_|_|\___| |_|   \__,_|_| |_|\___|\__|_|\___/|_| |_|___/
    */

    /**
     * @notice Returns the name of the vault token
     * @inheritdoc ERC20
     * @return The vault token name
     */
    function name() public pure override returns (string memory) {
        return "BitmorBTCVault";
    }

    /**
     * @notice Returns the symbol of the vault token
     * @inheritdoc ERC20
     * @return The vault token symbol
     */
    function symbol() public pure override returns (string memory) {
        return "bvBTC";
    }

    /**
     * @notice Returns the address of the underlying asset
     * @inheritdoc ERC4626
     * @return The address of the underlying ERC20 token
     */
    function asset() public view override returns (address) {
        return i_asset;
    }

    /**
     * @notice Previews the amount of shares that would be minted for a deposit
     * @inheritdoc ERC4626
     * @dev Deducts entry fees from assets before calculating shares
     * @param assets The amount of assets to be deposited
     * @return shares The amount of shares that would be minted (after fees)
     */
    function previewDeposit(uint256 assets) public view override returns (uint256 shares) {
        uint256 fee = _feeOnTotal(assets, getEntryFee());
        return super.previewDeposit(assets.rawSub(fee));
    }

    /**
     * @notice Previews the amount of assets needed to mint a specific amount of shares
     * @inheritdoc ERC4626
     * @dev Adds entry fees to the required assets
     * @param shares The amount of shares to be minted
     * @return assets The total amount of assets needed (including fees)
     */
    function previewMint(uint256 shares) public view override returns (uint256 assets) {
        assets = super.previewMint(shares);
        return (assets.rawAdd(_feeOnRaw(assets, getEntryFee())));
    }

    /**
     * @notice Previews the amount of shares needed to withdraw a specific amount of assets
     * @inheritdoc ERC4626
     * @dev Deducts exit fees from assets before calculating shares
     * @param assets The amount of assets to be withdrawn
     * @return shares The amount of shares that need to be burned
     */
    function previewWithdraw(uint256 assets) public view override returns (uint256 shares) {
        uint256 fee = _feeOnRaw(assets, getExitFee());
        return super.previewWithdraw(assets.rawAdd(fee));
    }

    /**
     * @notice Previews the amount of assets that would be withdrawn for redeeming shares
     * @inheritdoc ERC4626
     * @dev Adds exit fees to the assets calculation
     * @param shares The amount of shares to be redeemed
     * @return assets The total amount of assets that would be withdrawn (including fees)
     */
    function previewRedeem(uint256 shares) public view override returns (uint256 assets) {
        assets = super.previewRedeem(shares);
        return (assets.rawSub(_feeOnTotal(assets, getExitFee())));
    }

    /**
     * @notice Returns the total amount of assets under management
     * @inheritdoc ERC4626
     * @dev Delegates to the strategy contract to calculate total assets across all positions
     * @return assets The total amount of underlying assets managed by the vault
     */
    function totalAssets() public view override returns (uint256 assets) {
        uint256 i = 0;

        for (i; i < s_strategy.totalStrategies; i++) {
            assets = assets.rawAdd(TokenizedStrategyLogic.getAssetBalanceInStrategy(s_strategy.strategies[i].strategy));
        }
    }

    /**
     * @notice Returns max amount of assets any `user` can deposit.
     * @dev It returns the sum of remaining `cap` of each `strategy`.
     * @param user Address of the user
     */
    function maxDeposit(address user) public view override returns (uint256 maxAssets) {
        uint256 i = 0;
        uint256[] memory supplyQueue = s_strategy.supplyQueue;
        for (i; i < supplyQueue.length; i++) {
            DataTypes.Strategy memory strategy = s_strategy.strategies[supplyQueue[i]];

            uint256 cap = strategy.cap;

            if (cap == 0) continue;

            uint256 currentBalance = TokenizedStrategyLogic.getAssetBalanceInStrategy(strategy.strategy);

            maxAssets = maxAssets.rawAdd(cap.zeroFloorSub(currentBalance));
        }
    }

    /**
     * @notice Returns max amount of assets `user` can withdraw after applicable `fee`.
     * @param user Address of the user
     */
    function maxWithdraw(address user) public view override returns (uint256 maxAssets) {
        uint256 balanceOfUser = convertToAssets(balanceOf(user));
        uint256 fee = getExitFee();

        if (fee == 0) return balanceOfUser;

        uint256 feeOnWithdraw = _feeOnTotal(balanceOfUser, fee);

        maxAssets = balanceOfUser.rawSub(feeOnWithdraw);
    }

    /**
     * @notice Returns the current entry fee in basis points
     * @return The entry fee charged on deposits (in basis points)
     */
    function getEntryFee() public view returns (uint256) {
        return s_vault.entryFee;
    }

    /**
     * @notice Returns the current exit fee in basis points
     * @return The exit fee charged on withdrawals (in basis points)
     */
    function getExitFee() public view returns (uint256) {
        return s_vault.exitFee;
    }

    /**
     * @notice Deposits assets into the vault and mints shares to the receiver
     * @dev Overrides ERC4626 deposit with reentrancy guard and access control
     * @param assets Amount of underlying assets to deposit
     * @param to Address to receive the minted shares
     * @return Amount of shares minted
     */
    function deposit(uint256 assets, address to)
        public
        override
        nonReentrant
        whenNotPaused
        restricted
        returns (uint256)
    {
        return super.deposit(assets, to);
    }

    /**
     * @notice Mints exact shares to the receiver by depositing assets
     * @dev Overrides ERC4626 mint with reentrancy guard and access control
     * @param shares Exact amount of shares to mint
     * @param to Address to receive the minted shares
     * @return Amount of assets deposited
     */
    function mint(uint256 shares, address to) public override nonReentrant whenNotPaused restricted returns (uint256) {
        return super.mint(shares, to);
    }

    /**
     * @notice Withdraws exact assets by burning shares from the owner
     * @dev Overrides ERC4626 withdraw with reentrancy guard
     * @param assets Exact amount of assets to withdraw
     * @param to Address to receive the withdrawn assets
     * @param owner Address that owns the shares to burn
     * @return Amount of shares burned
     */
    function withdraw(uint256 assets, address to, address owner)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        return super.withdraw(assets, to, owner);
    }

    /**
     * @notice Redeems exact shares for assets
     * @dev Overrides ERC4626 redeem with reentrancy guard
     * @param shares Exact amount of shares to redeem
     * @param to Address to receive the assets
     * @param owner Address that owns the shares to redeem
     * @return Amount of assets received
     */
    function redeem(uint256 shares, address to, address owner)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        return super.redeem(shares, to, owner);
    }

    /*
       ___       _                        _   _____                 _   _
      |_ _|_ __ | |_ ___ _ __ _ __   __ _| | |  ___|   _ _ __   ___| |_(_) ___  _ __  ___
       | || '_ \| __/ _ \ '__| '_ \ / _` | | | |_ | | | | '_ \ / __| __| |/ _ \| '_ \/ __|
       | || | | | ||  __/ |  | | | | (_| | | |  _|| |_| | | | | (__| |_| | (_) | | | \__ \
      |___|_| |_|\__\___|_|  |_| |_|\__,_|_| |_|   \__,_|_| |_|\___|\__|_|\___/|_| |_|___/
    */

    /**
     * @notice Internal function for `deposit` and `mint`.
     * @dev This will first transfer the applicable `fee` to the `feeRecipient` and then execute the internal `_deposit` function which will accept `assets`-`fee` in the vault.
     * @param by Address where the `assets` will be transferred from.
     * @param to Address where the `shares` will be minted to.
     * @param assets The amount of underlying assets to deposit after applicable `fee`.
     * @param shares The amount of shares to mint.
     */
    function _deposit(address by, address to, uint256 assets, uint256 shares) internal override {
        uint256 fee = getEntryFee();

        super._deposit(by, to, assets, shares);

        if (fee != 0) {
            uint256 feeAmount = _feeOnTotal(assets, fee);

            // Transfer entry fee to fee recipient (if fee exists and recipient is not this contract)
            if (feeAmount > 0 && s_vault.feeRecipient != address(this)) {
                i_asset.safeTransfer(s_vault.feeRecipient, feeAmount);
            }

            assets = assets.rawSub(feeAmount);
        }

        _depositFunds(assets);
    }

    function _withdraw(address by, address to, address owner, uint256 assets, uint256 shares) internal override {
        uint256 fee = getExitFee();
        uint256 totalToWithdraw = assets;

        if (fee != 0) {
            // Calculate fee on the amount user will receive
            uint256 feeAmount = _feeOnRaw(assets, fee);
            // Withdraw assets PLUS fee from strategies
            totalToWithdraw = assets.rawAdd(feeAmount);

            // Withdraw total amount needed
            _withdrawFunds(totalToWithdraw);

            // Send fee to recipient
            if (feeAmount > 0 && s_vault.feeRecipient != address(this)) {
                i_asset.safeTransfer(s_vault.feeRecipient, feeAmount);
            }
        } else {
            // No fee, just withdraw the assets
            _withdrawFunds(assets);
        }

        // Send exact 'assets' amount to user as per ERC4626 spec
        super._withdraw(by, to, owner, assets, shares);
    }

    /**
     * @notice Returns the number of decimals used by the underlying asset
     * @inheritdoc ERC4626
     * @dev Used internally for precise share calculations
     * @return The number of decimals of the underlying asset
     */
    function _underlyingDecimals() internal view override returns (uint8) {
        return ERC20(i_asset).decimals();
    }

    /**
     * @notice Calculates the fees that should be added to an amount that does not already include fees
     * @dev Used in {ERC4626-mint} and {ERC4626-withdraw} operations
     * @param assets The base amount of assets (without fees)
     * @param feeBasisPoints The fee rate in basis points
     * @return The calculated fee amount
     */
    function _feeOnRaw(uint256 assets, uint256 feeBasisPoints) internal pure returns (uint256) {
        return assets.mulDivUp(feeBasisPoints, BASIS_POINT_SCALE);
    }

    /**
     * @notice Calculates the fee portion of an amount that already includes fees
     * @dev Used in {ERC4626-deposit} and {ERC4626-redeem} operations
     * @param assets The total amount of assets (including fees)
     * @param feeBasisPoints The fee rate in basis points
     * @return The calculated fee amount
     */
    function _feeOnTotal(uint256 assets, uint256 feeBasisPoints) internal pure returns (uint256) {
        return assets.mulDivUp(feeBasisPoints, feeBasisPoints + BASIS_POINT_SCALE);
    }

    /**
     * @notice Deposits assets into strategies following the supply queue order
     * @dev Distributes assets across strategies respecting allocation caps and queue priority
     * @param assets The total amount of assets to deposit
     */
    function _depositFunds(uint256 assets) internal {
        uint256 i = 0;
        uint256[] memory supplyQueue = s_strategy.supplyQueue;
        for (i; i < supplyQueue.length; ++i) {
            DataTypes.Strategy memory strategy = s_strategy.strategies[supplyQueue[i]];

            // Skip strategies with zero cap
            if (strategy.cap == 0) continue;

            // Get current asset balance in the strategy
            uint256 currentAssets = strategy.strategy.getAssetBalanceInStrategy();

            // Calculate available capacity: min(remaining assets, available cap)
            uint256 amountToSupply = assets.min(strategy.cap.zeroFloorSub(currentAssets));

            // Deposit available assets to the strategy
            if (amountToSupply > 0) {
                strategy.strategy.deposit(amountToSupply);
                assets = assets.zeroFloorSub(amountToSupply);

                emit BTCVault__DepositedInStrategy(supplyQueue[i], amountToSupply);
            }

            // Exit if all assets have been allocated
            if (assets == 0) return;
        }

        // Revert if assets remain after trying all strategies
        if (assets != 0) revert Errors.AllCapsReached();
    }

    /**
     * @notice Withdraws assets from strategies following the withdraw queue order
     * @dev Processes withdrawals across strategies until requested amount is obtained
     * @param assets The total amount of assets to withdraw
     */
    function _withdrawFunds(uint256 assets) internal {
        uint256 i = 0;
        uint256[] memory withdrawQueue = s_strategy.withdrawQueue;
        for (i; i < withdrawQueue.length; i++) {
            DataTypes.Strategy memory strategy = s_strategy.strategies[withdrawQueue[i]];

            // Get maximum withdrawable amount from this strategy
            uint256 maxWithdrawable = strategy.strategy.getMaxWithdrawable();

            // Withdraw the minimum of needed and available
            uint256 amountToWithdraw = maxWithdrawable.min(assets);

            if (amountToWithdraw > 0) {
                uint256 finalAmountWithdrawn = strategy.strategy.withdraw(amountToWithdraw);

                assets = assets.zeroFloorSub(finalAmountWithdrawn);

                emit BTCVault__WithdrewFromStrategy(withdrawQueue[i], finalAmountWithdrawn);
            }

            // Exit if all required assets have been withdrawn
            if (assets == 0) return;
        }

        // Revert if insufficient liquidity across all strategies
        if (assets != 0) revert Errors.NotEnoughLiquidity();
    }

    /**
     * @notice Reallocates funds across strategies according to specified allocations
     * @dev Processes withdrawals first, then deposits, ensuring total balance consistency
     * @param allocations Array of allocation instructions specifying target amounts per strategy
     */
    function _reallocateFunds(DataTypes.Allocation[] memory allocations) internal {
        uint256 totalSupplied;
        uint256 totalWithdrawn;

        uint256 i = 0;
        for (i; i < allocations.length; i++) {
            DataTypes.Allocation memory allocation = allocations[i];
            DataTypes.Strategy memory strategy = s_strategy.strategies[allocation.index];

            uint256 currentBalance = TokenizedStrategyLogic.getAssetBalanceInStrategy(strategy.strategy);
            uint256 newAllocation = allocation.amount;

            // Calculate if we need to withdraw (current > target)
            uint256 toWithdraw = currentBalance.zeroFloorSub(newAllocation);

            if (toWithdraw > 0) {
                // Withdraw excess funds from strategy
                uint256 withdrawn = strategy.strategy.withdraw(toWithdraw);

                totalWithdrawn += withdrawn;

                emit BTCVault__WithdrewFromStrategy(allocation.index, withdrawn);
            } else {
                // Calculate assets to supply (target > current)
                // Special case: type(uint256).max means allocate all remaining withdrawn funds
                uint256 assetToSupply = newAllocation == type(uint256).max
                    ? totalWithdrawn.zeroFloorSub(totalSupplied)
                    : newAllocation.zeroFloorSub(currentBalance);

                if (assetToSupply == 0) continue;

                // Validate strategy cap constraints
                uint256 currentSupplyCap = strategy.cap;
                if (currentSupplyCap == 0) revert Errors.StrategyWithZeroCap(allocation.index);

                if (currentBalance + assetToSupply > currentSupplyCap) {
                    revert Errors.SupplyCapExceeded(allocation.index);
                }

                strategy.strategy.deposit(assetToSupply);

                emit BTCVault__DepositedInStrategy(allocation.index, assetToSupply);

                totalSupplied += assetToSupply;
            }
        }

        // Ensure reallocation maintains asset balance (what's withdrawn must equal what's deposited)
        if (totalSupplied != totalWithdrawn) revert Errors.InvalidReallocation();
    }
}
