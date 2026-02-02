// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {AaveTokenizedStrategy} from "@btcVault/TokenizedStrategy/AaveTokenizedStrategy.sol";
import {SimpleTokenizedStrategyHarness} from "../../harness/SimpleTokenizedStrategyHarness.sol";

import {MockAaveV3Pool} from "../../mock/MockAaveV3Pool.sol";
import {MockAToken} from "../../mock/MockAToken.sol";
import {MockERC20} from "../../mock/MockERC20.sol";
import {MockVault} from "../../mock/MockVault.sol";

/// @title BaseStrategyTest
/// @notice Shared setup and helpers for TokenizedStrategy unit tests
/// @dev Provides mock infrastructure for testing strategies in isolation
contract BaseStrategyTest is Test {
    // ============ Constants ============

    /// @notice Standard deposit amount (1 BTC, 8 decimals)
    uint256 constant STRATEGY_DEPOSIT_AMOUNT = 1e8;

    /// @notice Small deposit for edge cases (0.01 BTC)
    uint256 constant STRATEGY_SMALL_DEPOSIT = 0.01e8;

    /// @notice Large deposit for boundary testing (10 BTC)
    uint256 constant STRATEGY_LARGE_DEPOSIT = 10e8;

    /// @notice Simulated yield amount (0.05 BTC)
    uint256 constant STRATEGY_YIELD_AMOUNT = 0.05e8;

    /// @notice User starting balance (100 BTC)
    uint256 constant STRATEGY_USER_BALANCE = 100e8;

    // ============ Mocks ============

    /// @notice Mock Aave V3 pool for supply/withdraw
    MockAaveV3Pool mockAavePool;

    /// @notice Mock aToken for balance tracking
    MockAToken mockAToken;

    /// @notice Mock underlying asset (cbBTC, 8 decimals)
    MockERC20 mockAsset;

    /// @notice Mock vault that returns asset address
    MockVault mockVault;

    // ============ Contracts Under Test ============

    /// @notice AaveTokenizedStrategy instance
    AaveTokenizedStrategy aaveStrategy;

    /// @notice SimpleTokenizedStrategy harness instance
    SimpleTokenizedStrategyHarness strategyHarness;

    // ============ Test Actors ============

    /// @notice Test user address
    address user;

    // ============ Setup ============

    function setUp() public virtual {
        // Create test user
        user = makeAddr("strategyUser");

        // Deploy mock asset (cbBTC with 8 decimals)
        mockAsset = new MockERC20("Coinbase BTC", "cbBTC", 8);

        // Deploy mock Aave pool first
        mockAavePool = new MockAaveV3Pool();

        // Deploy mock aToken with correct pool reference (5 args: name, symbol, decimals, underlying, pool)
        mockAToken = new MockAToken("Aave cbBTC", "acbBTC", 8, address(mockAsset), address(mockAavePool));

        // Initialize reserve in pool
        mockAavePool.initReserve(address(mockAsset), address(mockAToken));

        // Deploy mock vault
        mockVault = new MockVault(address(mockAsset));

        // Deploy strategies
        aaveStrategy = new AaveTokenizedStrategy(address(mockAavePool), address(mockVault));
        strategyHarness = new SimpleTokenizedStrategyHarness(address(mockAavePool), address(mockVault));

        // Fund user
        _fundUser(user, STRATEGY_USER_BALANCE);

        // Fund Aave pool for withdrawals
        mockAsset.mint(address(mockAavePool), STRATEGY_USER_BALANCE);
    }

    // ============ Helpers ============

    /// @notice Fund user with mock asset
    /// @param _user Address to fund
    /// @param amount Amount to mint
    function _fundUser(address _user, uint256 amount) internal {
        mockAsset.mint(_user, amount);
    }

    /// @notice Deposit to Aave strategy as user
    /// @param amount Amount to deposit
    function _depositToStrategy(uint256 amount) internal {
        vm.startPrank(user);
        mockAsset.approve(address(aaveStrategy), amount);
        aaveStrategy.deposit(amount, user);
        vm.stopPrank();
    }

    /// @notice Withdraw from Aave strategy as user
    /// @param amount Amount to withdraw
    function _withdrawFromStrategy(uint256 amount) internal {
        vm.prank(user);
        aaveStrategy.withdraw(amount, user, user);
    }

    /// @notice Simulate yield by minting extra aTokens to strategy
    /// @dev Pranks as pool since MockAToken restricts minting to pool only
    /// @param yieldAmount Amount of yield to simulate
    function _simulateYield(uint256 yieldAmount) internal {
        vm.prank(address(mockAavePool));
        mockAToken.mint(address(aaveStrategy), yieldAmount);
    }

    /// @notice Get user's share balance in strategy
    /// @param _user Address to check
    /// @return Share balance
    function _getStrategyShares(address _user) internal view returns (uint256) {
        return aaveStrategy.balanceOf(_user);
    }

    /// @notice Get strategy's total assets
    /// @return Total assets under management
    function _getTotalAssets() internal view returns (uint256) {
        return aaveStrategy.totalAssets();
    }
}
