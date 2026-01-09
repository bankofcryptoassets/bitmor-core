// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

/// @title MockRevertingTarget
/// @notice Mock contract that always reverts for testing execute error handling
contract MockRevertingTarget {
    function alwaysReverts() external pure {
        revert("MockRevertingTarget: forced revert");
    }
}

/// @title MockReturnTarget
/// @notice Mock contract that returns data for testing execute return handling
contract MockReturnTarget {
    uint256 public storedValue;

    function setAndReturnValue(uint256 value) external returns (uint256) {
        storedValue = value;
        return value * 2;
    }
}
