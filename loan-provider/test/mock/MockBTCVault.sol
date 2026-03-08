// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC4626} from "@solady/tokens/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

/// @title MockBTCVault
/// @author Bitmor Protocol
/// @notice Simplified ERC-4626 vault for testing - wraps cbBTC into bvBTC shares
/// @dev No strategies, no fees, 1:1 share ratio for testing simplicity.
///      Supports configurable `redeem()` return values for slippage testing.
contract MockBTCVault is ERC4626 {
    address private immutable _underlying;
    string private _name;
    string private _symbol;
    uint8 private immutable _decimals;

    // ============ Slippage Testing Support ============

    /// @dev Mock return value for `redeem()` when slippage testing is enabled
    uint256 private _mockRedeemReturn;

    /// @dev Whether to use mock redeem return instead of actual ERC-4626 calculation
    bool private _useMockRedeemReturn;

    /// @notice Creates a new MockBTCVault
    /// @param underlying_ Address of the underlying BTC token (e.g., cbBTC)
    /// @param name_ Vault token name (e.g., "Bitmor Vault BTC")
    /// @param symbol_ Vault token symbol (e.g., "bvBTC")
    /// @param decimals_ Number of decimals for the underlying asset
    constructor(address underlying_, string memory name_, string memory symbol_, uint8 decimals_) {
        _underlying = underlying_;
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function asset() public view override returns (address) {
        return _underlying;
    }

    function _underlyingDecimals() internal view override returns (uint8) {
        return _decimals;
    }

    /// @notice Test helper - mint shares directly without deposit
    function mint(address to, uint256 shares) external {
        _mint(to, shares);
    }

    /// @notice Test helper - burn shares directly
    function burn(address from, uint256 shares) external {
        _burn(from, shares);
    }

    // ============ Slippage Testing Methods ============

    /// @notice Set a specific return value for redeem() to test slippage scenarios
    /// @dev When set, redeem() will return this amount regardless of actual calculation
    /// @param amount The amount to return from redeem()
    function setMockRedeemReturn(uint256 amount) external {
        _mockRedeemReturn = amount;
        _useMockRedeemReturn = true;
    }

    /// @notice Reset to normal ERC4626 redeem behavior
    function resetMockRedeemReturn() external {
        _useMockRedeemReturn = false;
        _mockRedeemReturn = 0;
    }

    /// @notice Override redeem to allow controlled return values for slippage testing
    /// @dev When _useMockRedeemReturn is true, burns shares but returns mock amount
    /// @param shares Amount of shares to redeem
    /// @param receiver Address to receive assets
    /// @param owner_ Owner of the shares
    /// @return assets Amount of assets transferred (mock or actual)
    function redeem(uint256 shares, address receiver, address owner_) public override returns (uint256 assets) {
        if (_useMockRedeemReturn) {
            // Burn shares from owner (standard ERC4626 behavior)
            if (msg.sender != owner_) {
                uint256 allowed = allowance(owner_, msg.sender);
                if (allowed != type(uint256).max) {
                    _approve(owner_, msg.sender, allowed - shares);
                }
            }
            _burn(owner_, shares);

            // Transfer mock amount to receiver
            IERC20(_underlying).transfer(receiver, _mockRedeemReturn);
            return _mockRedeemReturn;
        }
        return super.redeem(shares, receiver, owner_);
    }
}
