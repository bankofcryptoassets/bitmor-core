// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {StableDebtToken} from "../protocol/tokenization/StableDebtToken.sol";

/// @dev Mock lending pool for StableDebtToken harness tests.
/// Only needed as a contract address for the onlyLendingPool modifier.
contract MockPoolForStableDebt {
    // Empty - only serves as an address
}

/// @dev Harness that inherits from the real StableDebtToken for fuzz testing.
/// All needed functions (mint, balanceOf, totalSupply, getUserStableRate,
/// getAverageStableRate) are already public/external in StableDebtToken.
contract StableDebtTokenHarness is StableDebtToken {}
