// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {VariableDebtToken} from "../protocol/tokenization/VariableDebtToken.sol";

/// @dev Mock lending pool for VariableDebtToken harness tests.
/// Provides configurable getReserveNormalizedVariableDebt for balanceOf/totalSupply.
contract MockPoolForVariableDebt {
    uint256 internal _normalizedVariableDebt;

    function setNormalizedVariableDebt(uint256 debt) external {
        _normalizedVariableDebt = debt;
    }

    function getReserveNormalizedVariableDebt(address) external view returns (uint256) {
        return _normalizedVariableDebt;
    }
}

/// @dev Harness that inherits from the real VariableDebtToken for fuzz testing.
/// All needed functions (mint, balanceOf, scaledBalanceOf, totalSupply) are
/// already public/external in VariableDebtToken.
contract VariableDebtTokenHarness is VariableDebtToken {}
