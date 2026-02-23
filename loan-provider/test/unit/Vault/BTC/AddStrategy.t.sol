// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@solady/tokens/ERC20.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

import {BTCVault} from "@btcVault/BTCVault.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {MockTokenizedStrategy, BaseTestForBTCVault} from "../BaseTestForBTCVault.t.sol";

/**
 * @title AddStrategy Test Suite for BTCVault
 * @author Bitmor Protocol
 * @notice Tests for adding strategies to the vault
 * @dev Tests various scenarios including first strategy, multiple strategies, and error conditions
 */
contract AddStrategy__BTCVaultHarness is BaseTestForBTCVault {
    using FixedPointMathLib for uint256;

    /**
     * @notice Test adding first strategy to an empty vault
     * @dev Verifies strategy index and total strategies count are correctly set
     */
    function test_addStrategy_FirstStrategyWithEmptyVault() public {
        uint256 cap = STANDARD_STRATEGY_CAP;

        _addStrategy(cap);

        uint256 currentStrategyIndex = vault.getStrategyIndex(address(strategy));
        uint256 expectedStrategyIndex = 0;

        assertEq(currentStrategyIndex, expectedStrategyIndex);

        uint256 currentNextIndex = vault.getNextStrategyIndex();
        uint256 expectedNextIndex = 1;

        assertEq(currentNextIndex, expectedNextIndex);

        uint256[] memory currentSupplyQueue = vault.getSupplyQueue();
        uint256[] memory expectedQueue = new uint256[](1);
        expectedQueue[0] = 0;

        assertEq(currentSupplyQueue, expectedQueue);
    }

    /**
     * @notice Test adding first strategy after deposits have been made
     * @dev Verifies funds are correctly allocated to the strategy based on cap percentage
     */
    function test_addStrategy_FirstStrategy() public {
        uint256 cap = STANDARD_STRATEGY_CAP;

        uint256 feeAmount = DEPOSIT_AMOUNT.mulDivUp(vault.getEntryFee(), vault.getEntryFee() + BASIS_POINT_SCALE);
        uint256 finalDepositAmount = DEPOSIT_AMOUNT.rawSub(feeAmount);

        _addStrategy(cap);
        _deposit(DEPOSIT_AMOUNT);

        uint256 assetsInStrategy = vault.getAssetInStrategy(address(strategy));

        uint256 expectedAssetsInStrategy = finalDepositAmount;

        assertEq(assetsInStrategy, expectedAssetsInStrategy);
    }

    /**
     * @notice Test adding a second strategy to vault with existing strategy
     * @dev Verifies multiple strategies can coexist with proper caps and total assets tracking
     */
    function test_addStrategy_SecondStrategy() public {
        uint256 firstStrategyCap = SMALL_STRATEGY_CAP;
        uint256 secondStrategyCap = SMALL_STRATEGY_CAP;

        uint256 feeAmount = DEPOSIT_AMOUNT.mulDivUp(vault.getEntryFee(), vault.getEntryFee() + BASIS_POINT_SCALE);
        uint256 finalDepositAmount = DEPOSIT_AMOUNT.rawSub(feeAmount);

        _addStrategy(firstStrategyCap);

        MockTokenizedStrategy strategy2 = new MockTokenizedStrategy(address(yieldSource), address(vault));
        _scheduleAndExecute(
            bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strategy2), secondStrategyCap))
        );

        _deposit(DEPOSIT_AMOUNT);

        uint256 assetsInStrategy1 = vault.getAssetInStrategy(address(strategy));
        uint256 assetsInStrategy2 = vault.getAssetInStrategy(address(strategy2));

        uint256 expectedAssetsInStrategy1 = SMALL_STRATEGY_CAP;
        uint256 expectedAssetsInStrategy2 = finalDepositAmount - expectedAssetsInStrategy1;

        assertEq(assetsInStrategy1, expectedAssetsInStrategy1);
        assertEq(assetsInStrategy2, expectedAssetsInStrategy2);

        uint256 totalAssets = vault.totalAssets();
        uint256 expectedTotalAssets = finalDepositAmount;

        assertEq(totalAssets, expectedTotalAssets);
    }

    /**
     * @notice Test that adding strategy with zero address reverts
     * @dev Expects revert with ZeroAddress error
     */
    function test_addStrategy_StrategyWithZeroAddress() public {
        bytes memory data = abi.encodeCall(BTCVault.addStrategy, (address(0), 0));

        _scheduleAndExpectRevert(bvc, bvc_id(), data, abi.encodeWithSelector(Errors.ZeroAddress.selector));
    }

    /**
     * @notice Test that adding duplicate strategy reverts
     * @dev Expects revert with StrategyAlreadyAdded error when adding same strategy twice
     */
    function test_addStrategy_StrategyAlreadyAdded() public {
        uint256 cap = DEPOSIT_AMOUNT;

        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strategy), cap)));

        bytes memory data = abi.encodeCall(BTCVault.addStrategy, (address(strategy), SMALL_STRATEGY_CAP));
        _scheduleAndExpectRevert(bvc, bvc_id(), data, abi.encodeWithSelector(Errors.StrategyAlreadyAdded.selector));
    }

    /**
     * @notice Test that strategies can be added with large caps (no TotalCapExceeded validation in current implementation)
     * @dev The implementation allows large caps per strategy
     */
    function test_addStrategy_WithLargeCap() public {
        uint256 largeCap = VERY_LARGE_CAP;

        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strategy), largeCap)));

        assertEq(vault.getStrategyDetails(0).cap, largeCap);
    }

    /**
     * @notice Test that strategies can be added with zero caps (current implementation allows this)
     * @dev Zero caps are allowed in the current implementation
     */
    function test_addStrategy_StrategyWithZeroCap() public {
        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strategy), 0)));

        assertEq(vault.getStrategyDetails(0).cap, 0);
    }

    // ==========================================================================

    /**
     * @notice Internal helper function to perform deposit operations
     * @dev Handles approval and deposit in a single transaction
     * @param depositAmount Amount of USDC to deposit
     */
    function _deposit(uint256 depositAmount) internal {
        vm.startPrank(user);
        ERC20(networkConfig.usdc).approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();
    }

    /**
     * @notice Internal helper function to perform withdrawal operations
     * @dev Withdraws specified amount to user's address
     * @param withdrawAmount Amount of assets to withdraw
     */
    function _withdraw(uint256 withdrawAmount) internal {
        vm.prank(user);
        vault.withdraw(withdrawAmount, user, user);
    }

    /**
     * @notice Internal helper function to add strategy as curator
     * @dev Pranks as curator to add strategy with specified cap
     * @param cap Cap amount in USDC (e.g., 50_000e6 = 50,000 USDC)
     */
    function _addStrategy(uint256 cap) internal {
        _scheduleAndExecute(bvc, bvc_id(), abi.encodeCall(BTCVault.addStrategy, (address(strategy), cap)));
    }
}
