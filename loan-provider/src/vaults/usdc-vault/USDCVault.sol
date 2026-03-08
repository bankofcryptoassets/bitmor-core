// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20Upgradeable, IERC20Metadata} from "@openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {AccessManagedUpgradeable} from "@openzeppelin-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/utils/PausableUpgradeable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

import {Errors} from "../../libraries/helpers/Errors.sol";
import {ISimpleStrategy} from "../../interfaces/ISimpleStrategy.sol";
import {ILendingPool} from "../../interfaces/ILendingPool.sol";

/**
 * @title USDCVault
 * @author Bitmor Protocol
 * @notice ERC-4626 compliant vault for USDC deposits with single-strategy yield generation
 * @dev Extends OZ ERC4626Upgradeable with role-based access control and pause functionality.
 * Delegates asset management to a single `ISimpleStrategy` implementation that splits
 * deposits between Aave and the Bitmor Lending Pool. Uses UUPS proxy pattern.
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
contract USDCVault is
    Initializable,
    UUPSUpgradeable,
    ERC4626Upgradeable,
    AccessManagedUpgradeable,
    PausableUpgradeable
{
    using FixedPointMathLib for uint256;
    using SafeERC20 for IERC20;

    /**
     * @notice Emitted when the strategy contract is updated
     * @param newStrategy The new strategy contract address
     */
    event SimpleVault__StrategyUpdated(address newStrategy);

    // ============ ERC-7201 Namespaced Storage ============

    bytes32 private constant USDCVAULT_STORAGE_LOCATION =
        0x728a56a58f48f7b9249abe79c2552224dd8053fe816600515235618f0b2cf500;

    /// @custom:storage-location erc7201:bitmor.storage.USDCVault
    struct USDCVaultStorageData {
        /// @dev Underlying asset address (USDC), set once in initialize
        address asset;
        /// @dev Bitmor Lending Pool address, set once in initialize
        address blp;
        /// @dev Strategy contract that manages yield generation
        ISimpleStrategy strategy;
    }

    function _getUSDCVaultStorage() internal pure returns (USDCVaultStorageData storage $) {
        assembly {
            $.slot := USDCVAULT_STORAGE_LOCATION
        }
    }

    // ============ Constructor & Initializer ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the vault with the specified underlying asset
     * @param _manager Access Manager address
     * @param _asset The address of the ERC20 token to be used as the underlying asset
     * @param _blp Bitmor Lending Pool Address
     */
    function initialize(address _manager, address _asset, address _blp) public initializer {
        if (_asset == address(0) || _blp == address(0)) revert Errors.ZeroAddress();

        __ERC20_init("Bitmor USDC Vault", "bvUSDC");
        __ERC4626_init(IERC20(_asset));
        __AccessManaged_init(_manager);
        __Pausable_init();

        USDCVaultStorageData storage $ = _getUSDCVaultStorage();
        $.asset = _asset;
        $.blp = _blp;
    }

    /**
     * @notice Authorizes contract upgrades
     * @dev Only callable by addresses with the appropriate AccessManager role
     * @param newImplementation Address of the new implementation
     * @custom:access Requires upgrade role via AccessManager
     */
    function _authorizeUpgrade(address newImplementation) internal override restricted {}

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

        USDCVaultStorageData storage $ = _getUSDCVaultStorage();

        // Withdraw all funds from current strategy if one exists
        if (address($.strategy) != address(0)) {
            if ($.strategy.getTotalBalanceInMarkets() > 0) {
                $.strategy.withdrawAllFunds();
            }
            IERC20($.asset).forceApprove(address($.strategy), 0);
        }

        // Approve new strategy to spend vault's assets
        IERC20($.asset).forceApprove(newStrategy, type(uint256).max);

        $.strategy = ISimpleStrategy(newStrategy);

        // Deploy idle assets into the new strategy to eliminate yield gap
        uint256 idle = IERC20($.asset).balanceOf(address(this));
        if (idle > 0) $.strategy.supply(idle);

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
        _getUSDCVaultStorage().strategy.reallocateAssets();
    }

    /**
     * @notice Reallocates assets by withdrawing `amountToWithdraw` from Aave to BLP
     * @dev Only callable by the Bitmor Lending Pool to maintain liquidity reserves
     * @param amountToWithdraw The amount of assets to move from Aave into BLP
     * @custom:access Requires UVA role and caller must be `blp`
     */
    function reallocateAssets(uint256 amountToWithdraw) external restricted whenNotPaused {
        USDCVaultStorageData storage $ = _getUSDCVaultStorage();
        if (msg.sender != $.blp) revert Errors.UnauthorizedCaller();
        $.strategy.reallocateAssets(amountToWithdraw);
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
        USDCVaultStorageData storage $ = _getUSDCVaultStorage();
        if (msg.sender != address($.strategy)) revert Errors.UnauthorizedCaller();
        if (amount == 0) return;
        IERC20($.asset).safeTransferFrom(msg.sender, address(this), amount);
        IERC20($.asset).forceApprove($.blp, amount);
        ILendingPool($.blp).deposit($.asset, amount, onBehalfOf, 0);
    }

    /**
     * @notice Updates the minimum delta threshold for triggering asset reallocation
     * @param newMinimumDeltaRequired The new minimum delta in basis points
     * @custom:access Requires UVC role
     */
    function updateMinimumDeltaRequired(uint256 newMinimumDeltaRequired) external restricted whenNotPaused {
        _getUSDCVaultStorage().strategy.updateMinimumDeltaRequired(newMinimumDeltaRequired);
    }

    function updateExternalAllocation(uint256 externalAllocation) external restricted whenNotPaused {
        _getUSDCVaultStorage().strategy.updateExternalAllocation(externalAllocation);
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
        return address(_getUSDCVaultStorage().strategy);
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
     * @return The vault token name
     */
    function name() public pure override(ERC20Upgradeable, IERC20Metadata) returns (string memory) {
        return "Bitmor USDC Vault";
    }

    /**
     * @notice Returns the symbol of the vault token
     * @return The vault token symbol
     */
    function symbol() public pure override(ERC20Upgradeable, IERC20Metadata) returns (string memory) {
        return "bvUSDC";
    }

    /**
     * @notice Returns the address of the underlying asset
     * @return The address of the underlying ERC20 token
     */
    function asset() public view override returns (address) {
        return _getUSDCVaultStorage().asset;
    }

    /**
     * @notice Returns the total amount of assets under management
     * @dev Delegates to the strategy contract to calculate total assets across all positions.
     *
     * USDC Vault invariant:
     * - MUST equal IERC20(asset).balanceOf(address(vault)) + strategy.totalAssets()
     * @return assets The total amount of underlying assets managed by the vault
     */
    function totalAssets() public view override returns (uint256 assets) {
        USDCVaultStorageData storage $ = _getUSDCVaultStorage();
        if (address($.strategy) == address(0)) return IERC20($.asset).balanceOf(address(this));
        assets = $.strategy.totalAssets() + IERC20($.asset).balanceOf(address(this));
    }

    /**
     * @notice Deposits `assets` into the vault and mints shares to `to`
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
     * @param shares The exact amount of shares to mint
     * @param to The address to receive the minted shares
     * @return assets The amount of assets deposited
     */
    function mint(uint256 shares, address to) public override whenNotPaused returns (uint256 assets) {
        return super.mint(shares, to);
    }

    /**
     * @notice Withdraws exact `assets` from the vault by burning shares from `owner`
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
        USDCVaultStorageData storage $ = _getUSDCVaultStorage();
        if (paused() || address($.strategy) == address(0)) return 0;
        uint256 ownerAssets = convertToAssets(balanceOf(owner));
        uint256 available = $.strategy.withdrawableAssets() + IERC20($.asset).balanceOf(address(this));
        maxAssets = ownerAssets < available ? ownerAssets : available;
    }

    /**
     * @notice Returns the maximum amount of shares that `owner` can redeem
     * @dev Converts the liquidity-capped `maxWithdraw` back to shares
     * @param owner The address to check maximum redemption for
     * @return maxShares The maximum number of shares redeemable by `owner`
     */
    function maxRedeem(address owner) public view override returns (uint256 maxShares) {
        USDCVaultStorageData storage $ = _getUSDCVaultStorage();
        if (paused() || address($.strategy) == address(0)) return 0;
        uint256 ownerShares = balanceOf(owner);
        uint256 available = $.strategy.withdrawableAssets() + IERC20($.asset).balanceOf(address(this));
        uint256 maxRedeemableShares = convertToShares(available);
        maxShares = ownerShares < maxRedeemableShares ? ownerShares : maxRedeemableShares;
    }

    /// @notice Returns 0 when paused or when strategy is not set as per ERC-4626 spec.
    function maxDeposit(address) public view override returns (uint256) {
        if (paused() || address(_getUSDCVaultStorage().strategy) == address(0)) return 0;
        return type(uint256).max;
    }

    /// @notice Returns 0 when paused or when strategy is not set as per ERC-4626 spec.
    function maxMint(address) public view override returns (uint256) {
        if (paused() || address(_getUSDCVaultStorage().strategy) == address(0)) return 0;
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
     * @notice Internal deposit hook — deploys assets into the strategy after minting shares
     * @dev Called after assets are transferred in and shares are minted.
     * @param caller Address where the `assets` will be transferred from
     * @param to Address where the `shares` will be minted to
     * @param assets The amount of underlying assets deposited
     * @param shares The amount of shares minted
     */
    function _deposit(address caller, address to, uint256 assets, uint256 shares) internal override {
        super._deposit(caller, to, assets, shares);
        _getUSDCVaultStorage().strategy.supply(assets);
    }

    /**
     * @notice Internal withdraw hook — retrieves assets from the strategy before burning shares
     * @dev Withdraws from strategy first, then executes the standard ERC4626 withdrawal
     * (burn shares + transfer assets).
     * @param caller The address initiating the withdrawal
     * @param to The address receiving the underlying assets
     * @param owner The address that owns the shares being burned
     * @param assets The amount of underlying assets to withdraw
     * @param shares The amount of shares to burn
     */
    function _withdraw(address caller, address to, address owner, uint256 assets, uint256 shares) internal override {
        _getUSDCVaultStorage().strategy.withdraw(assets);
        super._withdraw(caller, to, owner, assets, shares);
    }
}
