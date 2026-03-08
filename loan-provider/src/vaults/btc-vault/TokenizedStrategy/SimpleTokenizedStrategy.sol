// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Errors} from "../../../libraries/helpers/Errors.sol";

/**
 * @title SimpleTokenizedStrategy
 * @notice Abstract base contract for tokenized strategies that act as ERC-4626 vaults
 * @dev Inspired by Yearn's Tokenized Strategy architecture. Strategy itself is a vault that deposits into yield sources
 * @custom:security Ensures compatibility with vault's asset through immutable asset address
 * @author Bitmor Protocol
 */
abstract contract SimpleTokenizedStrategy is ERC4626 {
    using Address for address;
    using SafeERC20 for IERC20;

    /**
     * @notice The yield-generating protocol or contract address (e.g., Aave pool, Morpho vault)
     */
    address public immutable i_yieldSource;

    /**
     * @notice The vault contract that owns and manages this strategy
     */
    address public immutable i_vault;

    /// @notice Restricts function access to the vault contract only
    /// @custom:security Critical access control - prevents direct strategy manipulation bypassing vault accounting
    modifier onlyVault() {
        if (msg.sender != i_vault) revert Errors.UnauthorizedCaller();
        _;
    }

    /**
     * @notice Initializes the tokenized strategy with yield source and vault
     * @dev Automatically queries vault for asset address to ensure compatibility
     * @param yieldSource_ The address of the yield-generating protocol
     * @param vault_ The address of the vault that will manage this strategy
     */
    constructor(address yieldSource_, address vault_)
        ERC20("TokenizedStrategy", "TS")
        ERC4626(IERC20(abi.decode(Address.functionStaticCall(vault_, abi.encodeWithSignature("asset()")), (address))))
    {
        i_yieldSource = yieldSource_;
        i_vault = vault_;
    }

    /**
     * @notice Returns the total amount of assets under management by this strategy
     * @inheritdoc ERC4626
     * @dev Must be implemented by derived contracts to return actual deployed assets
     * @return assets The total amount of underlying assets managed by the strategy
     */
    function totalAssets() public view virtual override returns (uint256 assets) {
        return 0;
    }

    /**
     * @notice Hook called after assets are deposited into the strategy
     * @dev Override in derived strategies to deploy assets to yield source
     * @param assets The amount of assets deposited
     * @param shares The amount of shares minted
     */
    function _afterDeposit(uint256 assets, uint256 shares) internal virtual {}

    /**
     * @notice Hook called before assets are withdrawn from the strategy
     * @dev Override in derived strategies to retrieve assets from yield source
     * @param assets The amount of assets to withdraw
     * @param shares The amount of shares to burn
     */
    function _beforeWithdraw(uint256 assets, uint256 shares) internal virtual {}

    /**
     * @notice Internal deposit that guards against zero-share mints and calls the after-deposit hook
     * @dev Defense-in-depth: prevents donation attacks at the strategy level.
     *      If share price is inflated such that `shares` rounds to 0, the depositor
     *      would lose their assets. This guard reverts instead.
     * @param caller Address where the `assets` will be transferred from
     * @param receiver Address where the `shares` will be minted to
     * @param assets The amount of underlying assets to deposit
     * @param shares The amount of shares to mint
     */
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual override {
        if (shares == 0) revert Errors.ZeroAmount();
        super._deposit(caller, receiver, assets, shares);
        _afterDeposit(assets, shares);
    }

    /**
     * @notice Internal withdraw that calls the before-withdraw hook before executing
     * @param caller Address initiating the withdrawal
     * @param receiver Address that will receive the assets
     * @param owner Address whose shares will be burned
     * @param assets The amount of underlying assets to withdraw
     * @param shares The amount of shares to burn
     */
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        virtual
        override
    {
        _beforeWithdraw(assets, shares);
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    /// @inheritdoc ERC4626
    function deposit(uint256 assets, address to) public override onlyVault returns (uint256) {
        return super.deposit(assets, to);
    }

    /// @inheritdoc ERC4626
    function mint(uint256 shares, address to) public override onlyVault returns (uint256) {
        return super.mint(shares, to);
    }

    /**
     * @inheritdoc ERC4626
     * @dev Invariant 6.10: There MUST be no silent loss during withdrawal. BTC received from
     * the strategy MUST be >= `shares_burned * previewRedeem(shares) - s_slippage_sharesToAsset`.
     */
    function withdraw(uint256 assets, address to, address owner) public override onlyVault returns (uint256) {
        return super.withdraw(assets, to, owner);
    }

    /// @inheritdoc ERC4626
    function redeem(uint256 shares, address to, address owner) public override onlyVault returns (uint256) {
        return super.redeem(shares, to, owner);
    }

    /**
     * @notice Withdraws ALL assets from the strategy, bypassing ERC-4626 share conversion
     * @dev Prevents orphaned yield caused by ERC4626's virtual offset when share count is low.
     *      When `totalSupply` is small relative to `totalAssets`, `convertToAssets(shares)` returns
     *      significantly less than actual assets (e.g., 2/3 with 2 shares). This function reads the
     *      raw `totalAssets()` balance, withdraws it from the yield source, burns all vault shares,
     *      and transfers everything to the vault.
     *
     * Invariant 6.10: There MUST be no silent loss during withdrawal from a strategy. BTC received
     * from the strategy MUST be >= `shares_burned * previewRedeem(shares) - s_slippage_sharesToAsset`.
     * This function bypasses ERC-4626 conversion and withdraws the full `totalAssets()` balance to
     * ensure no assets are silently lost to rounding.
     * @return assets The total assets withdrawn and transferred to the vault
     * @custom:access Only callable by the vault contract
     */
    function withdrawAll() external virtual onlyVault returns (uint256 assets) {
        assets = totalAssets();
        if (assets == 0) return 0;

        uint256 shares = balanceOf(i_vault);

        // Hook: withdraw all assets from yield source (e.g., Aave)
        _beforeWithdraw(assets, shares);

        // Burn vault's strategy shares
        if (shares > 0) _burn(i_vault, shares);

        // Transfer ALL underlying assets to vault
        IERC20(asset()).safeTransfer(i_vault, assets);
    }
}
