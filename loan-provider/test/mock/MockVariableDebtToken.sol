// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {MockERC20} from "./MockERC20.sol";

/// @title MockVariableDebtToken
/// @author Bitmor Protocol
/// @notice Mock variable debt token for unit testing Bitmor lending pool interactions
/// @dev Extends MockERC20 with pool-restricted minting/burning to simulate Aave variable debt token behavior
contract MockVariableDebtToken is MockERC20 {
    /// @notice The underlying asset this debt token represents
    address public immutable UNDERLYING_ASSET;

    /// @notice The lending pool that controls minting and burning
    address public immutable POOL;

    /// @notice Thrown when a non-pool address attempts to mint or burn
    error MockVariableDebtToken__OnlyPool();

    /// @notice Creates a new MockVariableDebtToken
    /// @param name_ Token name (e.g., "Aave Mock Variable Debt USDC")
    /// @param symbol_ Token symbol (e.g., "variableDebtUSDC")
    /// @param decimals_ Number of decimals (should match underlying asset)
    /// @param underlyingAsset_ Address of the underlying asset (e.g., USDC)
    /// @param pool_ Address of the lending pool that can mint/burn
    constructor(string memory name_, string memory symbol_, uint8 decimals_, address underlyingAsset_, address pool_)
        MockERC20(name_, symbol_, decimals_)
    {
        UNDERLYING_ASSET = underlyingAsset_;
        POOL = pool_;
    }

    /// @notice Mints debt tokens to an account (called by pool on borrow)
    /// @dev Overrides MockERC20's unrestricted mint to add pool-only access
    /// @param to The account to mint to
    /// @param amount The amount to mint
    function mint(address to, uint256 amount) external override {
        if (msg.sender != POOL) revert MockVariableDebtToken__OnlyPool();
        _mint(to, amount);
    }

    /// @notice Burns debt tokens from an account (called by pool on repay)
    /// @dev Overrides MockERC20's unrestricted burn to add pool-only access
    /// @param from The account to burn from
    /// @param amount The amount to burn
    function burn(address from, uint256 amount) external override {
        if (msg.sender != POOL) revert MockVariableDebtToken__OnlyPool();
        _burn(from, amount);
    }

    /// @notice Returns the underlying asset address
    /// @dev Matches Aave's IVariableDebtToken interface
    /// @return The address of the underlying asset
    function UNDERLYING_ASSET_ADDRESS() external view returns (address) {
        return UNDERLYING_ASSET;
    }

    // ============ Credit Delegation ============

    /// @notice Mapping of borrower => delegatee => amount
    mapping(address => mapping(address => uint256)) private _borrowAllowances;

    /// @notice Approves a delegatee to borrow on behalf of the caller
    /// @dev Required for LSA to delegate credit to the Loan contract
    /// @param delegatee The address being granted delegation rights
    /// @param amount The maximum amount that can be borrowed
    function approveDelegation(address delegatee, uint256 amount) external {
        _borrowAllowances[msg.sender][delegatee] = amount;
    }

    /// @notice Returns the delegation allowance
    /// @param fromUser The user who delegated
    /// @param toUser The delegatee
    /// @return The delegated amount
    function borrowAllowance(address fromUser, address toUser) external view returns (uint256) {
        return _borrowAllowances[fromUser][toUser];
    }
}
