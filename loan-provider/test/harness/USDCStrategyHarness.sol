// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {USDCStrategy} from "@bitmor/vaults/usdc-vault/USDCStrategy.sol";

/// @title USDCStrategyHarness
/// @author Bitmor Protocol
/// @notice Test harness exposing internal functions of `USDCStrategy` for unit testing
/// @dev Following Trail of Bits harness pattern. Exposes withdrawal, reallocation, and balance
///      inspection internals that are otherwise inaccessible.
/// @custom:security FOR TESTING ONLY - Never deploy to production.
contract USDCStrategyHarness is USDCStrategy {
    /// @notice Initializes the harness with required USDCStrategy dependencies
    /// @param _vault The USDC vault address this strategy serves
    /// @param _aave The Aave V3 pool address for yield generation
    /// @param _blp The Bitmor lending pool address for USDC lending
    constructor(address _vault, address _aave, address _blp) USDCStrategy(_vault, _aave, _blp) {}

    /// @notice Exposes internal `_withdrawFunds` for testing withdrawal edge cases
    /// @param amount Amount of USDC to withdraw from yield sources
    function exposed_withdrawFunds(uint256 amount) external {
        _withdrawFunds(amount);
    }

    /// @notice Exposes internal `_reallocateAssets` for testing reallocation logic
    function exposed_reallocateAssets() external {
        _reallocateAssets();
    }

    /// @notice Exposes internal `_withdrawFundsToBLP` for testing BLP priority withdrawals
    /// @param amount Amount of USDC to withdraw and deposit into BLP
    function exposed_withdrawFundsToBLP(uint256 amount) external {
        _withdrawFundsToBLP(amount);
    }

    /// @notice Exposes internal `_withdrawAllFunds` for testing full withdrawal
    function exposed_withdrawAllFunds() external {
        _withdrawAllFunds();
    }

    /// @notice Exposes internal `_getBalanceInAave` for balance inspection
    /// @return The USDC balance currently deposited in Aave
    function exposed_getBalanceInAave() external view returns (uint256) {
        return _getBalanceInAave();
    }

    /// @notice Exposes internal `_getBalanceInBLP` for balance inspection
    /// @return The USDC balance currently deposited in the Bitmor lending pool
    function exposed_getBalanceInBLP() external view returns (uint256) {
        return _getBalanceInBLP();
    }

    /// @notice Exposes internal `_getTotalBalanceInMarkets` for total balance inspection
    /// @return The combined USDC balance across Aave and BLP
    function exposed_getTotalBalanceInMarkets() external view returns (uint256) {
        return _getTotalBalanceInMarkets();
    }

    /// @notice Exposes internal `_withdrawFomAaveAndDepositInBLP` for reallocation testing
    /// @param amount Amount of USDC to move from Aave to BLP
    function exposed_withdrawFromAaveAndDepositInBLP(uint256 amount) external {
        _withdrawFomAaveAndDepositInBLP(amount);
    }

    /// @notice Exposes internal `_withdrawFomBLPAndDepositInAAVE` for reallocation testing
    /// @param amount Amount of USDC to move from BLP to Aave
    function exposed_withdrawFromBLPAndDepositInAave(uint256 amount) external {
        _withdrawFomBLPAndDepositInAAVE(amount);
    }
}
