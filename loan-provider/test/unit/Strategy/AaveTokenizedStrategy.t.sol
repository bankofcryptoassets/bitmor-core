// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseStrategyTest} from "./BaseStrategyTest.t.sol";

/// @title AaveTokenizedStrategyTest
/// @author Bitmor Protocol
/// @notice Unit tests for AaveTokenizedStrategy contract
/// @dev Tests deposit/withdraw flows, yield accrual, and ERC-4626 compliance with `MockAaveV3Pool`
contract AaveTokenizedStrategyTest is BaseStrategyTest {
    // ============ Constructor Tests ============

    /// @notice Test that constructor sets yield source (Aave pool)
    function test_Constructor_SetsYieldSource() public view {
        address yieldSource = aaveStrategy.i_yieldSource();
        assertEq(yieldSource, address(mockAavePool), "yieldSource should be Aave pool");
    }

    /// @notice Test that constructor sets vault
    function test_Constructor_SetsVault() public view {
        address vault = aaveStrategy.i_vault();
        assertEq(vault, address(mockVault), "vault should match constructor arg");
    }

    /// @notice Test that constructor queries and sets asset from vault
    function test_Constructor_SetsAsset() public view {
        address asset = aaveStrategy.asset();
        assertEq(asset, address(mockAsset), "asset should be queried from vault");
    }

    // ============ View Function Tests ============

    /// @notice Test that name() returns correct value
    function test_Name_ReturnsAaveTokenizedStrategy() public view {
        string memory name = aaveStrategy.name();
        assertEq(name, "aaveTokenizedStrategy", "name should be aaveTokenizedStrategy");
    }

    /// @notice Test that symbol() returns correct value
    function test_Symbol_ReturnsAaveTS() public view {
        string memory symbol = aaveStrategy.symbol();
        assertEq(symbol, "aaveTS", "symbol should be aaveTS");
    }

    // ============ TotalAssets Tests ============

    /// @notice Test totalAssets returns zero when no deposits
    function test_TotalAssets_ReturnsZeroWhenEmpty() public view {
        uint256 totalAssets = aaveStrategy.totalAssets();
        assertEq(totalAssets, 0, "totalAssets should be 0 with no deposits");
    }

    /// @notice Test totalAssets returns aToken balance after deposit
    function test_TotalAssets_ReturnsATokenBalance() public {
        // Arrange
        uint256 depositAmount = STRATEGY_DEPOSIT_AMOUNT;

        // Act
        _depositToStrategy(depositAmount);

        // Assert
        uint256 totalAssets = aaveStrategy.totalAssets();
        uint256 aTokenBalance = mockAToken.balanceOf(address(aaveStrategy));
        assertEq(totalAssets, aTokenBalance, "totalAssets should equal aToken balance");
        assertEq(totalAssets, depositAmount, "totalAssets should equal deposit amount");
    }

    /// @notice Test totalAssets includes simulated yield
    function test_TotalAssets_IncludesYield() public {
        // Arrange
        uint256 depositAmount = STRATEGY_DEPOSIT_AMOUNT;
        _depositToStrategy(depositAmount);

        uint256 yieldAmount = STRATEGY_YIELD_AMOUNT;

        // Act - simulate yield accrual
        _simulateYield(yieldAmount);

        // Assert
        uint256 totalAssets = aaveStrategy.totalAssets();
        uint256 expectedTotal = depositAmount + yieldAmount;
        assertEq(totalAssets, expectedTotal, "totalAssets should include yield");
    }

    // ============ Deposit Tests ============

    /// @notice Test deposit transfers assets from user to strategy
    function test_Deposit_TransfersFromUser() public {
        // Arrange
        uint256 depositAmount = STRATEGY_DEPOSIT_AMOUNT;
        uint256 userBalanceBefore = mockAsset.balanceOf(user);

        // Act
        _depositToStrategy(depositAmount);

        // Assert
        uint256 userBalanceAfter = mockAsset.balanceOf(user);
        assertEq(userBalanceAfter, userBalanceBefore - depositAmount, "user balance should decrease by deposit");
    }

    /// @notice Test deposit supplies assets to Aave pool
    function test_Deposit_SuppliesToAave() public {
        // Arrange
        uint256 depositAmount = STRATEGY_DEPOSIT_AMOUNT;

        // Act
        _depositToStrategy(depositAmount);

        // Assert
        uint256 aTokenBalance = mockAToken.balanceOf(address(aaveStrategy));
        assertEq(aTokenBalance, depositAmount, "aToken balance should match deposit");
    }

    /// @notice Test deposit mints shares to user
    function test_Deposit_MintsShares() public {
        // Arrange
        uint256 depositAmount = STRATEGY_DEPOSIT_AMOUNT;

        // Act
        _depositToStrategy(depositAmount);

        // Assert
        uint256 shares = _getStrategyShares(user);
        assertGt(shares, 0, "user should receive shares");
        // First deposit: shares == assets (1:1 ratio)
        assertEq(shares, depositAmount, "first deposit should mint 1:1 shares");
    }

    /// @notice Test deposit updates totalAssets
    function test_Deposit_UpdatesTotalAssets() public {
        // Arrange
        uint256 depositAmount = STRATEGY_DEPOSIT_AMOUNT;
        uint256 totalAssetsBefore = aaveStrategy.totalAssets();

        // Act
        _depositToStrategy(depositAmount);

        // Assert
        uint256 totalAssetsAfter = aaveStrategy.totalAssets();
        assertEq(totalAssetsAfter, totalAssetsBefore + depositAmount, "totalAssets should increase by deposit");
    }

    /// @notice Test multiple deposits accumulate correctly
    function test_Deposit_MultipleDepositsAccumulate() public {
        // Arrange
        uint256 firstDeposit = STRATEGY_DEPOSIT_AMOUNT;
        uint256 secondDeposit = STRATEGY_SMALL_DEPOSIT;

        // Act
        _depositToStrategy(firstDeposit);
        _depositToStrategy(secondDeposit);

        // Assert
        uint256 totalAssets = aaveStrategy.totalAssets();
        assertEq(totalAssets, firstDeposit + secondDeposit, "totalAssets should be sum of deposits");
    }

    // ============ Withdraw Tests ============

    /// @notice Test withdraw pulls assets from Aave
    function test_Withdraw_WithdrawsFromAave() public {
        // Arrange
        uint256 depositAmount = STRATEGY_DEPOSIT_AMOUNT;
        _depositToStrategy(depositAmount);

        uint256 withdrawAmount = depositAmount / 2;
        uint256 aTokenBalanceBefore = mockAToken.balanceOf(address(aaveStrategy));

        // Act
        _withdrawFromStrategy(withdrawAmount);

        // Assert
        uint256 aTokenBalanceAfter = mockAToken.balanceOf(address(aaveStrategy));
        assertEq(aTokenBalanceAfter, aTokenBalanceBefore - withdrawAmount, "aToken balance should decrease");
    }

    /// @notice Test withdraw transfers assets to receiver
    function test_Withdraw_TransfersToReceiver() public {
        // Arrange
        uint256 depositAmount = STRATEGY_DEPOSIT_AMOUNT;
        _depositToStrategy(depositAmount);

        uint256 withdrawAmount = depositAmount / 2;
        uint256 userBalanceBefore = mockAsset.balanceOf(user);

        // Act
        _withdrawFromStrategy(withdrawAmount);

        // Assert
        uint256 userBalanceAfter = mockAsset.balanceOf(user);
        assertEq(userBalanceAfter, userBalanceBefore + withdrawAmount, "user should receive withdrawn assets");
    }

    /// @notice Test withdraw burns user shares
    function test_Withdraw_BurnsShares() public {
        // Arrange
        uint256 depositAmount = STRATEGY_DEPOSIT_AMOUNT;
        _depositToStrategy(depositAmount);

        uint256 sharesBefore = _getStrategyShares(user);
        uint256 withdrawAmount = depositAmount / 2;

        // Act
        _withdrawFromStrategy(withdrawAmount);

        // Assert
        uint256 sharesAfter = _getStrategyShares(user);
        assertLt(sharesAfter, sharesBefore, "shares should decrease after withdraw");
    }

    /// @notice Test withdraw updates totalAssets
    function test_Withdraw_UpdatesTotalAssets() public {
        // Arrange
        uint256 depositAmount = STRATEGY_DEPOSIT_AMOUNT;
        _depositToStrategy(depositAmount);

        uint256 withdrawAmount = depositAmount / 2;
        uint256 totalAssetsBefore = aaveStrategy.totalAssets();

        // Act
        _withdrawFromStrategy(withdrawAmount);

        // Assert
        uint256 totalAssetsAfter = aaveStrategy.totalAssets();
        assertEq(totalAssetsAfter, totalAssetsBefore - withdrawAmount, "totalAssets should decrease");
    }

    /// @notice Test withdraw full balance
    function test_Withdraw_FullBalance() public {
        // Arrange
        uint256 depositAmount = STRATEGY_DEPOSIT_AMOUNT;
        _depositToStrategy(depositAmount);

        // Act - withdraw everything
        _withdrawFromStrategy(depositAmount);

        // Assert
        uint256 totalAssets = aaveStrategy.totalAssets();
        uint256 shares = _getStrategyShares(user);
        assertEq(totalAssets, 0, "totalAssets should be 0 after full withdraw");
        assertEq(shares, 0, "user should have 0 shares after full withdraw");
    }

    // ============ Revert Tests ============

    /// @notice Test withdraw reverts when exceeding balance
    function test_RevertWhen_WithdrawExceedsBalance() public {
        // Arrange
        uint256 depositAmount = STRATEGY_DEPOSIT_AMOUNT;
        _depositToStrategy(depositAmount);

        uint256 excessAmount = depositAmount + 1;

        // Assert + Act
        vm.expectRevert();
        vm.prank(user);
        aaveStrategy.withdraw(excessAmount, user, user);
    }

    /// @notice Test deposit with zero amount behavior
    function test_Deposit_ZeroAmount() public {
        // Arrange
        uint256 sharesBefore = _getStrategyShares(user);

        // Act
        vm.startPrank(user);
        mockAsset.approve(address(aaveStrategy), 0);
        aaveStrategy.deposit(0, user);
        vm.stopPrank();

        // Assert - zero deposit should mint zero shares
        uint256 sharesAfter = _getStrategyShares(user);
        assertEq(sharesAfter, sharesBefore, "zero deposit should not mint shares");
    }
}
