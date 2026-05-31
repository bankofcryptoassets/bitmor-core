// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BTCVaultFuzzTestBase} from "../base/BTCVaultFuzzTestBase.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {AaveTokenizedStrategy} from "@btcVault/TokenizedStrategy/AaveTokenizedStrategy.sol";
import {MockAToken} from "../../mock/MockAToken.sol";

/**
 * @title BTCVaultStrategyFuzzTest
 * @author Bitmor Protocol
 * @notice Fuzz tests for BTCVault strategy management: caps, queues, and reallocation
 * @dev Tests real BTCVault and AaveTokenizedStrategy contracts with two strategies.
 *      Validates cap enforcement, withdrawal ordering, reallocation invariants,
 *      strategy addition/removal, and queue validation.
 *
 *      Property catalogue:
 *        BTC-STRAT-01  Deposit respects strategy cap
 *        BTC-STRAT-02  Deposit spans multiple strategies when first is full
 *        BTC-STRAT-02b Custom supply queue order changes fill priority
 *        BTC-STRAT-03  Deposit reverts when all caps reached
 *        BTC-STRAT-04  Withdraw drains strategies in queue order
 *        BTC-STRAT-05  Withdraw spills to next strategy in queue
 *        BTC-STRAT-06  Withdraw reverts when insufficient liquidity
 *        BTC-STRAT-07  Reallocation moves assets between strategies (+ preserves totalAssets)
 *        BTC-STRAT-08  Reallocation with type(uint256).max allocates remaining
 *        BTC-STRAT-09  Reallocation reverts when exceeding strategy cap
 *        BTC-STRAT-10  Reallocation reverts when supplied != withdrawn
 *        BTC-STRAT-12  New strategy receives deposits after being added
 *        BTC-STRAT-13  Cannot remove strategy with non-zero balance
 *        BTC-STRAT-14  Strategy removal succeeds after draining
 *        BTC-STRAT-15  Strategy with zero cap is skipped on deposit
 *        BTC-STRAT-16  Supply queue rejects strategy with zero cap (non-fuzz)
 *        BTC-STRAT-17  Withdraw queue rejects duplicate entries (non-fuzz)
 *        BTC-STRAT-18  maxDeposit reflects remaining caps
 *        BTC-STRAT-SEC-01  maxDeposit fee gap — strategies not fully filled
 *        BTC-STRAT-SEC-02  Vault handles strategy liquidity shortage
 */
