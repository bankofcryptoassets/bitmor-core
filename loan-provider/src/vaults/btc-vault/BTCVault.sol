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
import {SimpleTokenizedStrategy} from "./TokenizedStrategy/SimpleTokenizedStrategy.sol";

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

    /// @notice Returns the next available strategy index (monotonic counter, never decremented)
    /// @return The next index that will be assigned when a new strategy is added
    function getNextStrategyIndex() external view returns (uint256) {
        return s_strategy.nextStrategyIndex;
    }

    /**
     * @notice Returns the amount of assets currently deployed in a specific strategy
     * @param strategy The address of the strategy to query
     * @return assets The amount of underlying assets held by the specified strategy
     */
    function getAssetInStrategy(address strategy) external view returns (uint256 assets) {
        assets = s_strategy.strategies[s_strategy.getStrategyIndex(strategy)].strategy.getAssetBalanceInStrategy();
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
     * @custom:access Requires BVM_SLOW role (1-day delay)
     */
    function setEntryFee(uint256 newEntryFee) external restricted {
        if (newEntryFee > MAX_FEE_BPS) revert Errors.ExceedMaxFee();
        if (newEntryFee > 0 && s_vault.feeRecipient == address(0)) revert Errors.Vault__FeeRecipientNotSet();

        s_vault.updateEntryFee(newEntryFee);

        emit BTCVault__EntryFeeUpdated(newEntryFee);
    }

    /**
     * @notice Sets the exit fee for withdrawals
     * @param newExitFee The new exit fee in basis points (e.g., 100 = 1%)
     * @custom:access Requires BVM_SLOW role (1-day delay)
     */
    function setExitFee(uint256 newExitFee) external restricted {
        if (newExitFee > MAX_FEE_BPS) revert Errors.ExceedMaxFee();
        if (newExitFee > 0 && s_vault.feeRecipient == address(0)) revert Errors.Vault__FeeRecipientNotSet();

        s_vault.updateExitFee(newExitFee);

        emit BTCVault__ExitFeeUpdated(newExitFee);
    }

    /**
     * @notice Sets the address that will receive collected fees
     * @param newFeeRecipient The new fee recipient address (cannot be zero address)
     * @custom:access Requires BVM_SLOW role (1-day delay)
     */
    function setFeeRecipient(address newFeeRecipient) external restricted {
        if (newFeeRecipient == address(0)) revert Errors.ZeroAddress();

        s_vault.updateFeeRecipient(newFeeRecipient);

        emit BTCVault__FeeRecipientUpdated(newFeeRecipient);
    }

    /**
     * @notice Sets the maximum number of strategies the vault can manage
     * @param newMaxStrategies The new maximum strategies limit
     * @custom:access Requires BVC role (1-day delay)
     */
    function setMaxStrategies(uint256 newMaxStrategies) external restricted {
        s_vault.maxStrategies = newMaxStrategies;

        emit BTCVault__MaxStrategiesUpdated(newMaxStrategies);
    }

    /**
     * @notice Adds a new tokenized strategy to the vault
     * @dev Strategy must be compatible with the vault asset
     * @param strategy The address of the tokenized strategy contract to add
     * @param cap The maximum amount of assets this strategy can hold
     * @custom:access Requires BVC role (1-day delay)
     */
    function addStrategy(address strategy, uint256 cap) external restricted {
        s_strategy.validateStrategyAddition(strategy, i_asset, s_vault.maxStrategies);

        s_strategy.addStrategy(strategy, cap);

        i_asset.safeApprove(strategy, type(uint256).max);

        emit BTCVault__TokenizedStrategyAdded(strategy, cap);
    }

    /**
     * @notice Changes the asset allocation cap for an existing strategy
     * @param strategy The address of the strategy to modify
     * @param newCap The new maximum amount of assets this strategy can hold
     * @custom:access Requires BVC role (1-day delay)
     */
    function changeStrategyCap(address strategy, uint256 newCap) external restricted {
        s_strategy.validateCapChange(strategy, newCap);

        s_strategy.changeCap(strategy, newCap);

        emit BTCVault__CapUpdated(strategy, newCap);
    }

    /**
     * @notice Reallocates funds across strategies according to specified allocations
     * @dev Validates total allocations and asset availability before execution
     * @param allocations Array of allocation instructions specifying strategy and amount changes
     * @custom:access Requires BVA_FAST role
     */
    function reallocateFunds(DataTypes.Allocation[] calldata allocations) external restricted {
        s_strategy.validateReallocateFunds(totalAssets(), i_asset);

        _reallocateFunds(allocations);

        emit BTCVault__FundsReallocated();
    }

    /**
     * @notice Emergency function to withdraw all funds from all strategies back to the vault
     * @dev Iterates the withdraw queue and attempts `withdrawAll()` on each strategy.
     *      Individual failures are caught and emit `BTCVault__EmergencyWithdrawFailed` so a
     *      single broken strategy does not block emergency recovery of all other strategies.
     *      Emits `BTCVault__EmergencyWithdrawFunds` with the total amount successfully recovered.
     * @custom:access Requires BVM_FAST role
     * @custom:security Critical safety mechanism — must never be blocked by a single strategy failure
     */
    function emergencyWithdrawFunds() external restricted {
        uint256[] memory withdrawQueue = s_strategy.withdrawQueue;
        uint256 totalRecovered;

        for (uint256 i; i < withdrawQueue.length; i++) {
            address strategyAddress = s_strategy.strategies[withdrawQueue[i]].strategy;

            try SimpleTokenizedStrategy(strategyAddress).withdrawAll() returns (uint256 recovered) {
                totalRecovered += recovered;
            } catch (bytes memory reason) {
                emit BTCVault__EmergencyWithdrawFailed(withdrawQueue[i], reason);
            }
        }

        emit BTCVault__EmergencyWithdrawFunds(totalRecovered);
    }

    /**
     * @notice Updates the order in which strategies receive deposits
     * @dev Queue determines priority for fund deployment
     * @param newSupplyQueue Array of strategy indices in desired supply order
     * @custom:access Requires BVA_SLOW role (1-day delay)
     */
    function updateSupplyQueue(uint256[] memory newSupplyQueue) external restricted {
        s_strategy.validateNewSupplyQueue(newSupplyQueue, s_vault.maxStrategies);

        s_strategy.updateSupplyQueue(newSupplyQueue);

        emit BTCVault__SupplyQueueUpdated(newSupplyQueue);
    }

    /**
     * @notice Updates the order in which strategies are drained for withdrawals
     * @dev Queue determines priority for fund withdrawal. Strategies excluded from `newWithdrawQueue`
     *      are deleted (requires cap = 0 and balance = 0). Automatically cleans stale entries from
     *      the supply queue when strategies are removed.
     * @param newWithdrawQueue Array of strategy indices in desired withdrawal order
     * @custom:access Requires BVA_SLOW role (1-day delay)
     */
    function updateWithdrawQueue(uint256[] memory newWithdrawQueue) external restricted {
        s_strategy.validateNewWithdrawQueue(newWithdrawQueue);

        bool supplyQueueCleaned = s_strategy.updateWithdrawQueue(newWithdrawQueue, i_asset);

        emit BTCVault__WithdrawQueueUpdated(newWithdrawQueue);

        if (supplyQueueCleaned) {
            emit BTCVault__SupplyQueueUpdated(s_strategy.supplyQueue);
        }
    }

    /**
     * @notice Pauses all vault operations in case of emergency
     * @custom:access Requires BVM_FAST role
     */
    function pause() external whenNotPaused restricted {
        _pause();
    }

    /**
     * @notice Resumes vault operations after an emergency pause
     * @custom:access Requires BVM_SLOW role (1-day delay)
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
     * @dev Sums the vault's idle balance (`balanceOf(address(this))`) and all strategy
     *      balances in the withdraw queue. Only active strategies (those in the withdraw
     *      queue) are counted — removed strategies are excluded.
     * @return assets The total amount of underlying assets managed by the vault
     */
    function totalAssets() public view override returns (uint256 assets) {
        assets = ERC20(i_asset).balanceOf(address(this));

        uint256[] memory wq = s_strategy.withdrawQueue;
        for (uint256 i = 0; i < wq.length; i++) {
            assets = assets.rawAdd(s_strategy.strategies[wq[i]].strategy.getAssetBalanceInStrategy());
        }
    }

    /**
     * @notice Returns max amount of assets any `owner` can deposit
     * @param owner Address of the depositor
     * @return maxAssets 0 when paused per ERC-4626 spec. Otherwise returns the sum of remaining `cap` of each strategy in the supply queue.
     */
    function maxDeposit(address owner) public view override returns (uint256 maxAssets) {
        if (paused()) return 0;

        uint256 i = 0;
        uint256[] memory supplyQueue = s_strategy.supplyQueue;
        for (i; i < supplyQueue.length; i++) {
            DataTypes.Strategy memory strategy = s_strategy.strategies[supplyQueue[i]];

            uint256 cap = strategy.cap;

            if (cap == 0) continue;

            uint256 currentBalance = strategy.strategy.getAssetBalanceInStrategy();

            maxAssets = maxAssets.rawAdd(cap.zeroFloorSub(currentBalance));
        }
    }

    /**
     * @notice Returns max shares any `owner` can mint
     * @dev Returns 0 when paused per ERC-4626 spec. Otherwise converts `maxDeposit` to shares for ERC-4626 compliance.
     * @param owner Address of the minter
     * @return maxShares Maximum number of shares that can be minted
     */
    function maxMint(address owner) public view override returns (uint256 maxShares) {
        if (paused()) return 0;
        maxShares = convertToShares(maxDeposit(owner));
    }

    /**
     * @notice Returns max amount of assets `owner` can withdraw after applicable exit fee
     * @dev Caps the ERC-4626 default at actual available liquidity across strategies.
     * Returns 0 when paused per ERC-4626 spec. The returned value MUST NOT cause a revert when passed to `withdraw`.
     * @param owner Address of the withdrawer
     * @return maxAssets Maximum amount of assets withdrawable by `owner` after exit fee
     */
    function maxWithdraw(address owner) public view override returns (uint256 maxAssets) {
        if (paused()) return 0;
        uint256 ownerAssets = convertToAssets(balanceOf(owner));
        uint256 availableLiquidity = _getAvailableLiquidity();
        uint256 withdrawable = ownerAssets < availableLiquidity ? ownerAssets : availableLiquidity;

        uint256 fee = getExitFee();
        if (fee == 0) return withdrawable;

        maxAssets = withdrawable.rawSub(_feeOnTotal(withdrawable, fee));
    }

    /**
     * @notice Returns max shares `owner` can redeem
     * @dev Caps at actual available liquidity converted to shares. Returns 0 when paused per ERC-4626 spec.
     * @param owner Address of the user
     * @return maxShares Maximum number of shares redeemable by `owner`
     */
    function maxRedeem(address owner) public view override returns (uint256 maxShares) {
        if (paused()) return 0;

        uint256 ownerShares = balanceOf(owner);
        uint256 availableLiquidity = _getAvailableLiquidity();
        uint256 maxRedeemableShares = convertToShares(availableLiquidity);

        maxShares = ownerShares < maxRedeemableShares ? ownerShares : maxRedeemableShares;
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
     * @custom:access Requires BVD role
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
     * @custom:access Requires BVD role
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
        // Lazy cleanup: burn ghost dust shares from previous drain.
        // When the vault fully drains (totalAssets == 0), some holders may retain
        // worthless shares. Burning them here on next interaction prevents stale
        // shares from diluting new depositors.
        uint256 recipientDust = balanceOf(to);
        if (recipientDust > 0 && totalAssets() == 0) {
            _burn(to, recipientDust);
        }

        if (shares == 0) revert Errors.ZeroAmount();

        uint256 fee = getEntryFee();

        super._deposit(by, to, assets, shares);

        if (fee != 0) {
            uint256 feeAmount = _feeOnTotal(assets, fee);

            // Transfer entry fee to fee recipient (if fee exists and recipient is not this contract)
            if (feeAmount > 0 && s_vault.feeRecipient != address(this)) {
                i_asset.safeTransfer(s_vault.feeRecipient, feeAmount);
            }
        }

        // Deposit all idle vault balance (current + accumulated dust) to strategies
        // if it meets the minimum threshold. Otherwise, assets stay idle in the vault
        // and are still counted by totalAssets() via balanceOf(address(this)).
        uint256 toDeposit = ERC20(i_asset).balanceOf(address(this));
        if (toDeposit >= MIN_STRATEGY_DEPOSIT) {
            _depositFunds(toDeposit);
        }
    }

    /**
     * @notice Internal function for `withdraw` and `redeem` with exit fee collection
     * @dev Calculates exit fee, withdraws total needed from strategies, sends fee to recipient,
     * then calls the parent `_withdraw` to transfer exact `assets` to the user.
     * @param by The address initiating the withdrawal
     * @param to The address receiving the underlying assets
     * @param owner The address that owns the shares being burned
     * @param assets The amount of underlying assets to send to `to`
     * @param shares The amount of shares to burn
     */
    function _withdraw(address by, address to, address owner, uint256 assets, uint256 shares) internal override {
        uint256 fee = getExitFee();
        uint256 feeAmount = 0;
        uint256 totalToWithdraw = assets;

        if (fee != 0) {
            feeAmount = _feeOnRaw(assets, fee);
            totalToWithdraw = assets.rawAdd(feeAmount);
        }

        // Use idle vault balance first, then pull remainder from strategies
        uint256 vaultBalance = ERC20(i_asset).balanceOf(address(this));
        if (totalToWithdraw > vaultBalance) {
            _withdrawFunds(totalToWithdraw - vaultBalance);
        }

        // Send fee to recipient
        if (feeAmount > 0 && s_vault.feeRecipient != address(this)) {
            i_asset.safeTransfer(s_vault.feeRecipient, feeAmount);
        }

        // Send exact 'assets' amount to user as per ERC4626 spec
        super._withdraw(by, to, owner, assets, shares);

        // Burn owner's remaining dust shares if vault is fully drained.
        // After many deposit/yield/withdraw cycles, double-layer ERC-4626 rounding
        // can drain all strategy shares while leaving a few vault shares (dust).
        // These dust shares are worthless (convertToAssets returns 0) so burning
        // them maintains the solvency invariant: totalSupply > 0 → totalAssets > 0.
        uint256 ownerDust = balanceOf(owner);
        if (ownerDust > 0 && totalAssets() == 0) {
            _burn(owner, ownerDust);
        }
    }

    /**
     * @notice Returns the total available liquidity for withdrawals
     * @dev Sums idle vault balance and max withdrawable from each strategy in the withdraw queue
     * @return liquidity The total amount of assets available for immediate withdrawal
     */
    function _getAvailableLiquidity() internal view returns (uint256 liquidity) {
        liquidity = ERC20(i_asset).balanceOf(address(this));

        uint256[] memory withdrawQueue = s_strategy.withdrawQueue;
        for (uint256 i = 0; i < withdrawQueue.length; i++) {
            liquidity = liquidity.rawAdd(s_strategy.strategies[withdrawQueue[i]].strategy.getMaxWithdrawable());
        }
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

            // Skip strategies with zero cap (defense-in-depth: also handles any
            // stale supply queue entries pointing to deleted strategies)
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
     * @dev When draining a strategy's full position (`assets >= maxWithdrawable`), uses
     *      `withdrawAll()` to prevent orphaned yield from Solady's virtual offset rounding.
     *      Any excess from `withdrawAll()` is re-deposited to keep strategy accounting clean.
     *      For partial withdrawals, uses standard ERC-4626 `withdraw()`.
     * @param assets The total amount of assets to withdraw
     */
    function _withdrawFunds(uint256 assets) internal {
        uint256 i = 0;
        uint256[] memory withdrawQueue = s_strategy.withdrawQueue;
        for (i; i < withdrawQueue.length; i++) {
            DataTypes.Strategy memory strategy = s_strategy.strategies[withdrawQueue[i]];

            // Get maximum withdrawable amount from this strategy
            uint256 maxWithdrawable = strategy.strategy.getMaxWithdrawable();

            if (maxWithdrawable == 0) continue;

            if (assets >= maxWithdrawable) {
                // Full position drain — use withdrawAll to prevent orphaned yield
                uint256 actualWithdrawn = strategy.strategy.withdrawAll();

                // Re-deposit any excess to keep strategy-based accounting clean
                uint256 needed = assets.min(actualWithdrawn);
                uint256 excess = actualWithdrawn - needed;
                if (excess > 0) {
                    strategy.strategy.deposit(excess);
                }

                assets = assets.zeroFloorSub(needed);

                emit BTCVault__WithdrewFromStrategy(withdrawQueue[i], needed);
            } else {
                // Partial withdrawal — standard ERC-4626 path
                strategy.strategy.withdraw(assets);

                emit BTCVault__WithdrewFromStrategy(withdrawQueue[i], assets);

                assets = 0;
            }

            // Exit if all required assets have been withdrawn
            if (assets == 0) return;
        }

        // Revert if insufficient liquidity across all strategies
        if (assets != 0) revert Errors.NotEnoughLiquidity();
    }

    /**
     * @notice Reallocates funds across strategies according to specified allocations
     * @dev Processes withdrawals first, then deposits, ensuring total balance consistency.
     *      Individual strategy withdrawals are wrapped in try/catch so a single failing
     *      strategy (e.g., paused underlying protocol) does not block the entire reallocation.
     *      Failed withdrawals emit `BTCVault__StrategyWithdrawFailed` and are skipped.
     *      The `totalSupplied != totalWithdrawn` invariant still enforces balance consistency.
     * @param allocations Array of allocation instructions specifying target amounts per strategy
     * @custom:security Deposits are NOT wrapped in try/catch — deposit failures revert the
     *      transaction, which is correct: admins should not silently lose funds into broken strategies
     */
    function _reallocateFunds(DataTypes.Allocation[] memory allocations) internal {
        uint256 totalSupplied;
        uint256 totalWithdrawn;

        uint256 i = 0;
        for (i; i < allocations.length; i++) {
            DataTypes.Allocation memory allocation = allocations[i];
            DataTypes.Strategy memory strategy = s_strategy.strategies[allocation.index];

            uint256 currentBalance = strategy.strategy.getAssetBalanceInStrategy();
            uint256 newAllocation = allocation.amount;

            // Calculate if we need to withdraw (current > target)
            uint256 toWithdraw = currentBalance.zeroFloorSub(newAllocation);

            if (toWithdraw > 0) {
                // Withdraw excess funds from strategy — wrapped in try/catch so a single
                // broken strategy does not block reallocation of all other strategies
                try SimpleTokenizedStrategy(strategy.strategy).withdraw(toWithdraw, address(this), address(this)) {
                    totalWithdrawn += toWithdraw;

                    emit BTCVault__WithdrewFromStrategy(allocation.index, toWithdraw);
                } catch (bytes memory reason) {
                    emit BTCVault__StrategyWithdrawFailed(allocation.index, toWithdraw, reason);
                }
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
