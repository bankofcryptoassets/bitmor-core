// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IReserveInterestRateStrategy} from "@bitmor/interfaces/IReserveInterestRateStrategy.sol";

/// @title MockInterestRateStrategy
/// @author Bitmor Protocol
/// @notice Simplified mock interest rate strategy that returns constant rates
/// @dev Returns fixed rates (1% liquidity, 5% stable, 5% variable) regardless of utilization.
///      Use MockDefaultInterestRateStrategy or MockUSDCInterestRateStrategy for
///      utilization-based rate testing.
contract MockInterestRateStrategy is IReserveInterestRateStrategy {
    /// @dev Base variable borrow rate (default: 2% in RAY)
    uint256 private _baseVariableBorrowRate = 0.02e27;

    /// @dev Max variable borrow rate (default: 20% in RAY)
    uint256 private _maxVariableBorrowRate = 0.2e27;

    /// @inheritdoc IReserveInterestRateStrategy
    function baseVariableBorrowRate() external view override returns (uint256) {
        return _baseVariableBorrowRate;
    }

    /// @inheritdoc IReserveInterestRateStrategy
    function getMaxVariableBorrowRate() external view override returns (uint256) {
        return _maxVariableBorrowRate;
    }

    /// @inheritdoc IReserveInterestRateStrategy
    /// @dev Returns constant rates: 1% liquidity, 5% stable, 5% variable (all in RAY)
    function calculateInterestRates(address, uint256, uint256, uint256, uint256, uint256)
        external
        pure
        override
        returns (uint256, uint256, uint256)
    {
        return (0.01e27, 0.05e27, 0.05e27);
    }

    /// @inheritdoc IReserveInterestRateStrategy
    /// @dev Returns constant rates: 1% liquidity, 5% stable, 5% variable (all in RAY)
    function calculateInterestRates(address, address, uint256, uint256, uint256, uint256, uint256, uint256)
        external
        pure
        override
        returns (uint256, uint256, uint256)
    {
        return (0.01e27, 0.05e27, 0.05e27);
    }

    /// @notice Set the max variable borrow rate (test helper)
    /// @param rate New max rate in RAY (e.g., 0.2e27 for 20%)
    function setMaxVariableBorrowRate(uint256 rate) external {
        _maxVariableBorrowRate = rate;
    }

    /// @notice Set the base variable borrow rate (test helper)
    /// @param rate New base rate in RAY (e.g., 0.02e27 for 2%)
    function setBaseVariableBorrowRate(uint256 rate) external {
        _baseVariableBorrowRate = rate;
    }
}
