// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {ERC4626} from "@solady/tokens/ERC4626.sol";

library BTCVaultLogic {
    /**
     * Deposit `btc` into the BTC Vault.
     * @param btcVault Address of the BTC Vault
     * @param amount Amount of `btc`
     * @param to Address which will receive vault shares.
     * @return shares Amount of `bvBTC` shares received.
     */
    function deposit(address btcVault, uint256 amount, address to) internal returns (uint256 shares) {
        shares = ERC4626(btcVault).deposit(amount, to);
    }
}
