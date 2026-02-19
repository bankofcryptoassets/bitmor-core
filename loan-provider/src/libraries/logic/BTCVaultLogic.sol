// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {ERC4626} from "@solady/tokens/ERC4626.sol";

/**
 * @title BTCVaultLogic
 * @author Bitmor Protocol
 * @notice Library for interacting with the BTC Vault (ERC-4626) during loan operations
 * @dev Wraps ERC-4626 calls to the BTCVault for depositing cbBTC, converting shares
 * to underlying assets, and previewing redemption amounts. Used by the Loan contract
 * and LSALogic to manage collateral in the vault.
 */
library BTCVaultLogic {
    /**
     * @notice Deposits `amount` of cbBTC into the BTC Vault on behalf of `to`
     * @param btcVault Address of the BTC Vault (ERC-4626)
     * @param amount Amount of cbBTC to deposit (8 decimals)
     * @param to Address that will receive the bvBTC vault shares
     * @return shares Amount of bvBTC shares received
     */
    function deposit(address btcVault, uint256 amount, address to) internal returns (uint256 shares) {
        shares = ERC4626(btcVault).deposit(amount, to);
    }

    /**
     * @notice Converts a bvBTC `sharesAmount` to its equivalent cbBTC asset value
     * @param btcVault Address of the BTC Vault (ERC-4626)
     * @param sharesAmount Amount of bvBTC shares to convert
     * @return assets Equivalent amount of underlying cbBTC assets
     */
    function convertToAssets(address btcVault, uint256 sharesAmount) internal view returns (uint256 assets) {
        assets = ERC4626(btcVault).convertToAssets(sharesAmount);
    }

    /**
     * @notice Previews the amount of cbBTC assets receivable for redeeming `sharesAmount` of bvBTC
     * @dev Accounts for exit fees and rounding, unlike `convertToAssets`
     * @param btcVault Address of the BTC Vault (ERC-4626)
     * @param sharesAmount Amount of bvBTC shares to preview redemption for
     * @return assets Expected amount of cbBTC assets receivable on redemption
     */
    function previewRedeem(address btcVault, uint256 sharesAmount) internal view returns (uint256 assets) {
        assets = ERC4626(btcVault).previewRedeem(sharesAmount);
    }
}