contract BTCVaultStrategyFuzzTest is BTCVaultFuzzTestBase {
    // ============ Constants ============

    /// @dev Maximum cap for fuzz-bounded caps (10,000 BTC)
    uint256 internal constant MAX_CAP = 10_000e8;

    /// @dev Basis point scale for fee calculations
    uint256 internal constant BPS_SCALE = 1e4;

    // ============ Setup ============

    function setUp() public override {
        super.setUp();
        _deploySecondStrategy();
        _addStrategy(address(strategy2), FC.SMALL_STRATEGY_CAP);

        // Update queues to include both strategies
        uint256[] memory queue = new uint256[](2);
        queue[0] = 0;
        queue[1] = 1;
        _updateSupplyQueue(queue);
        _updateWithdrawQueue(queue);
    }

    // ============ Helpers ============

    /// @notice Computes net assets deposited to strategies after entry fee deduction
    /// @dev WARNING: This is an independent reimplementation of vault fee math.
    ///      Use ONLY for test setup (bounds, vm.assume conditions), NEVER as an
    ///      assertion oracle. Using this in assertions creates circular logic.
    /// @param grossAssets The gross deposit amount before fees
    /// @return The net amount that reaches strategies
    function _netAfterEntryFee(uint256 grossAssets) internal view returns (uint256) {
        uint256 fee = vault.getEntryFee();
        if (fee == 0) return grossAssets;
        // _feeOnTotal: fee = assets * feeBps / (feeBps + BPS_SCALE)
        uint256 feeAmount = (grossAssets * fee + (fee + BPS_SCALE) - 1) / (fee + BPS_SCALE);
        return grossAssets - feeAmount;
    }

    /// @notice Safely change strategy cap, skipping if new cap equals current cap
    /// @param strategy The strategy address
    /// @param newCap The desired new cap
    function _safeChangeStrategyCap(address strategy, uint256 newCap) internal {
        uint256 index = vault.getStrategyIndex(strategy);
        DataTypes.Strategy memory s = vault.getStrategyDetails(index);
        if (s.cap == newCap) return; // skip to avoid NoChangeInCap revert
        _changeStrategyCap(strategy, newCap);
    }

    /// @notice Deposits up to maxDeposit, capping the gross amount
    /// @param user The depositor address
    /// @param grossDesired The desired gross deposit
    /// @return shares The shares minted
    function _safeDeposit(address user, uint256 grossDesired) internal returns (uint256 shares) {
        uint256 maxDep = vault.maxDeposit(user);
        uint256 gross = grossDesired > maxDep ? maxDep : grossDesired;
        vm.assume(gross > 0);
        return _depositToVault(user, gross);
    }

    // ================================================================
    //                    CAP ENFORCEMENT TESTS (3)
    // ================================================================

    /// @custom:audit-property BTC-STRAT-01 Deposit respects strategy cap
    function testFuzz_Deposit_RespectsStrategyCap(uint256 assetsSeed, uint256 capSeed) public {
        // Arrange
        uint256 cap = bound(capSeed, FC.MIN_BTC_AMOUNT, MAX_CAP);
        _safeChangeStrategyCap(address(strategy1), cap);

        // Ensure strategy2 has large cap to absorb overflow
        _safeChangeStrategyCap(address(strategy2), MAX_CAP);

        uint256 maxDep = vault.maxDeposit(depositor);
        uint256 assets = bound(assetsSeed, FC.MIN_BTC_AMOUNT, maxDep);
        vm.assume(assets > 0);

        // Act
        _depositToVault(depositor, assets);

        // Assert - strategy1 balance must not exceed its cap
        uint256 strategy1Balance = vault.getAssetInStrategy(address(strategy1));
        assertLe(strategy1Balance, cap, "strategy1 balance exceeds its cap after deposit");
    }

    /// @custom:audit-property BTC-STRAT-02 Deposit spans multiple strategies when first is full
    function testFuzz_Deposit_SpansMultipleStrategies(uint256 assetsSeed, uint256 cap1Seed, uint256 cap2Seed) public {
        // Arrange
        uint256 cap1 = bound(cap1Seed, FC.MIN_BTC_AMOUNT, 10e8);
        uint256 cap2 = bound(cap2Seed, FC.MIN_BTC_AMOUNT, 10e8);
        _safeChangeStrategyCap(address(strategy1), cap1);
        _safeChangeStrategyCap(address(strategy2), cap2);

        // We need net deposit to exceed cap1 but fit within cap1 + cap2
        // maxDeposit = cap1 + cap2 (gross), net = gross - fee
        // We need netDeposit > cap1, so gross > cap1 (since net <= gross)
        // Just deposit the full maxDeposit — net will be cap1 + cap2 - fee < cap1 + cap2
        // But we need net > cap1. Let's bound gross so that net > cap1.
        uint256 maxDep = vault.maxDeposit(depositor);
        // net(gross) = gross - feeOnTotal(gross)
        // We need net > cap1, so gross must be large enough
        // Since fee is small (10 bps), gross ~= net. Just ensure gross > cap1 + 1.
        uint256 grossDeposit = bound(assetsSeed, cap1 + 1, maxDep);
        vm.assume(grossDeposit > cap1);

        uint256 net = _netAfterEntryFee(grossDeposit);
        vm.assume(net > cap1); // net must spill into strategy2

        // Act
        _depositToVault(depositor, grossDeposit);

        // Assert
        uint256 s1Balance = vault.getAssetInStrategy(address(strategy1));
        uint256 s2Balance = vault.getAssetInStrategy(address(strategy2));

        assertEq(s1Balance, cap1, "strategy1 should be filled to its cap");
        assertGt(s2Balance, 0, "strategy2 should receive the overflow");
        assertLe(s2Balance, cap2, "strategy2 balance should not exceed its cap");
    }

    /// @custom:audit-property BTC-STRAT-02b Custom supply queue order changes which strategy fills first
    function testFuzz_Deposit_RespectsCustomSupplyQueueOrder(uint256 assetsSeed, uint256 cap1Seed, uint256 cap2Seed)
        public
    {
        // Arrange — set caps so deposits can span both strategies
        uint256 cap1 = bound(cap1Seed, FC.MIN_BTC_AMOUNT, 10e8);
        uint256 cap2 = bound(cap2Seed, FC.MIN_BTC_AMOUNT, 10e8);
        _safeChangeStrategyCap(address(strategy1), cap1);
        _safeChangeStrategyCap(address(strategy2), cap2);

        // Reverse the supply queue: strategy2 (index 1) first, then strategy1 (index 0)
        uint256[] memory reversedQueue = new uint256[](2);
        reversedQueue[0] = 1;
        reversedQueue[1] = 0;
        _updateSupplyQueue(reversedQueue);

        // Deposit enough so that net > cap2 (strategy2 fills first under reversed queue)
        uint256 maxDep = vault.maxDeposit(depositor);
        uint256 grossDeposit = bound(assetsSeed, cap2 + 1, maxDep);
        vm.assume(grossDeposit > cap2);

        uint256 net = _netAfterEntryFee(grossDeposit);
        vm.assume(net > cap2); // net must spill from strategy2 into strategy1

        // Act
        _depositToVault(depositor, grossDeposit);

        // Assert — under reversed queue, strategy2 should fill to its cap first
        uint256 s1Balance = vault.getAssetInStrategy(address(strategy1));
        uint256 s2Balance = vault.getAssetInStrategy(address(strategy2));

        assertEq(s2Balance, cap2, "strategy2 should be filled to its cap (first in reversed queue)");
        assertGt(s1Balance, 0, "strategy1 should receive the overflow (second in reversed queue)");
        assertLe(s1Balance, cap1, "strategy1 balance should not exceed its cap");
    }

    /// @custom:audit-property BTC-STRAT-03 Deposit reverts when all caps are reached
    /// @dev With entry fees, depositing maxDeposit does not fully fill caps (fee is deducted
    ///      before forwarding to strategies). We set entry fee to 0 for this test so that
    ///      depositing maxDeposit fills caps exactly. Then any further deposit reverts.
    function testFuzz_Deposit_RevertsWhenAllCapsReached(uint256 assetsSeed) public {
        // Remove entry fee so deposits fill caps exactly
        _setEntryFee(0);

        // Arrange - set low caps on both strategies
        uint256 lowCap = FC.MIN_BTC_AMOUNT; // 0.01 BTC
        _safeChangeStrategyCap(address(strategy1), lowCap);
        _safeChangeStrategyCap(address(strategy2), lowCap);

        // maxDeposit = remaining cap = lowCap + lowCap (both empty)
        uint256 maxDep = vault.maxDeposit(depositor);
        vm.assume(maxDep > 0);

        // Deposit exactly maxDeposit to fill caps (no fee, so net == gross == caps)
        _depositToVault(depositor, maxDep);

        // Now maxDeposit should be 0
        uint256 maxDepAfter = vault.maxDeposit(depositor2);
        assertEq(maxDepAfter, 0, "maxDeposit should be 0 when all caps are filled");

        // Any additional deposit should revert
        uint256 extraDeposit = bound(assetsSeed, 1, FC.MAX_BTC_AMOUNT);
        _fundCbBTCAndApprove(depositor2, address(vault), extraDeposit);

        // Act + Assert - OZ ERC4626 reverts with ERC4626ExceededMaxDeposit()
        vm.prank(depositor2);
        vm.expectRevert();
        vault.deposit(extraDeposit, depositor2);
    }

    // ================================================================
    //                   WITHDRAWAL QUEUE TESTS (3)
    // ================================================================

    /// @custom:audit-property BTC-STRAT-04 Withdraw drains strategies in queue order
    function testFuzz_Withdraw_DrainsInQueueOrder(uint256 depositSeed, uint256 withdrawSeed) public {
        // Arrange - deposit across both strategies
        uint256 cap1 = 5e8; // 5 BTC
        uint256 cap2 = 5e8; // 5 BTC
        _safeChangeStrategyCap(address(strategy1), cap1);
        _safeChangeStrategyCap(address(strategy2), cap2);

        // Deposit to fill strategy1 and partially fill strategy2
        uint256 maxDep = vault.maxDeposit(depositor);
        uint256 grossDeposit = bound(depositSeed, cap1 + FC.MIN_BTC_AMOUNT, maxDep);
        // Ensure net > cap1 so strategy2 gets some
        uint256 net = _netAfterEntryFee(grossDeposit);
        vm.assume(net > cap1);

        _depositToVault(depositor, grossDeposit);

        uint256 s1Before = vault.getAssetInStrategy(address(strategy1));
        uint256 s2Before = vault.getAssetInStrategy(address(strategy2));
        vm.assume(s2Before > 0);

        // Withdraw less than what strategy1 holds (accounting for exit fee)
        uint256 maxWithdrawable = vault.maxWithdraw(depositor);
        vm.assume(maxWithdrawable > 0);

        // Need total from strategies (assets + exit fee) <= s1Before
        // totalFromStrategies = assets + assets * exitFee / BPS = assets * (1 + exitFee/BPS)
        // So assets <= s1Before * BPS / (BPS + exitFee)
        uint256 exitFee = vault.getExitFee();
        uint256 maxAssetsFromS1Only = s1Before * BPS_SCALE / (BPS_SCALE + exitFee);
        uint256 upperBound = _utilMin(maxAssetsFromS1Only, maxWithdrawable);
        vm.assume(upperBound > 0);

        uint256 withdrawAmt = bound(withdrawSeed, 1, upperBound);

        // Act
        vm.prank(depositor);
        vault.withdraw(withdrawAmt, depositor, depositor);

        // Assert - strategy1 should be drained first (withdraw queue order: [0, 1])
        uint256 s1After = vault.getAssetInStrategy(address(strategy1));
        uint256 s2After = vault.getAssetInStrategy(address(strategy2));

        assertLt(s1After, s1Before, "strategy1 should have decreased");
        assertEq(s2After, s2Before, "strategy2 should be untouched when strategy1 has enough");
    }

    /// @custom:audit-property BTC-STRAT-05 Withdraw spills to next strategy in queue
    /// @param depositSeed Seed for deposit amount
    /// @param cap1Seed Seed for strategy1 cap
    /// @param cap2Seed Seed for strategy2 cap
    function testFuzz_Withdraw_SpillsToNextStrategy(uint256 depositSeed, uint256 cap1Seed, uint256 cap2Seed) public {
        // Arrange - fill both strategies with fuzzed caps
        uint256 cap1 = bound(cap1Seed, FC.MIN_BTC_AMOUNT, 5e8);
        uint256 cap2 = bound(cap2Seed, FC.MIN_BTC_AMOUNT, 5e8);
        _safeChangeStrategyCap(address(strategy1), cap1);
        _safeChangeStrategyCap(address(strategy2), cap2);

        // Deposit to fill both caps
        uint256 maxDep = vault.maxDeposit(depositor);
        vm.assume(maxDep > 0);
        _depositToVault(depositor, maxDep);

        uint256 s1Before = vault.getAssetInStrategy(address(strategy1));
        uint256 s2Before = vault.getAssetInStrategy(address(strategy2));
        vm.assume(s1Before > 0 && s2Before > 0);

        // Withdraw more than strategy1 holds but within total
        uint256 maxW = vault.maxWithdraw(depositor);
        vm.assume(maxW > s1Before);
        uint256 withdrawAmt = bound(depositSeed, s1Before + 1, maxW);

        // Act
        vm.prank(depositor);
        vault.withdraw(withdrawAmt, depositor, depositor);

        // Assert - both strategies should have been drained
        uint256 s1After = vault.getAssetInStrategy(address(strategy1));
        uint256 s2After = vault.getAssetInStrategy(address(strategy2));

        assertEq(s1After, 0, "strategy1 should be fully drained");
        assertLt(s2After, s2Before, "strategy2 should have been partially drained");
    }

    /// @custom:audit-property BTC-STRAT-06 Withdraw reverts when insufficient liquidity
    function testFuzz_Withdraw_RevertsWhenInsufficientLiquidity(uint256 depositSeed, uint256 withdrawSeed) public {
        // Arrange - small deposit
        uint256 maxDep = vault.maxDeposit(depositor);
        uint256 assets = bound(depositSeed, FC.MIN_BTC_AMOUNT, _utilMin(1e8, maxDep));
        _depositToVault(depositor, assets);

        uint256 maxW = vault.maxWithdraw(depositor);
        vm.assume(maxW > 0);
        // Try to withdraw more than max
        uint256 withdrawAmt = bound(withdrawSeed, maxW + 1, maxW + FC.MAX_BTC_AMOUNT);

        // Act + Assert - OZ ERC4626 reverts with ERC4626ExceededMaxWithdraw()
        vm.prank(depositor);
        vm.expectRevert();
        vault.withdraw(withdrawAmt, depositor, depositor);
    }

    // ================================================================
    //                    REALLOCATION TESTS (5)
    // ================================================================

    /// @custom:audit-property BTC-STRAT-07 Reallocation moves assets between strategies and preserves totalAssets
    function testFuzz_Reallocate_MovesBetweenStrategies(uint256 depositSeed, uint256 reallocateSeed) public {
        // Arrange
        _safeChangeStrategyCap(address(strategy2), FC.DEFAULT_STRATEGY_CAP);

        uint256 maxDep = vault.maxDeposit(depositor);
        uint256 assets = bound(depositSeed, FC.MIN_BTC_AMOUNT, _utilMin(FC.MAX_BTC_AMOUNT, maxDep));
        _depositToVault(depositor, assets);

        uint256 s1Before = vault.getAssetInStrategy(address(strategy1));
        vm.assume(s1Before > 1);

        // Move some from strategy1 to strategy2
        uint256 toMove = bound(reallocateSeed, 1, s1Before);
        uint256 newS1Target = s1Before - toMove;

        DataTypes.Allocation[] memory allocs = new DataTypes.Allocation[](2);
        allocs[0] = DataTypes.Allocation({index: 0, amount: newS1Target});
        allocs[1] = DataTypes.Allocation({index: 1, amount: vault.getAssetInStrategy(address(strategy2)) + toMove});

        uint256 totalBefore = vault.totalAssets();

        // Act
        _reallocate(allocs);

        // Assert
        uint256 s1After = vault.getAssetInStrategy(address(strategy1));
        uint256 s2After = vault.getAssetInStrategy(address(strategy2));

        assertEq(s1After, newS1Target, "strategy1 balance should match target after reallocation");
        assertGe(s2After, toMove, "strategy2 should have received the moved assets");

        uint256 totalAfter = vault.totalAssets();
        assertEq(totalAfter, totalBefore, "totalAssets should be preserved after reallocation");
    }

    /// @custom:audit-property BTC-STRAT-08 Reallocation with type(uint256).max allocates all remaining
    function testFuzz_Reallocate_MaxUint256AllocatesRemaining(uint256 depositSeed) public {
        // Arrange
        _safeChangeStrategyCap(address(strategy2), FC.DEFAULT_STRATEGY_CAP);

        uint256 maxDep = vault.maxDeposit(depositor);
        uint256 assets = bound(depositSeed, FC.MIN_BTC_AMOUNT, _utilMin(FC.MAX_BTC_AMOUNT, maxDep));
        _depositToVault(depositor, assets);

        uint256 s1Before = vault.getAssetInStrategy(address(strategy1));
        vm.assume(s1Before > 0);

        // Move all from strategy1 to strategy2 using type(uint256).max
        DataTypes.Allocation[] memory allocs = new DataTypes.Allocation[](2);
        allocs[0] = DataTypes.Allocation({index: 0, amount: 0});
        allocs[1] = DataTypes.Allocation({index: 1, amount: type(uint256).max});

        // Act
        _reallocate(allocs);

        // Assert
        uint256 s1After = vault.getAssetInStrategy(address(strategy1));
        uint256 s2After = vault.getAssetInStrategy(address(strategy2));

        assertEq(s1After, 0, "strategy1 should be empty after moving all out");
        assertEq(s2After, s1Before, "strategy2 should have received all of strategy1 assets");
    }

    /// @custom:audit-property BTC-STRAT-09 Reallocation reverts when exceeding strategy cap
    function testFuzz_Reallocate_RevertsWhenExceedsCap(uint256 depositSeed, uint256 capSeed) public {
        // Arrange
        uint256 maxDep = vault.maxDeposit(depositor);
        uint256 assets = bound(depositSeed, FC.MIN_BTC_AMOUNT, _utilMin(FC.MAX_BTC_AMOUNT, maxDep));
        _depositToVault(depositor, assets);

        uint256 s1Balance = vault.getAssetInStrategy(address(strategy1));
        vm.assume(s1Balance > 1);

        // Set strategy2 cap smaller than what we want to move
        uint256 smallCap = bound(capSeed, 1, s1Balance - 1);
        _safeChangeStrategyCap(address(strategy2), smallCap);

        // Try to move all from strategy1 to strategy2 (exceeds cap)
        DataTypes.Allocation[] memory allocs = new DataTypes.Allocation[](2);
        allocs[0] = DataTypes.Allocation({index: 0, amount: 0});
        allocs[1] = DataTypes.Allocation({index: 1, amount: type(uint256).max});

        // Act + Assert
        uint256 strategy2Index = vault.getStrategyIndex(address(strategy2));
        vm.expectRevert(abi.encodeWithSelector(Errors.SupplyCapExceeded.selector, strategy2Index));
        _reallocate(allocs);
    }

    /// @custom:audit-property BTC-STRAT-10 Reallocation reverts when supplied != withdrawn
    function testFuzz_Reallocate_RevertsWhenSuppliedNotEqualWithdrawn(uint256 depositSeed) public {
        // Arrange
        _safeChangeStrategyCap(address(strategy2), FC.DEFAULT_STRATEGY_CAP);

        uint256 maxDep = vault.maxDeposit(depositor);
        uint256 assets = bound(depositSeed, FC.MIN_BTC_AMOUNT, _utilMin(FC.MAX_BTC_AMOUNT, maxDep));
        _depositToVault(depositor, assets);

        uint256 s1Balance = vault.getAssetInStrategy(address(strategy1));
        vm.assume(s1Balance > 2);

        // Unbalanced allocation: withdraw all from strategy1 but deposit only half to strategy2
        uint256 newS2Target = s1Balance / 2;

        DataTypes.Allocation[] memory allocs = new DataTypes.Allocation[](2);
        allocs[0] = DataTypes.Allocation({index: 0, amount: 0});
        allocs[1] = DataTypes.Allocation({index: 1, amount: newS2Target});

        // Act + Assert
        vm.expectRevert(Errors.InvalidReallocation.selector);
        _reallocate(allocs);
    }

    // ================================================================
    //               STRATEGY ADDITION/REMOVAL TESTS (4)
    // ================================================================

    /// @custom:audit-property BTC-STRAT-12 New strategy receives deposits after being added
    function testFuzz_AddStrategy_ThenDeposit(uint256 capSeed, uint256 depositSeed) public {
        // Arrange - deploy a 3rd strategy
        new MockAToken("Aave Mock cbBTC 3", "amcbBTC3", 8, address(mockCbBTC), address(mockAavePool));
        mockCbBTC.mint(address(mockAavePool), 10_000e8);
        AaveTokenizedStrategy strategy3 = new AaveTokenizedStrategy(address(mockAavePool), address(vault));

        uint256 cap3 = bound(capSeed, FC.MIN_BTC_AMOUNT, 50e8);
        _addStrategy(address(strategy3), cap3);

        // After addStrategy, withdraw queue auto-appended to [0, 1, 2]
        // Update queues to include all 3 strategies
        uint256[] memory supplyQ = new uint256[](3);
        supplyQ[0] = 0;
        supplyQ[1] = 1;
        supplyQ[2] = 2;
        _updateSupplyQueue(supplyQ);

        // updateWithdrawQueue takes positions in current queue
        // Current withdraw queue after addStrategy auto-push: [0, 1, 2]
        uint256[] memory withdrawQ = new uint256[](3);
        withdrawQ[0] = 0;
        withdrawQ[1] = 1;
        withdrawQ[2] = 2;
        _updateWithdrawQueue(withdrawQ);

        // Set low caps on first two strategies so deposit spills to strategy3
        uint256 lowCap = FC.MIN_BTC_AMOUNT;
        _safeChangeStrategyCap(address(strategy1), lowCap);
        _safeChangeStrategyCap(address(strategy2), lowCap);

        // Deposit just enough to spill into strategy3
        // maxDeposit = lowCap + lowCap + cap3 = remaining caps
        uint256 maxDep = vault.maxDeposit(depositor);
        // Need net > lowCap + lowCap to reach strategy3
        uint256 minGross = lowCap + lowCap + 1;
        vm.assume(maxDep >= minGross);
        uint256 grossDeposit = bound(depositSeed, minGross, maxDep);

        uint256 net = _netAfterEntryFee(grossDeposit);
        vm.assume(net > lowCap + lowCap);

        // Act
        _depositToVault(depositor, grossDeposit);

        // Assert
        uint256 s3Balance = vault.getAssetInStrategy(address(strategy3));
        assertGt(s3Balance, 0, "strategy3 should have received deposits");
    }

    /// @custom:audit-property BTC-STRAT-13 Cannot remove strategy with non-zero balance
    /// @param depositSeed Seed for deposit amount
    function testFuzz_RemoveStrategy_RevertsWithNonZeroBalance(uint256 depositSeed) public {
        // Arrange - use small caps so deposits spill into strategy2
        uint256 cap1 = FC.MIN_BTC_AMOUNT; // 0.01 BTC — fills quickly
        uint256 cap2 = 2e8;
        _safeChangeStrategyCap(address(strategy1), cap1);
        _safeChangeStrategyCap(address(strategy2), cap2);

        // Deposit enough to spill into strategy2
        uint256 maxDep = vault.maxDeposit(depositor);
        uint256 minNeeded = cap1 + FC.MIN_BTC_AMOUNT; // at least cap1 + something for strategy2
        vm.assume(maxDep >= minNeeded);
        uint256 grossDeposit = bound(depositSeed, minNeeded, maxDep);
        uint256 net = _netAfterEntryFee(grossDeposit);
        vm.assume(net > cap1); // net must exceed strategy1 cap

        _depositToVault(depositor, grossDeposit);

        uint256 s2Balance = vault.getAssetInStrategy(address(strategy2));
        assertGt(s2Balance, 0, "setup must place assets in strategy2");

        // Set cap to 0 so removal validation for cap passes
        _changeStrategyCap(address(strategy2), 0);

        // Try to update withdraw queue excluding strategy2 (position 1 in current queue)
        uint256[] memory newWithdrawQ = new uint256[](1);
        newWithdrawQ[0] = 0;

        // Act + Assert - should revert because strategy2 has non-zero balance
        bytes memory data = abi.encodeCall(BTCVault.updateWithdrawQueue, (newWithdrawQ));
        bytes memory revertData =
            abi.encodeWithSelector(Errors.InvalidStrategyRemovalWithNonZeroAssetBalance.selector, 1);
        _scheduleAndExpectRevert(address(vault), bva_slow, BVA_SLOW_ID(), data, revertData);
    }

    /// @custom:audit-property BTC-STRAT-14 Strategy removal succeeds after draining
    function testFuzz_RemoveStrategy_SucceedsAfterDraining(uint256 depositSeed) public {
        // Arrange - deposit some assets (both strategies have default caps, net fits in strategy1)
        uint256 maxDep = vault.maxDeposit(depositor);
        uint256 assets = bound(depositSeed, FC.MIN_BTC_AMOUNT, _utilMin(FC.SMALL_STRATEGY_CAP, maxDep));
        _depositToVault(depositor, assets);

        // Reallocate everything from strategy2 into strategy1
        uint256 s1Balance = vault.getAssetInStrategy(address(strategy1));
        uint256 s2Balance = vault.getAssetInStrategy(address(strategy2));

        if (s2Balance > 0) {
            DataTypes.Allocation[] memory allocs = new DataTypes.Allocation[](2);
            allocs[0] = DataTypes.Allocation({index: 1, amount: 0});
            allocs[1] = DataTypes.Allocation({index: 0, amount: s1Balance + s2Balance});
            _reallocate(allocs);
        }

        // Verify strategy2 is empty
        assertEq(vault.getAssetInStrategy(address(strategy2)), 0, "strategy2 should be empty before removal");

        // Set cap to 0
        _changeStrategyCap(address(strategy2), 0);

        // Update supply queue to exclude strategy2
        uint256[] memory newSupplyQ = new uint256[](1);
        newSupplyQ[0] = 0;
        _updateSupplyQueue(newSupplyQ);

        // Update withdraw queue excluding strategy2 (position 1 in current queue [0, 1])
        uint256[] memory newWithdrawQ = new uint256[](1);
        newWithdrawQ[0] = 0;

        // Act - should succeed since strategy2 has cap=0 and balance=0
        _updateWithdrawQueue(newWithdrawQ);

        // Assert
        assertEq(vault.getWithdrawQueue().length, 1, "withdraw queue should have 1 strategy");
    }

    /// @custom:audit-property BTC-STRAT-15 Strategy with zero cap is skipped on deposit
    /// @param depositSeed Seed for first deposit amount
    /// @param secondDepositSeed Seed for second deposit amount
    function testFuzz_ChangeCapToZero_SkipsOnNextDeposit(uint256 depositSeed, uint256 secondDepositSeed) public {
        // Arrange - use small cap on strategy1 so first deposit spills into strategy2
        uint256 smallCap1 = FC.MIN_BTC_AMOUNT; // 0.01 BTC
        _safeChangeStrategyCap(address(strategy1), smallCap1);
        _safeChangeStrategyCap(address(strategy2), 5e8);

        uint256 maxDep1 = vault.maxDeposit(depositor);
        uint256 minNeeded = smallCap1 + FC.MIN_BTC_AMOUNT;
        vm.assume(maxDep1 >= minNeeded);
        uint256 firstDeposit = bound(depositSeed, minNeeded, maxDep1);
        uint256 net = _netAfterEntryFee(firstDeposit);
        vm.assume(net > smallCap1); // must spill into strategy2

        _depositToVault(depositor, firstDeposit);

        uint256 s2Before = vault.getAssetInStrategy(address(strategy2));
        assertGt(s2Before, 0, "setup must place assets in strategy2");

        // Change strategy2 cap to 0
        _changeStrategyCap(address(strategy2), 0);

        // Restore strategy1 cap so second deposit has room
        _safeChangeStrategyCap(address(strategy1), FC.DEFAULT_STRATEGY_CAP);

        // Update supply queue to remove zero-cap strategy
        uint256[] memory newSupplyQ = new uint256[](1);
        newSupplyQ[0] = 0;
        _updateSupplyQueue(newSupplyQ);

        // Second deposit must fit in strategy1 remaining cap
        uint256 maxDep2 = vault.maxDeposit(depositor2);
        vm.assume(maxDep2 > 0);
        uint256 secondDeposit = bound(secondDepositSeed, FC.MIN_BTC_AMOUNT, _utilMin(5e8, maxDep2));

        // Act
        _depositToVault(depositor2, secondDeposit);

        // Assert
        uint256 s2After = vault.getAssetInStrategy(address(strategy2));
        assertEq(s2After, s2Before, "strategy2 with zero cap should not receive any new deposits");
    }

    // ================================================================
    //                   QUEUE VALIDATION TESTS (3)
    // ================================================================

    /// @custom:audit-property BTC-STRAT-16 Supply queue rejects strategy with zero cap
    function test_UpdateSupplyQueue_RejectsZeroCapStrategy() public {
        // Arrange - set strategy2 cap to 0
        _changeStrategyCap(address(strategy2), 0);

        // Try to update supply queue including strategy2 (index 1)
        uint256[] memory newSupplyQ = new uint256[](2);
        newSupplyQ[0] = 0;
        newSupplyQ[1] = 1;

        bytes memory data = abi.encodeCall(BTCVault.updateSupplyQueue, (newSupplyQ));
        bytes memory revertData = abi.encodeWithSelector(Errors.ZeroCap.selector);

        // Act + Assert
        _scheduleAndExpectRevert(address(vault), bva_slow, BVA_SLOW_ID(), data, revertData);
    }

    /// @custom:audit-property BTC-STRAT-17 Withdraw queue rejects duplicate entries
    function test_UpdateWithdrawQueue_RejectsDuplicates() public {
        // Try to update withdraw queue with [0, 0] (duplicate position)
        uint256[] memory newWithdrawQ = new uint256[](2);
        newWithdrawQ[0] = 0;
        newWithdrawQ[1] = 0;

        bytes memory data = abi.encodeCall(BTCVault.updateWithdrawQueue, (newWithdrawQ));
        // DuplicateStrategy(id) where id is the strategy index at position 0 in current queue
        bytes memory revertData = abi.encodeWithSelector(Errors.DuplicateStrategy.selector, 0);

        // Act + Assert
        _scheduleAndExpectRevert(address(vault), bva_slow, BVA_SLOW_ID(), data, revertData);
    }

    /// @custom:audit-property BTC-STRAT-18 maxDeposit reflects remaining caps
    function testFuzz_MaxDeposit_ReflectsRemainingCaps(uint256 depositSeed, uint256 cap1Seed, uint256 cap2Seed) public {
        // Arrange
        uint256 cap1 = bound(cap1Seed, 1e8, 50e8);
        uint256 cap2 = bound(cap2Seed, 1e8, 50e8);
        _safeChangeStrategyCap(address(strategy1), cap1);
        _safeChangeStrategyCap(address(strategy2), cap2);

        // Deposit partially (ensure within maxDeposit)
        uint256 maxDep = vault.maxDeposit(depositor);
        vm.assume(maxDep >= FC.MIN_BTC_AMOUNT);
        uint256 grossPartial = bound(depositSeed, FC.MIN_BTC_AMOUNT, maxDep);
        _depositToVault(depositor, grossPartial);

        // Act
        uint256 maxDepAfter = vault.maxDeposit(depositor);

        // Assert - maxDeposit should be total remaining capacity across strategies
        uint256 s1Balance = vault.getAssetInStrategy(address(strategy1));
        uint256 s2Balance = vault.getAssetInStrategy(address(strategy2));
        uint256 expectedRemaining =
            (cap1 > s1Balance ? cap1 - s1Balance : 0) + (cap2 > s2Balance ? cap2 - s2Balance : 0);

        assertEq(maxDepAfter, expectedRemaining, "maxDeposit should equal sum of remaining caps across strategies");
    }

    // ================================================================
    //                    SECURITY TESTS
    // ================================================================

    /// @custom:audit-property BTC-STRAT-SEC-01 maxDeposit does not account for entry fees
    /// @notice Depositing exactly maxDeposit() should succeed but strategies won't be fully filled
    /// @param cap1Seed Seed for strategy1 cap
    /// @param cap2Seed Seed for strategy2 cap
    function testFuzz_MaxDeposit_FeeGap_StrategiesNotFullyFilled(uint256 cap1Seed, uint256 cap2Seed) public {
        uint256 cap1 = bound(cap1Seed, 1e8, 10e8);
        uint256 cap2 = bound(cap2Seed, 1e8, 10e8);
        _safeChangeStrategyCap(address(strategy1), cap1);
        _safeChangeStrategyCap(address(strategy2), cap2);

        // Ensure non-zero entry fee
        uint256 entryFee = vault.getEntryFee();
        vm.assume(entryFee > 0);

        uint256 maxDep = vault.maxDeposit(depositor);
        vm.assume(maxDep > 0);

        // Deposit exactly maxDeposit — should succeed
        _depositToVault(depositor, maxDep);

        // Strategies should NOT be fully filled because fee was deducted
        uint256 s1Balance = vault.getAssetInStrategy(address(strategy1));
        uint256 s2Balance = vault.getAssetInStrategy(address(strategy2));
        uint256 totalInStrategies = s1Balance + s2Balance;
        uint256 totalCap = cap1 + cap2;

        // There should be a gap equal to the entry fee
        assertLt(
            totalInStrategies,
            totalCap,
            "with entry fee, depositing maxDeposit should leave a fee-sized gap in strategies"
        );

        // A second depositor should be able to deposit the gap
        uint256 maxDepAfter = vault.maxDeposit(depositor2);
        assertGt(maxDepAfter, 0, "second depositor should still have room due to fee gap");
    }

    /// @custom:audit-property BTC-STRAT-SEC-02 Vault handles strategy liquidity shortage
    /// @notice When Aave pool lacks liquidity, withdrawal must fail with a known failure mode
    /// @param depositSeed Seed for deposit amount
    function testFuzz_Withdraw_HandlesStrategyLiquidityShortage(uint256 depositSeed) public {
        uint256 maxDep = vault.maxDeposit(depositor);
        uint256 assets = bound(depositSeed, FC.MIN_BTC_AMOUNT, _utilMin(5e8, maxDep));
        _depositToVault(depositor, assets);

        uint256 maxW = vault.maxWithdraw(depositor);
        vm.assume(maxW > 0);

        // Drain cbBTC from the Aave pool to simulate liquidity shortage
        uint256 poolBalance = mockCbBTC.balanceOf(address(mockAavePool));
        if (poolBalance > 0) {
            vm.prank(address(mockAavePool));
            mockCbBTC.transfer(address(0xdead), poolBalance - 1);
        }

        // Attempt to withdraw — should revert
        vm.prank(depositor);
        (bool ok, bytes memory ret) =
            address(vault).call(abi.encodeCall(BTCVault.withdraw, (maxW, depositor, depositor)));

        assertFalse(ok, "withdraw should fail under strategy liquidity shortage");

        bytes4 sel = ret.length >= 4 ? bytes4(ret) : bytes4(0);
        bool knownSelector = sel == Errors.NotEnoughLiquidity.selector
            || sel == bytes4(keccak256("ERC4626ExceededMaxWithdraw(address,uint256,uint256)"))
            || sel == bytes4(keccak256("ERC20InsufficientBalance(address,uint256,uint256)"));
        assertTrue(knownSelector, "unexpected revert selector under liquidity shortage");
    }
}
