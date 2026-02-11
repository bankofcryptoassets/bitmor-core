// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Address} from "@openzeppelin/utils/Address.sol";
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
     * @notice Withdraws ALL assets from the strategy, bypassing ERC-4626 share conversion
     * @dev Prevents orphaned yield caused by Solady's virtual offset when share count is low.
     *      When `totalSupply` is small relative to `totalAssets`, `convertToAssets(shares)` returns
     *      significantly less than actual assets (e.g., 2/3 with 2 shares). This function reads the
     *      raw `totalAssets()` balance, withdraws it from the yield source, burns all vault shares,
     *      and transfers everything to the vault.
     * @return assets The total assets withdrawn and transferred to the vault
     * @custom:access Only callable by the vault contract
     */
    function withdrawAll() external virtual returns (uint256 assets) {
        if (msg.sender != i_vault) revert Errors.UnauthorizedCaller();

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
