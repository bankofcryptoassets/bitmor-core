// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC4626, ERC20} from "@solady/tokens/ERC4626.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";

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

    /**
     * @notice The yield-generating protocol or contract address (e.g., Aave pool, Morpho vault)
     */
    address public immutable i_yieldSource;

    /**
     * @notice The vault contract that owns and manages this strategy
     */
    address public immutable i_vault;

    /**
     * @notice The underlying asset that this strategy accepts and manages
     */
    address private immutable i_asset;

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
    constructor(address yieldSource_, address vault_) {
        i_yieldSource = yieldSource_;
        i_vault = vault_;

        // Query vault for its underlying asset to ensure compatibility
        bytes memory data = i_vault.functionStaticCall(abi.encodeWithSignature("asset()"));

        i_asset = abi.decode(data, (address));
    }

    /**
     * @notice Returns the underlying asset managed by this strategy
     * @inheritdoc ERC4626
     * @return assetAddress The address of the underlying ERC20 token
     */
    function asset() public view override returns (address assetAddress) {
        return i_asset;
    }

    /**
     * @notice Returns the number of decimals used by the underlying asset
     * @inheritdoc ERC4626
     * @dev Used internally for precise share calculations
     * @return The number of decimals of the underlying asset
     */
    function _underlyingDecimals() internal view override returns (uint8) {
        return ERC20(asset()).decimals();
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
     * @notice Internal deposit hook that guards against zero-share mints
     * @dev Defense-in-depth: prevents donation attacks at the strategy level.
     *      If share price is inflated such that `shares` rounds to 0, the depositor
     *      would lose their assets. This guard reverts instead.
     * @param by Address where the `assets` will be transferred from
     * @param to Address where the `shares` will be minted to
     * @param assets The amount of underlying assets to deposit
     * @param shares The amount of shares to mint
     */
    function _deposit(address by, address to, uint256 assets, uint256 shares) internal virtual override {
        if (shares == 0) revert Errors.ZeroAmount();
        super._deposit(by, to, assets, shares);
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
     * @dev Prevents orphaned yield caused by Solady's virtual offset when share count is low.
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
        SafeTransferLib.safeTransfer(asset(), i_vault, assets);
    }
}
