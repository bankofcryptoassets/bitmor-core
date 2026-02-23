// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title MockYieldSource
/// @author Bitmor Protocol
/// @notice Mock yield source for testing MockTokenizedStrategy deposit/withdraw flows
/// @dev Tracks per-user, per-asset balances without actual token transfers.
///      Used as a stand-in for real protocols like Aave in strategy unit tests.
contract MockYieldSource {
    /// @dev Mapping of user => asset => deposited balance
    mapping(address user => mapping(address asset => uint256 balance)) balances;

    /// @dev When true, withdraw() will revert
    bool public shouldRevertOnWithdraw;

    /// @notice Toggle whether withdraw should revert
    /// @param _shouldRevert Whether to revert on withdraw calls
    function setShouldRevertOnWithdraw(bool _shouldRevert) external {
        shouldRevertOnWithdraw = _shouldRevert;
    }

    /// @notice Records a supply of `amount` of `asset` from the caller
    /// @param asset The asset being supplied
    /// @param amount The amount being supplied
    function supply(address asset, uint256 amount) external {
        balances[msg.sender][asset] += amount;
    }

    /// @notice Records a withdrawal of `amount` of `asset` for the caller
    /// @param asset The asset being withdrawn
    /// @param amount The amount being withdrawn
    function withdraw(address asset, uint256 amount) external {
        if (shouldRevertOnWithdraw) revert("MockYieldSource: paused");
        balances[msg.sender][asset] -= amount;
    }

    /// @notice Returns the tracked balance of `asset` for `user`
    /// @param asset The asset address
    /// @param user The user address
    /// @return The tracked balance
    function balanceOf(address asset, address user) external view returns (uint256) {
        return balances[user][asset];
    }
}
