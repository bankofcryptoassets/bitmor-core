// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {ERC4626} from "@solady/tokens/ERC4626.sol";

/// @title VaultUtilities
/// @notice Shared utility contract for USDC Vault tests
/// @dev Contains reusable helpers for ERC4626 vault testing
/// @dev Inherits from Test to access vm cheatcodes and assertion functions
abstract contract VaultUtilities is Test {
    // ============ Constants ============

    uint256 internal constant VAULT_UTILITIES_PRECISION = 1e18;
    uint256 internal constant VAULT_UTILITIES_BPS = 10_000;

    // ============ Token Minting Helpers ============

    /// @notice Mint any token to any address using its mint(uint256) hook
    /// @dev Uses a low-level call so mocks can expose mint without a shared interface
    /// @param token The token address to mint
    /// @param to The address to mint to (will be pranked)
    /// @param amount Amount to mint
    function _utilMintTokenTo(address token, address to, uint256 amount) internal {
        vm.prank(to);
        (bool success,) = token.call(abi.encodeWithSignature("mint(uint256)", amount));
        assertTrue(success, "MINT_ERROR");
    }

    /// @notice Mint token and approve spender in a single helper
    /// @dev Combines minting + approval pattern used across multiple test files
    /// @param token The token address to mint
    /// @param to The address to mint to
    /// @param spender The address to approve for spending
    /// @param amount Amount to mint and approve
    function _utilMintTokenAndApprove(address token, address to, address spender, uint256 amount) internal {
        vm.startPrank(to);
        (bool success,) = token.call(abi.encodeWithSignature("mint(uint256)", amount));
        assertTrue(success, "MINT_ERROR");
        IERC20(token).approve(spender, amount);
        vm.stopPrank();
    }

    /// @notice Mint token and approve max spending
    /// @dev Useful for actors that need unlimited approval
    /// @param token The token address to mint
    /// @param to The address to mint to
    /// @param spender The address to approve for spending
    /// @param amount Amount to mint
    function _utilMintTokenAndApproveMax(address token, address to, address spender, uint256 amount) internal {
        vm.startPrank(to);
        (bool success,) = token.call(abi.encodeWithSignature("mint(uint256)", amount));
        assertTrue(success, "MINT_ERROR");
        IERC20(token).approve(spender, type(uint256).max);
        vm.stopPrank();
    }

    // ============ Vault Operation Helpers ============

    /// @notice Deposit assets into an ERC4626 vault
    /// @param vault The vault address
    /// @param depositor The address depositing assets
    /// @param amount The amount of assets to deposit
    /// @return shares The number of shares minted to depositor
    function _utilVaultDeposit(address vault, address depositor, uint256 amount) internal returns (uint256 shares) {
        vm.prank(depositor);
        shares = ERC4626(vault).deposit(amount, depositor);
    }

    /// @notice Withdraw assets from an ERC4626 vault
    /// @param vault The vault address
    /// @param user The address withdrawing assets
    /// @param assets The amount of assets to withdraw
    /// @return shares The number of shares burned
    function _utilVaultWithdraw(address vault, address user, uint256 assets) internal returns (uint256 shares) {
        vm.prank(user);
        shares = ERC4626(vault).withdraw(assets, user, user);
    }

    /// @notice Redeem shares from an ERC4626 vault
    /// @param vault The vault address
    /// @param user The address redeeming shares
    /// @param shares The number of shares to redeem
    /// @return assets The amount of assets returned
    function _utilVaultRedeem(address vault, address user, uint256 shares) internal returns (uint256 assets) {
        vm.prank(user);
        assets = ERC4626(vault).redeem(shares, user, user);
    }

    /// @notice Mint shares in an ERC4626 vault
    /// @param vault The vault address
    /// @param user The address minting shares
    /// @param shares The number of shares to mint
    /// @return assets The amount of assets required
    function _utilVaultMint(address vault, address user, uint256 shares) internal returns (uint256 assets) {
        vm.prank(user);
        assets = ERC4626(vault).mint(shares, user);
    }

    // ============ Vault Query Helpers ============

    /// @notice Get the current share price of an ERC4626 vault
    /// @param vault The vault address
    /// @return sharePrice The share price (scaled to 1e18)
    function _utilGetSharePrice(address vault) internal view returns (uint256) {
        uint256 supply = ERC4626(vault).totalSupply();
        if (supply == 0) return VAULT_UTILITIES_PRECISION;
        return (ERC4626(vault).totalAssets() * VAULT_UTILITIES_PRECISION) / supply;
    }

    /// @notice Get the total assets managed by an ERC4626 vault
    /// @param vault The vault address
    /// @return The total assets in the vault
    function _utilGetVaultTotalAssets(address vault) internal view returns (uint256) {
        return ERC4626(vault).totalAssets();
    }

    /// @notice Get the total supply of shares in an ERC4626 vault
    /// @param vault The vault address
    /// @return The total supply of shares
    function _utilGetVaultTotalSupply(address vault) internal view returns (uint256) {
        return ERC4626(vault).totalSupply();
    }

    /// @notice Get the share balance of an account in an ERC4626 vault
    /// @param vault The vault address
    /// @param account The account to check
    /// @return The share balance
    function _utilGetVaultShareBalance(address vault, address account) internal view returns (uint256) {
        return ERC4626(vault).balanceOf(account);
    }

    // ============ Preview Helpers ============

    /// @notice Preview the amount of shares that would be minted for a deposit
    /// @param vault The vault address
    /// @param assets The amount of assets to deposit
    /// @return The preview shares amount
    function _utilPreviewDeposit(address vault, uint256 assets) internal view returns (uint256) {
        return ERC4626(vault).previewDeposit(assets);
    }

    /// @notice Preview the amount of shares that would be burned for a withdrawal
    /// @param vault The vault address
    /// @param assets The amount of assets to withdraw
    /// @return The preview shares amount
    function _utilPreviewWithdraw(address vault, uint256 assets) internal view returns (uint256) {
        return ERC4626(vault).previewWithdraw(assets);
    }

    /// @notice Preview the amount of assets that would be returned for a redemption
    /// @param vault The vault address
    /// @param shares The amount of shares to redeem
    /// @return The preview assets amount
    function _utilPreviewRedeem(address vault, uint256 shares) internal view returns (uint256) {
        return ERC4626(vault).previewRedeem(shares);
    }

    /// @notice Preview the amount of assets needed to mint shares
    /// @param vault The vault address
    /// @param shares The amount of shares to mint
    /// @return The preview assets amount
    function _utilPreviewMint(address vault, uint256 shares) internal view returns (uint256) {
        return ERC4626(vault).previewMint(shares);
    }

    // ============ Assertion Helpers ============

    /// @notice Assert two values are approximately equal within basis point tolerance
    /// @param actual The actual value
    /// @param expected The expected value
    /// @param toleranceBps The tolerance in basis points (e.g., 100 = 1%)
    /// @param err The error message if assertion fails
    function _utilAssertApproxBps(uint256 actual, uint256 expected, uint256 toleranceBps, string memory err)
        internal
        pure
    {
        if (expected == 0) {
            assertTrue(actual == 0, err);
            return;
        }
        uint256 delta = actual > expected ? actual - expected : expected - actual;
        assertTrue(delta <= (expected * toleranceBps) / VAULT_UTILITIES_BPS, err);
    }

    /// @notice Assert share price has not decreased
    /// @param vault The vault address
    /// @param previousSharePrice The share price before the action
    function _utilAssertSharePriceNotDecreased(address vault, uint256 previousSharePrice) internal view {
        uint256 currentSharePrice = _utilGetSharePrice(vault);
        assertGe(currentSharePrice, previousSharePrice, "Share price decreased");
    }

    /// @notice Assert share price has not decreased beyond tolerance
    /// @param vault The vault address
    /// @param previousSharePrice The share price before the action
    /// @param toleranceBps Maximum allowed decrease in basis points
    function _utilAssertSharePriceNotDecreasedSignificantly(
        address vault,
        uint256 previousSharePrice,
        uint256 toleranceBps
    ) internal view {
        uint256 currentSharePrice = _utilGetSharePrice(vault);
        uint256 minAcceptable = (previousSharePrice * (VAULT_UTILITIES_BPS - toleranceBps)) / VAULT_UTILITIES_BPS;
        assertGe(currentSharePrice, minAcceptable, "Share price decreased beyond tolerance");
    }

    // ============ Time Helpers ============

    /// @notice Warp time by a specific number of seconds
    /// @param seconds_ Number of seconds to warp
    function _utilWarpBy(uint256 seconds_) internal {
        vm.warp(block.timestamp + seconds_);
    }

    /// @notice Warp time by a specific number of days
    /// @param days_ Number of days to warp
    function _utilWarpByDays(uint256 days_) internal {
        vm.warp(block.timestamp + (days_ * 1 days));
    }

    // ============ Min/Max Helpers ============

    /// @notice Returns the minimum of two values
    /// @param a First value
    /// @param b Second value
    /// @return The smaller of the two values
    function _utilMin(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /// @notice Returns the maximum of two values
    /// @param a First value
    /// @param b Second value
    /// @return The larger of the two values
    function _utilMax(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
}
