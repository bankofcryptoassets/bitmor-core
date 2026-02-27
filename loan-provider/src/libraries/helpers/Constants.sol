// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title Constants
/// @author Bitmor Protocol
/// @notice Shared protocol constants used across multiple libraries
library Constants {
    /// @notice Maximum acceptable dust debt (in debt asset wei) remaining after repayment
    /// @dev Covers Aave V2 rayMul/rayDiv rounding (~1 wei) plus inter-block interest accrual (~1 wei).
    ///      Set to 10 for a comfortable margin. At USDC 6 decimals, 10 wei = $0.00001.
    uint256 internal constant DEBT_DUST_THRESHOLD = 10;
}
