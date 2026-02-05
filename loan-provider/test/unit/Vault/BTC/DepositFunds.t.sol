// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTestForBTCVault} from "../BaseTestForBTCVault.t.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {MockTokenizedStrategy} from "../../../mock/MockTokenizedStrategy.sol";
import {MockYieldSource} from "../../../mock/MockYieldSource.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";

/// @title DepositFundsTest
/// @notice Tests for BTCVault _depositFunds internal logic via deposit()
/// @dev Hunts for fund distribution bugs, cap enforcement issues, queue ordering problems
contract DepositFundsTest is BaseTestForBTCVault {
    // ============ Additional Strategies ============
    MockTokenizedStrategy strategy2;
    MockTokenizedStrategy strategy3;
    MockYieldSource yieldSource2;
    MockYieldSource yieldSource3;

    // ============ Constants ============
    uint256 constant SMALL_CAP = 1000e6;
    uint256 constant MEDIUM_CAP = 5000e6;
    uint256 constant LARGE_CAP = 10000e6;

    // ============ Setup ============

    function setUp() public override {
        super.setUp();

        // Create additional strategies
        yieldSource2 = new MockYieldSource();
        yieldSource3 = new MockYieldSource();
        strategy2 = new MockTokenizedStrategy(address(yieldSource2), address(vault));
        strategy3 = new MockTokenizedStrategy(address(yieldSource3), address(vault));
    }

    /// @notice Helper to add strategy via proper access control
    function _addStrategy(address strat, uint256 cap) internal {
        _scheduleAndExecuteLocal(bvc, BVC_ID(), abi.encodeCall(BTCVault.addStrategy, (strat, cap)));
    }

    /// @notice Helper to deposit as user with proper approval
    function _depositAsUser(uint256 amount) internal returns (uint256 shares) {
        vm.startPrank(user);
        mockUSDC.approve(address(vault), amount);
        shares = vault.deposit(amount, user);
        vm.stopPrank();
    }

    // ============ Single Strategy Tests ============

    /// @notice Deposit with single strategy should allocate all to that strategy
    function test_depositFunds_SingleStrategy_FullAllocation() public {
        _addStrategy(address(strategy), LARGE_CAP);

        uint256 depositAmount = 5000e6;
        uint256 entryFee = vault.getEntryFee();
        uint256 feeAmount = vault.feeOnTotal(depositAmount, entryFee);
        uint256 expectedToStrategy = depositAmount - feeAmount;

        _depositAsUser(depositAmount);

        uint256 assetsInStrategy = vault.getAssetInStrategy(address(strategy));
        assertEq(assetsInStrategy, expectedToStrategy, "all assets should go to strategy");
        assertEq(vault.totalAssets(), expectedToStrategy, "totalAssets should match strategy balance");
    }

    /// @notice Deposit exceeding single strategy cap should revert
    function test_depositFunds_SingleStrategy_revertWhen_ExceedsCap() public {
        _addStrategy(address(strategy), SMALL_CAP);

        uint256 depositAmount = SMALL_CAP + 1000e6; // Exceeds cap

        vm.startPrank(user);
        mockUSDC.approve(address(vault), depositAmount);
        // ERC4626 checks maxDeposit first, so we get DepositMoreThanMax error
        vm.expectRevert(abi.encodeWithSignature("DepositMoreThanMax()"));
        vault.deposit(depositAmount, user);
        vm.stopPrank();
    }

    // ============ Multiple Strategy Tests ============

    /// @notice Deposit should follow supply queue order
    function test_depositFunds_MultipleStrategies_FollowsSupplyQueue() public {
        // Add strategies with different caps
        _addStrategy(address(strategy), SMALL_CAP); // Index 0
        _addStrategy(address(strategy2), MEDIUM_CAP); // Index 1
        _addStrategy(address(strategy3), LARGE_CAP); // Index 2

        // Deposit amount that exceeds first strategy cap
        uint256 depositAmount = SMALL_CAP + 2000e6;
        uint256 entryFee = vault.getEntryFee();
        uint256 feeAmount = vault.feeOnTotal(depositAmount, entryFee);
        uint256 netDeposit = depositAmount - feeAmount;

        _depositAsUser(depositAmount);

        // First strategy should be at cap
        uint256 inStrategy1 = vault.getAssetInStrategy(address(strategy));
        assertEq(inStrategy1, SMALL_CAP, "first strategy should be at cap");

        // Remainder should go to second strategy
        uint256 inStrategy2 = vault.getAssetInStrategy(address(strategy2));
        uint256 expectedInStrategy2 = netDeposit - SMALL_CAP;
        assertEq(inStrategy2, expectedInStrategy2, "overflow should go to second strategy");

        // Third strategy should be empty
        uint256 inStrategy3 = vault.getAssetInStrategy(address(strategy3));
        assertEq(inStrategy3, 0, "third strategy should be empty");
    }

    /// @notice Should skip strategies that are already at cap
    function test_depositFunds_MultipleStrategies_SkipsFullStrategy() public {
        _addStrategy(address(strategy), SMALL_CAP);
        _addStrategy(address(strategy2), MEDIUM_CAP);

        // Fill first strategy
        _depositAsUser(SMALL_CAP + 100e6); // Slightly over to fill first, overflow to second

        uint256 inStrategy1AfterFirst = vault.getAssetInStrategy(address(strategy));
        assertEq(inStrategy1AfterFirst, SMALL_CAP, "first strategy should be at cap after first deposit");

        // Second deposit should skip first strategy
        uint256 secondDeposit = 1000e6;
        uint256 entryFee = vault.getEntryFee();
        uint256 secondFeeAmount = vault.feeOnTotal(secondDeposit, entryFee);
        uint256 expectedIncrease = secondDeposit - secondFeeAmount;

        uint256 inStrategy2Before = vault.getAssetInStrategy(address(strategy2));

        _depositAsUser(secondDeposit);

        uint256 inStrategy1 = vault.getAssetInStrategy(address(strategy));
        assertEq(inStrategy1, SMALL_CAP, "first strategy should remain at cap");

        // All of second deposit should go to strategy2
        uint256 inStrategy2 = vault.getAssetInStrategy(address(strategy2));
        assertEq(inStrategy2, inStrategy2Before + expectedIncrease, "second strategy should have received funds");
    }

    /// @notice All strategies at cap should revert
    function test_depositFunds_AllStrategiesFull_revertWhen_AllCapsReached() public {
        _addStrategy(address(strategy), SMALL_CAP);
        _addStrategy(address(strategy2), SMALL_CAP);

        // Fill both strategies by depositing exactly maxDeposit
        // Note: maxDeposit returns the sum of remaining caps (2000e6)
        // Entry fee is deducted from deposit, so actual allocation to strategies
        // will be less than 2000e6. The strategies won't be completely filled,
        // but maxDeposit will become 0.
        uint256 maxDep = vault.maxDeposit(user);
        assertEq(maxDep, SMALL_CAP * 2, "maxDeposit should equal sum of caps");

        _depositAsUser(maxDep);

        // After depositing maxDeposit, strategies receive maxDep - fees
        // First strategy should be at cap, second gets remainder
        uint256 inStrategy1 = vault.getAssetInStrategy(address(strategy));
        uint256 inStrategy2 = vault.getAssetInStrategy(address(strategy2));
        assertEq(inStrategy1, SMALL_CAP, "first strategy should be at cap");

        // Second strategy gets remainder (maxDep - fee - SMALL_CAP)
        uint256 entryFee = vault.getEntryFee();
        uint256 feeAmount = vault.feeOnTotal(maxDep, entryFee);
        uint256 netDeposit = maxDep - feeAmount;
        assertEq(inStrategy2, netDeposit - SMALL_CAP, "second strategy should get remainder");

        // Third deposit should fail - maxDeposit should now reflect remaining cap
        uint256 remainingCap = SMALL_CAP - inStrategy2; // strategy2's remaining cap

        vm.startPrank(user);
        mockUSDC.approve(address(vault), remainingCap + 1000e6);
        // ERC4626 checks maxDeposit first, so we get DepositMoreThanMax error
        vm.expectRevert(abi.encodeWithSignature("DepositMoreThanMax()"));
        vault.deposit(remainingCap + 1000e6, user);
        vm.stopPrank();
    }

    // ============ Edge Cases ============

    /// @notice Zero cap strategy should be skipped
    function test_depositFunds_SkipsZeroCapStrategy() public {
        _addStrategy(address(strategy), 0); // Zero cap
        _addStrategy(address(strategy2), LARGE_CAP);

        uint256 depositAmount = 5000e6;
        _depositAsUser(depositAmount);

        uint256 inStrategy1 = vault.getAssetInStrategy(address(strategy));
        assertEq(inStrategy1, 0, "zero cap strategy should be skipped");

        uint256 inStrategy2 = vault.getAssetInStrategy(address(strategy2));
        assertGt(inStrategy2, 0, "deposit should go to second strategy");
    }

    /// @notice totalAssets should match sum of all strategies
    function test_totalAssets_MatchesSumOfStrategies() public {
        _addStrategy(address(strategy), MEDIUM_CAP);
        _addStrategy(address(strategy2), MEDIUM_CAP);

        _depositAsUser(8000e6);

        uint256 inStrategy1 = vault.getAssetInStrategy(address(strategy));
        uint256 inStrategy2 = vault.getAssetInStrategy(address(strategy2));
        uint256 total = vault.totalAssets();

        assertEq(total, inStrategy1 + inStrategy2, "totalAssets should equal sum of strategies");
    }

    /// @notice getAssetInStrategy for non-existent strategy reverts with StrategyNotFound
    /// @dev StrategyStateLogic.getStrategyIndex reverts with StrategyNotFound when strategy not in mapping
    function test_getAssetInStrategy_NonExistentStrategy_RevertsWithStrategyNotFound() public {
        _addStrategy(address(strategy), LARGE_CAP);

        address fakeStrategy = makeAddr("fakeStrategy");

        // Non-existent strategy lookup should revert with specific error
        vm.expectRevert(Errors.StrategyNotFound.selector);
        vault.getAssetInStrategy(fakeStrategy);
    }
}
