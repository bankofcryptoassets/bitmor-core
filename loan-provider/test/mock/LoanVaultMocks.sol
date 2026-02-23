// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

/// @title MockRevertingTarget
/// @author Bitmor Protocol
/// @notice Mock contract that always reverts for testing LoanVault `execute()` error handling
contract MockRevertingTarget {
    /// @notice Always reverts with a descriptive message
    function alwaysReverts() external pure {
        revert("MockRevertingTarget: forced revert");
    }
}

/// @title MockReturnTarget
/// @author Bitmor Protocol
/// @notice Mock contract that stores and returns data for testing LoanVault `execute()` return handling
contract MockReturnTarget {
    /// @notice Value stored by the last `setAndReturnValue` call
    uint256 public storedValue;

    /// @notice Stores `value` and returns `value * 2` for verifying execute return data
    /// @param value The value to store
    /// @return The stored value multiplied by 2
    function setAndReturnValue(uint256 value) external returns (uint256) {
        storedValue = value;
        return value * 2;
    }
}
