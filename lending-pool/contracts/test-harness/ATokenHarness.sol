// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {AToken} from "../protocol/tokenization/AToken.sol";

/// @dev Mock lending pool for AToken harness tests.
/// Provides configurable getReserveNormalizedIncome for balanceOf/totalSupply.
contract MockPoolForAToken {
    uint256 internal _normalizedIncome;

    function setNormalizedIncome(uint256 income) external {
        _normalizedIncome = income;
    }

    function getReserveNormalizedIncome(address) external view returns (uint256) {
        return _normalizedIncome;
    }
}

/// @dev Harness that inherits from the real AToken for fuzz testing.
/// Tests exercise mint, scaledBalanceOf, and balanceOf on the actual AToken code.
contract ATokenHarness is AToken {}
