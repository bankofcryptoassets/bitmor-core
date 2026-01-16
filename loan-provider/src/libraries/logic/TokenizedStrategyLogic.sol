// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";

import {DataTypes} from "../types/DataTypes.sol";
import {BTCVault__Validation as Helpers} from "../helpers/BTCVault__Validation.sol";
import {Errors} from "../helpers/Errors.sol";

import {SimpleTokenizedStrategy} from "../../vaults/btc-vault/TokenizedStrategy/SimpleTokenizedStrategy.sol";

/**
 * @title TokenizedStrategyLogic
 * @notice Library for interacting with tokenized strategies and managing fund flows
 * @dev Handles deposits, withdrawals, and reallocations across multiple tokenized strategies
 * @author Bitmor Protocol
 */
library TokenizedStrategyLogic {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for address;
    using Helpers for DataTypes.StrategyState;

    /**
     * @notice Scale factor for basis points calculations (10,000 = 100%)
     */
    uint256 internal constant BASIS_POINT_SCALE = 1e4;

    /**
     * @notice Retrieves the underlying asset address from a tokenized strategy
     * @param strategy The address of the tokenized strategy
     * @return asset The address of the underlying asset
     */
    function getAsset(address strategy) internal view returns (address asset) {
        asset = SimpleTokenizedStrategy(strategy).asset();
    }

    /**
     * @notice Returns the amount of assets deployed in a specific tokenized strategy
     * @dev Converts strategy shares to underlying asset amount using ERC-4626 conversion
     * @param strategy The address of the tokenized strategy
     * @return assets The amount of underlying assets held by the strategy
     */
    function getAssetBalanceInStrategy(address strategy) internal view returns (uint256 assets) {
        // Get the number of strategy shares held by this vault
        uint256 strategySharesBalance = SimpleTokenizedStrategy(strategy).balanceOf(address(this));

        // Convert strategy shares to underlying asset amount
        assets = SimpleTokenizedStrategy(strategy).convertToAssets(strategySharesBalance);
    }

    /**
     * @notice Returns the maximum amount of assets that can be withdrawn from a strategy
     * @dev Queries the strategy's maxWithdraw function for current withdrawal limit
     * @param strategy The address of the tokenized strategy
     * @return maxWithdrawableAmount The maximum withdrawable amount in underlying assets
     */
    function getMaxWithdrawable(address strategy) internal view returns (uint256 maxWithdrawableAmount) {
        maxWithdrawableAmount = SimpleTokenizedStrategy(strategy).maxWithdraw(address(this));
    }

    /**
     * @notice Withdraws all available funds from a specific strategy
     * @dev Used when removing strategies or during emergency operations
     * @param strategy The address of the strategy to withdraw from
     * @param asset The address of the underlying asset for approval reset
     */
    function withdrawMaxFunds(address strategy, address asset) internal {
        uint256 maxWithdrawable = getMaxWithdrawable(strategy);

        withdraw(strategy, maxWithdrawable);

        // Reset asset approval for the strategy
        asset.safeApprove(strategy, 0);
    }

    /**
     * @notice Emergency withdrawal of all funds from all strategies
     * @dev Withdraws maximum available from each strategy in withdraw queue order
     * @param s The strategy state storage reference
     */
    function emergencyWithdraw(DataTypes.StrategyState storage s) internal {
        uint256 i = 0;
        uint256[] memory withdrawQueue = s.withdrawQueue;
        for (i; i < withdrawQueue.length; i++) {
            address strategyAddress = s.strategies[withdrawQueue[i]].strategy;
            uint256 maxWithdrawable = SimpleTokenizedStrategy(strategyAddress).maxWithdraw(address(this));

            // Skip strategies with no withdrawable balance
            if (maxWithdrawable == 0) continue;

            SimpleTokenizedStrategy(strategyAddress).withdraw(maxWithdrawable, address(this), address(this));
        }
    }

    /**
     * @notice Internal function to deposit assets into a tokenized strategy
     * @dev Calls the strategy's deposit function with vault as receiver
     * @param strategy The address of the strategy to deposit into
     * @param amountToSupply The amount of assets to deposit
     */
    function deposit(address strategy, uint256 amountToSupply) internal {
        SimpleTokenizedStrategy(strategy).deposit(amountToSupply, address(this));
    }

    /**
     * @notice Internal function to withdraw assets from a tokenized strategy
     * @dev Calls the strategy's withdraw function with vault as receiver and owner
     * @param strategy The address of the strategy to withdraw from
     * @param amount The amount of assets to withdraw
     * @return finalWithdrawn The actual amount of assets withdrawn
     */
    function withdraw(address strategy, uint256 amount) internal returns (uint256 finalWithdrawn) {
        finalWithdrawn = SimpleTokenizedStrategy(strategy).withdraw(amount, address(this), address(this));
    }
}
