// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

import {ERC20, ERC4626, SimpleTokenizedStrategy} from "@btcVault/TokenizedStrategy/SimpleTokenizedStrategy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockYieldSource} from "./MockYieldSource.sol";

/// @title MockTokenizedStrategy
/// @notice Mock implementation of a tokenized strategy for testing purposes
/// @dev Uses MockYieldSource instead of real protocols like Aave for controlled testing environment.
///      Yield source withdrawal is done in `_beforeWithdraw` so it works for both ERC-4626 `withdraw()`
///      and `SimpleTokenizedStrategy.withdrawAll()` (which calls `_beforeWithdraw` directly).
/// @author Bitmor Protocol
contract MockTokenizedStrategy is SimpleTokenizedStrategy {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for address;

    /// @notice Initializes the mock strategy with a mock yield source
    /// @param _yieldSource The address of the MockYieldSource contract
    /// @param _vault The address of the vault that will manage this strategy
    constructor(address _yieldSource, address _vault) SimpleTokenizedStrategy(_yieldSource, _vault) {}

    /// @notice Returns the name of the mock strategy token
    /// @inheritdoc ERC20
    /// @return The mock strategy token name
    function name() public pure override(ERC20, IERC20Metadata) returns (string memory) {
        return "mockTokenizedStrategy";
    }

    /// @notice Returns the symbol of the mock strategy token
    /// @inheritdoc ERC20
    /// @return The mock strategy token symbol
    function symbol() public pure override(ERC20, IERC20Metadata) returns (string memory) {
        return "mockTS";
    }

    /// @notice Returns the total amount of assets deployed in the mock yield source
    /// @inheritdoc ERC4626
    /// @dev Queries mock balance instead of real protocol balance
    /// @return assets The total amount of underlying assets in the mock yield source
    function totalAssets() public view override returns (uint256 assets) {
        assets = _getBalanceInAave();
    }

    /// @notice Internal hook called after deposits to deploy assets to mock yield source
    /// @inheritdoc ERC4626
    /// @dev Approves and supplies assets to MockYieldSource for testing
    /// @param by The address initiating the deposit
    /// @param to The address receiving the shares
    /// @param assets The amount of assets being deposited
    /// @param shares The amount of shares being minted
    function _deposit(address by, address to, uint256 assets, uint256 shares) internal override {
        super._deposit(by, to, assets, shares);

        // Supply assets to mock yield source
        asset().safeApprove(i_yieldSource, assets);
        MockYieldSource(i_yieldSource).supply(asset(), assets);
    }

    /// @notice Hook called before withdrawals to retrieve assets from mock yield source
    /// @dev Withdraws assets from MockYieldSource back to strategy. Used by both
    ///      ERC-4626 `withdraw()` (via `_withdraw` → `_beforeWithdraw`) and
    ///      `SimpleTokenizedStrategy.withdrawAll()` (calls `_beforeWithdraw` directly).
    /// @param assets The amount of assets being withdrawn
    function _beforeWithdraw(uint256 assets, uint256) internal override {
        MockYieldSource(i_yieldSource).withdraw(asset(), assets);
    }

    /// @notice Gets the balance of assets deposited in the mock yield source
    /// @dev Queries the mock balance which simulates deposits in a real protocol
    /// @return balance The amount of assets deposited in the mock yield source
    function _getBalanceInAave() internal view returns (uint256 balance) {
        balance = MockYieldSource(i_yieldSource).balanceOf(asset(), address(this));
    }
}
