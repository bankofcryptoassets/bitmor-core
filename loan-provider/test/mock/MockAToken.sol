// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {MockERC20} from "./MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

/// @title MockAToken
/// @author Bitmor Protocol
/// @notice Mock aToken for unit testing Bitmor lending pool interactions
/// @dev Extends MockERC20 with pool-restricted minting/burning to simulate Aave aToken behavior
contract MockAToken is MockERC20 {
    /// @notice The underlying asset this aToken represents
    address public immutable UNDERLYING_ASSET;

    /// @notice The lending pool that controls minting and burning
    address public immutable POOL;

    /// @notice Thrown when a non-pool address attempts to mint or burn
    error MockAToken__OnlyPool();

    /// @notice Creates a new MockAToken
    /// @param name_ Token name (e.g., "Aave Mock cbBTC")
    /// @param symbol_ Token symbol (e.g., "amcbBTC")
    /// @param decimals_ Number of decimals (should match underlying asset)
    /// @param underlyingAsset_ Address of the underlying asset (e.g., cbBTC)
    /// @param pool_ Address of the lending pool that can mint/burn
    constructor(string memory name_, string memory symbol_, uint8 decimals_, address underlyingAsset_, address pool_)
        MockERC20(name_, symbol_, decimals_)
    {
        UNDERLYING_ASSET = underlyingAsset_;
        POOL = pool_;
        // Approve pool to transfer underlying asset (for withdrawals)
        IERC20(underlyingAsset_).approve(pool_, type(uint256).max);
    }

    /// @notice Mints aTokens to an account (called by pool on deposit)
    /// @dev Overrides MockERC20's unrestricted mint to add pool-only access
    /// @param to The account to mint to
    /// @param amount The amount to mint
    function mint(address to, uint256 amount) external override {
        if (msg.sender != POOL) revert MockAToken__OnlyPool();
        _mint(to, amount);
    }

    /// @notice Burns aTokens from an account (called by pool on withdraw)
    /// @dev Overrides MockERC20's unrestricted burn to add pool-only access
    /// @param from The account to burn from
    /// @param amount The amount to burn
    function burn(address from, uint256 amount) external override {
        if (msg.sender != POOL) revert MockAToken__OnlyPool();
        _burn(from, amount);
    }

    /// @notice Returns the underlying asset address
    /// @dev Matches Aave's IAToken interface
    /// @return The address of the underlying asset
    function UNDERLYING_ASSET_ADDRESS() external view returns (address) {
        return UNDERLYING_ASSET;
    }
}
