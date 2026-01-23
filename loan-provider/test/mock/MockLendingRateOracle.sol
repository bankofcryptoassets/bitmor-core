// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title MockLendingRateOracle
/// @notice Mock oracle for market borrow rates used by interest rate strategies
contract MockLendingRateOracle {
    mapping(address => uint256) private _marketBorrowRates;

    /// @notice Returns the market borrow rate for an asset
    /// @param asset The asset address
    /// @return The market borrow rate in RAY (1e27)
    function getMarketBorrowRate(address asset) external view returns (uint256) {
        uint256 rate = _marketBorrowRates[asset];
        return rate > 0 ? rate : 0.03e27; // Default 3%
    }

    /// @notice Sets the market borrow rate for an asset (test helper)
    /// @param asset The asset address
    /// @param rate The rate in RAY
    function setMarketBorrowRate(address asset, uint256 rate) external {
        _marketBorrowRates[asset] = rate;
    }
}
