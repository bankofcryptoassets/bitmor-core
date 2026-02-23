// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC4626, ERC20} from "@solady/tokens/ERC4626.sol";
import {Pausable} from "@openzeppelin/utils/Pausable.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {AccessManaged} from "@openzeppelin/access/manager/AccessManaged.sol";

import {Errors} from "../../libraries/helpers/Errors.sol";
import {ISimpleStrategy} from "../../interfaces/ISimpleStrategy.sol";
import {ILendingPool} from "../../interfaces/ILendingPool.sol";

/**
 * @title USDCVault
 * @author Bitmor Protocol
 * @notice ERC-4626 compliant vault for USDC deposits with single-strategy yield generation
 * @dev Extends Solady's ERC4626 with role-based access control and pause functionality.
 * Delegates asset management to a single `ISimpleStrategy` implementation that splits
 * deposits between Aave and the Bitmor Lending Pool.
 *
 * USDC Vault invariants:
 * - totalSupply() MUST equal the sum of bvUSDC.balanceOf(addr) for all holder addresses
 * - If a user deposits X USDC and immediately withdraws (no intervening borrows),
 *   user MUST receive >= X - 1 wei (rounding tolerance)
 *
 * Bitmor single-wei invariant (9.2):
 * Deposits, repayments, and withdrawals of 1 wei MUST either succeed with correct
 * accounting OR revert with a minimum amount check. They MUST NEVER succeed while
 * losing the 1 wei to rounding.
 *
 * Bitmor maximum value invariant (9.3):
 * Operations with type(uint256).max MUST either revert cleanly (overflow protection)
 * OR be bounded to a sensible maximum. They MUST NEVER overflow silently.
 *
 * @custom:security Uses AccessManaged for role-based permissions and Pausable for emergency stops
 */
