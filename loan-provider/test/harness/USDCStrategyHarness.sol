// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {USDCStrategy} from "@bitmor/vaults/usdc-vault/USDCStrategy.sol";

/// @title USDCStrategyHarness
/// @notice Exposes internal functions for unit testing
/// @dev Following Trail of Bits harness pattern for internal function testing
contract USDCStrategyHarness is USDCStrategy {
    constructor(address _vault, address _aave, address _blp) USDCStrategy(_vault, _aave, _blp) {}

    /// @notice Exposes _withdrawFunds for testing withdrawal edge cases
    function exposed_withdrawFunds(uint256 amount) external {
        _withdrawFunds(amount);
    }

    /// @notice Exposes _reallocateAssets for testing reallocation logic
    function exposed_reallocateAssets() external {
        _reallocateAssets();
    }

    /// @notice Exposes _withdrawFundsToBLP for testing BLP priority withdrawals
    function exposed_withdrawFundsToBLP(uint256 amount) external {
        _withdrawFundsToBLP(amount);
    }

    /// @notice Exposes _withdrawAllFunds for testing full withdrawal
    function exposed_withdrawAllFunds() external {
        _withdrawAllFunds();
    }

    /// @notice Exposes _getBalanceInAave for balance inspection
    function exposed_getBalanceInAave() external view returns (uint256) {
        return _getBalanceInAave();
    }

    /// @notice Exposes _getBalanceInBLP for balance inspection
    function exposed_getBalanceInBLP() external view returns (uint256) {
        return _getBalanceInBLP();
    }

    /// @notice Exposes _getTotalBalanceInMarkets for total balance inspection
    function exposed_getTotalBalanceInMarkets() external view returns (uint256) {
        return _getTotalBalanceInMarkets();
    }

    /// @notice Exposes _withdrawFomAaveAndDepositInBLP for reallocation testing
    function exposed_withdrawFromAaveAndDepositInBLP(uint256 amount) external {
        _withdrawFomAaveAndDepositInBLP(amount);
    }

    /// @notice Exposes _withdrawFomBLPAndDepositInAAVE for reallocation testing
    function exposed_withdrawFromBLPAndDepositInAave(uint256 amount) external {
        _withdrawFomBLPAndDepositInAAVE(amount);
    }
}
