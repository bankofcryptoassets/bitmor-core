// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IReserveInterestRateStrategy} from "@bitmor/interfaces/IReserveInterestRateStrategy.sol";

/// @title MockInterestRateStrategy
/// @author Bitmor Protocol
/// @notice Mock interest rate strategy for unit testing
contract MockInterestRateStrategy is IReserveInterestRateStrategy {
    /// @notice Base variable borrow rate (default: 2% in RAY)
    uint256 private _baseVariableBorrowRate = 0.02e27;

    /// @notice Max variable borrow rate (default: 20% in RAY)
    uint256 private _maxVariableBorrowRate = 0.2e27;

    /// @notice Returns the base variable borrow rate
    function baseVariableBorrowRate() external view override returns (uint256) {
        return _baseVariableBorrowRate;
    }

    /// @notice Returns the max variable borrow rate
    function getMaxVariableBorrowRate() external view override returns (uint256) {
        return _maxVariableBorrowRate;
    }

    /// @notice Calculate interest rates (simple mock implementation)
    function calculateInterestRates(address, uint256, uint256, uint256, uint256, uint256)
        external
        pure
        override
        returns (uint256, uint256, uint256)
    {
        // Return simple constant rates: liquidityRate, stableBorrowRate, variableBorrowRate
        return (0.01e27, 0.05e27, 0.05e27);
    }

    /// @notice Calculate interest rates with aToken (simple mock implementation)
    function calculateInterestRates(address, address, uint256, uint256, uint256, uint256, uint256, uint256)
        external
        pure
        override
        returns (uint256, uint256, uint256)
    {
        // Return simple constant rates
        return (0.01e27, 0.05e27, 0.05e27);
    }

    /// @notice Set the max variable borrow rate (test helper)
    function setMaxVariableBorrowRate(uint256 rate) external {
        _maxVariableBorrowRate = rate;
    }

    /// @notice Set the base variable borrow rate (test helper)
    function setBaseVariableBorrowRate(uint256 rate) external {
        _baseVariableBorrowRate = rate;
    }
}