contract USDCVault is ERC4626, AccessManaged, Pausable {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for address;

    /**
     * @notice Emitted when the strategy contract is updated
     * @param newStrategy The new strategy contract address
     */
    event SimpleVault__StrategyUpdated(address newStrategy);

    /**
     * @notice The underlying asset that the vault accepts (immutable)
     */
    address internal immutable i_asset;

    /// @notice The Bitmor Lending Pool address used for authorized reallocation calls
    address internal immutable i_blp;

    /**
     * @notice The strategy contract that manages yield generation
     */
    ISimpleStrategy private s_strategy;

    /**
     * @notice Initializes the vault with the specified underlying asset
     * @param _manager Access Manager address
     * @param _asset The address of the ERC20 token to be used as the underlying asset
     * @param _blp Bitmor Lending Pool Address
     */
    constructor(address _manager, address _asset, address _blp) AccessManaged(_manager) {
        if (_asset == address(0) || _blp == address(0)) revert Errors.ZeroAddress();
        i_asset = _asset;
        i_blp = _blp;
    }

    /*
       _____      _                        _   _____                 _   _
      | ____|_  _| |_ ___ _ __ _ __   __ _| | |  ___|   _ _ __   ___| |_(_) ___  _ __  ___
      |  _| \ \/ / __/ _ \ '__| '_ \ / _` | | | |_ | | | | '_ \ / __| __| |/ _ \| '_ \/ __|
      | |___ >  <| ||  __/ |  | | | | (_| | | |  _|| |_| | | | | (__| |_| | (_) | | | \__ \
      |_____/_/\_\\__\___|_|  |_| |_|\__,_|_| |_|   \__,_|_| |_|\___|\__|_|\___/|_| |_|___/
    */

    /**
     * @notice Updates the strategy contract used for yield generation
     * @dev Withdraws funds from current strategy before switching to new one
     * @param newStrategy The address of the new strategy contract (cannot be zero address)
     * @custom:access Requires UVC role (1-day delay)
     */
    function setStrategy(address newStrategy) external restricted whenNotPaused {
        if (newStrategy == address(0)) revert Errors.ZeroAddress();

        // Withdraw all funds from current strategy if one exists
        if (address(s_strategy) != address(0)) {
            if (s_strategy.getTotalBalanceInMarkets() > 0) {
                s_strategy.withdrawAllFunds();
            }
            i_asset.safeApprove(address(s_strategy), 0);
        }

        // Approve new strategy to spend vault's assets
        i_asset.safeApprove(newStrategy, type(uint256).max);

        s_strategy = ISimpleStrategy(newStrategy);

        // Deploy idle assets into the new strategy to eliminate yield gap
        uint256 idle = ERC20(i_asset).balanceOf(address(this));
        if (idle > 0) s_strategy.supply(idle);

        emit SimpleVault__StrategyUpdated(newStrategy);
    }

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
    function reallocateAssets() external restricted whenNotPaused {
        s_strategy.reallocateAssets();
    }

    /**
     * @notice Reallocates assets by withdrawing `amountToWithdraw` from Aave to BLP
     * @dev Only callable by the Bitmor Lending Pool to maintain liquidity reserves
     * @param amountToWithdraw The amount of assets to move from Aave into BLP
     * @custom:access Requires UVA role and caller must be `i_blp`
     */
    function reallocateAssets(uint256 amountToWithdraw) external restricted whenNotPaused {
        if (msg.sender != i_blp) revert Errors.UnauthorizedCaller();
        s_strategy.reallocateAssets(amountToWithdraw);
    }

    /**
     * @notice Routes a BLP deposit through the vault so `msg.sender` at the LendingPool is the vault
     * @dev Called by the strategy to deposit assets into the Bitmor Lending Pool.
     * The strategy transfers USDC to the vault first, then the vault deposits into BLP.
     * This ensures the LendingPool sees USDCVault as the caller (not the strategy).
     * @param amount The amount of USDC to deposit into BLP
     * @param onBehalfOf The address that receives the aTokens
     * @custom:access Only callable by the current strategy
     */
    function depositToBLP(uint256 amount, address onBehalfOf) external whenNotPaused {
        if (msg.sender != address(s_strategy)) revert Errors.UnauthorizedCaller();
        if (amount == 0) return;
        i_asset.safeTransferFrom(msg.sender, address(this), amount);
        i_asset.safeApprove(i_blp, amount);
        ILendingPool(i_blp).deposit(i_asset, amount, onBehalfOf, 0);
    }

    /**
     * @notice Updates the minimum delta threshold for triggering asset reallocation
     * @param newMinimumDeltaRequired The new minimum delta in basis points
     * @custom:access Requires UVC role
     */
    function updateMinimumDeltaRequired(uint256 newMinimumDeltaRequired) external restricted whenNotPaused {
        s_strategy.updateMinimumDeltaRequired(newMinimumDeltaRequired);
    }

    function updateExternalAllocation(uint256 externalAllocation) external restricted whenNotPaused {
        s_strategy.updateExternalAllocation(externalAllocation);
    }

    /**
     * @notice Pauses all vault operations in case of emergency
     * @custom:access Requires UVM_FAST role
     */
    function pause() external restricted whenNotPaused {
        _pause();
    }

    /**
     * @notice Resumes vault operations after an emergency pause
     * @custom:access Requires UVM_SLOW role (1-day delay)
     */
    function unpause() external restricted whenPaused {
        _unpause();
    }

    /// @notice Returns the address of the current strategy contract.
    function getStrategy() external view returns (address) {
        return address(s_strategy);
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
        return "Bitmor USDC Vault";
    }

    /**
     * @notice Returns the symbol of the vault token
     * @inheritdoc ERC20
     * @return The vault token symbol
     */
    function symbol() public pure override returns (string memory) {
        return "bvUSDC";
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
     * @notice Returns the total amount of assets under management
     * @inheritdoc ERC4626
     * @dev Delegates to the strategy contract to calculate total assets across all positions.
     *
     * USDC Vault invariant:
     * - MUST equal ERC20(i_asset).balanceOf(address(vault)) + s_strategy.totalAssets()
     * @return assets The total amount of underlying assets managed by the vault
     */
    function totalAssets() public view override returns (uint256 assets) {
        if (address(s_strategy) == address(0)) return ERC20(i_asset).balanceOf(address(this));
        assets = s_strategy.totalAssets() + ERC20(i_asset).balanceOf(address(this));
    }

    /**
     * @notice Deposits `assets` into the vault and mints shares to `to`
     * @inheritdoc ERC4626
     * @dev USDC Vault invariant:
     * - MUST allow any address to deposit USDC
     * - MUST NOT restrict deposit access (no role or allowlist gating)
     * @param assets The amount of underlying assets to deposit (must be non-zero)
     * @param to The address to receive the minted shares
     * @return shares The amount of shares minted
     */
    function deposit(uint256 assets, address to) public override whenNotPaused returns (uint256 shares) {
        if (assets == 0) revert Errors.ZeroAmount();
        return super.deposit(assets, to);
    }

    /**
     * @notice Mints exact `shares` to `to` by depositing the required amount of assets
     * @inheritdoc ERC4626
     * @param shares The exact amount of shares to mint
     * @param to The address to receive the minted shares
     * @return assets The amount of assets deposited
     */
    function mint(uint256 shares, address to) public override whenNotPaused returns (uint256 assets) {
        return super.mint(shares, to);
    }

    /**
     * @notice Withdraws exact `assets` from the vault by burning shares from `owner`
     * @inheritdoc ERC4626
     * @dev USDC Vault invariant:
     * - If a user deposits X USDC and immediately withdraws (no intervening borrows),
     *   user MUST receive >= X - 1 wei (rounding tolerance)
     * @param assets The exact amount of assets to withdraw
     * @param to The address to receive the withdrawn assets
     * @param owner The address whose shares will be burned
     * @return shares The amount of shares burned
     */
    function withdraw(uint256 assets, address to, address owner)
        public
        override
        whenNotPaused
        returns (uint256 shares)
    {
        return super.withdraw(assets, to, owner);
    }

    /**
     * @notice Redeems `shares` for the corresponding amount of assets
     * @inheritdoc ERC4626
     * @param shares The amount of shares to redeem
     * @param to The address to receive the underlying assets
     * @param owner The address whose shares will be burned
     * @return assets The amount of assets received
     */
    function redeem(uint256 shares, address to, address owner) public override whenNotPaused returns (uint256 assets) {
        return super.redeem(shares, to, owner);
    }

    /**
     * @notice Returns the maximum amount of assets that `owner` can withdraw
     * @dev Caps the ERC-4626 default at the strategy's actual withdrawable liquidity.
     *      `totalAssets()` includes lent-out BLP funds for correct share pricing,
     *      but those funds are not available for immediate withdrawal.
     *
     * USDC Vault invariants:
     * - maxWithdraw(`owner`) MUST equal min(`owner`'s share value,
     *   USDC balance in BLP's aToken contract + Aave aUSDC held by USDCStrategy)
     * - Withdrawal MUST succeed if amount <= maxWithdraw(`owner`)
     * - Withdrawal MUST revert if amount > maxWithdraw(`owner`)
     * @param owner The address to check maximum withdrawal for
     * @return maxAssets The maximum amount of underlying assets withdrawable by `owner`
     */
    function maxWithdraw(address owner) public view override returns (uint256 maxAssets) {
        if (paused() || address(s_strategy) == address(0)) return 0;
        uint256 ownerAssets = convertToAssets(balanceOf(owner));
        uint256 available = s_strategy.withdrawableAssets() + ERC20(i_asset).balanceOf(address(this));
        maxAssets = ownerAssets < available ? ownerAssets : available;
    }

    /**
     * @notice Returns the maximum amount of shares that `owner` can redeem
     * @dev Converts the liquidity-capped `maxWithdraw` back to shares
     * @param owner The address to check maximum redemption for
     * @return maxShares The maximum number of shares redeemable by `owner`
     */
    function maxRedeem(address owner) public view override returns (uint256 maxShares) {
        if (paused() || address(s_strategy) == address(0)) return 0;
        uint256 ownerShares = balanceOf(owner);
        uint256 available = s_strategy.withdrawableAssets() + ERC20(i_asset).balanceOf(address(this));
        uint256 maxRedeemableShares = convertToShares(available);
        maxShares = ownerShares < maxRedeemableShares ? ownerShares : maxRedeemableShares;
    }

    /// @notice Returns 0 when paused or when strategy is not set as per ERC-4626 spec.
    function maxDeposit(address) public view override returns (uint256) {
        if (paused() || address(s_strategy) == address(0)) return 0;
        return type(uint256).max;
    }

    /// @notice Returns 0 when paused or when strategy is not set as per ERC-4626 spec.
    function maxMint(address) public view override returns (uint256) {
        if (paused() || address(s_strategy) == address(0)) return 0;
        return type(uint256).max;
    }

    /*
       ___       _                        _   _____                 _   _
      |_ _|_ __ | |_ ___ _ __ _ __   __ _| | |  ___|   _ _ __   ___| |_(_) ___  _ __  ___
       | || '_ \| __/ _ \ '__| '_ \ / _` | | | |_ | | | | '_ \ / __| __| |/ _ \| '_ \/ __|
       | || | | | ||  __/ |  | | | | (_| | | |  _|| |_| | | | | (__| |_| | (_) | | | \__ \
      |___|_| |_|\__\___|_|  |_| |_|\__,_|_| |_|   \__,_|_| |_|\___|\__|_|\___/|_| |_|___/
    */

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
     * @notice Hook called after a deposit to deploy assets into the strategy
     * @param assets The amount of assets deposited
     * @param shares The amount of shares minted (unused)
     */
    function _afterDeposit(uint256 assets, uint256 shares) internal override {
        s_strategy.supply(assets);
    }

    /**
     * @notice Hook called before a withdrawal to retrieve assets from the strategy
     * @param assets The amount of assets to withdraw
     * @param shares The amount of shares being burned (unused)
     */
    function _beforeWithdraw(uint256 assets, uint256 shares) internal override {
        // Withdraw assets from strategy
        s_strategy.withdraw(assets);
    }
}
