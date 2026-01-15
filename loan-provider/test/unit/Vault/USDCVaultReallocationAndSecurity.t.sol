// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseVaultTest} from "./BaseVault.t.sol";
import {USDCVault} from "@bitmor/vault/usdc-vault/USDCVault.sol";
import {USDCStrategy} from "@bitmor/vault/usdc-vault/USDCStrategy.sol";
import {IERC20} from "@bitmor/dependencies/openzeppelin/IERC20.sol";
import {ERC20} from "@solady/tokens/ERC20.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @title USDCVaultReallocationAndSecurityTest
/// @notice Test suite for vault reallocation logic and security measures
/// @dev Tests reallocation between Aave and BLP, security against attacks, and access control
contract USDCVaultReallocationAndSecurityTest is BaseVaultTest {
    // ============ Section 3.1: Reallocation Logic ============

    /// @notice Test that when Aave balance exceeds target allocation, funds move to BLP
    /// @dev Scenario: Manually push more funds to Aave, then reallocate
    function test_reallocate_aaveOverweight_movesToBLP() public withDeposit(LARGE_DEPOSIT) {
        // Capture initial state
        VaultState memory stateBefore = _captureVaultState();
        uint256 aaveBalanceBefore = stateBefore.aaveBalance;
        uint256 blpBalanceBefore = stateBefore.blpBalance;

        // Verify initial allocation is roughly correct (80/20)
        _assertAllocationCorrect();

        // Lower the Aave allocation to 50% so the current 80% becomes "overweight"
        vm.prank(curator);
        strategy.setAaveAllocation(HALF_ALLOCATION_BPS);

        // Now Aave is overweight relative to 50% target
        // Trigger reallocation
        _rebalance();

        // Capture state after reallocation
        VaultState memory stateAfter = _captureVaultState();

        // Verify funds moved from Aave to BLP
        assertLt(stateAfter.aaveBalance, aaveBalanceBefore, "Aave balance should decrease");
        assertGt(stateAfter.blpBalance, blpBalanceBefore, "BLP balance should increase");

        // Verify new allocation is approximately 50/50
        _assertAllocationCorrect(HALF_ALLOCATION_BPS, DEFAULT_TOLERANCE_BPS);

        // Total assets should remain the same (minus any rounding)
        _assertApproxEqBps(
            stateAfter.totalAssets,
            stateBefore.totalAssets,
            STRICT_TOLERANCE_BPS,
            "Total assets should be preserved"
        );
    }

    /// @notice Test that when BLP balance exceeds target allocation, funds move to Aave
    /// @dev Scenario: Lower Aave allocation target, then increase it so BLP becomes overweight
    function test_reallocate_blpOverweight_movesToAave() public withDeposit(LARGE_DEPOSIT) {
        // First, set allocation to 50/50
        vm.prank(curator);
        strategy.setAaveAllocation(HALF_ALLOCATION_BPS);
        _rebalance();

        // Verify 50/50 allocation
        _assertAllocationCorrect(HALF_ALLOCATION_BPS, DEFAULT_TOLERANCE_BPS);

        // Capture state before second reallocation
        VaultState memory stateBefore = _captureVaultState();

        // Now increase Aave allocation back to 80%
        // This means BLP is now "overweight" relative to target 20%
        vm.prank(curator);
        strategy.setAaveAllocation(DEFAULT_AAVE_ALLOCATION_BPS);

        // Trigger reallocation
        _rebalance();

        // Capture state after reallocation
        VaultState memory stateAfter = _captureVaultState();

        // Verify funds moved from BLP to Aave
        assertGt(stateAfter.aaveBalance, stateBefore.aaveBalance, "Aave balance should increase");
        assertLt(stateAfter.blpBalance, stateBefore.blpBalance, "BLP balance should decrease");

        // Verify new allocation is approximately 80/20
        _assertAllocationCorrect(DEFAULT_AAVE_ALLOCATION_BPS, DEFAULT_TOLERANCE_BPS);
    }

    /// @notice Test that reallocation is a no-op when delta is below minimum threshold
    /// @dev The strategy has s_minimumDeltaRequired that must be exceeded for reallocation
    function test_reallocate_belowMinDelta_noOp() public withDeposit(LARGE_DEPOSIT) {
        // Set a very high minimum delta required (e.g., 50% = 5000 bps)
        uint256 highMinDelta = 5000;
        vm.prank(manager);
        vault.updateMinimumDeltaRequired(highMinDelta);

        // Capture initial state
        VaultState memory stateBefore = _captureVaultState();

        // Change allocation slightly (80% -> 75%)
        // This creates a small delta that should be below threshold
        vm.prank(curator);
        strategy.setAaveAllocation(7500);

        // Trigger reallocation
        _rebalance();

        // Capture state after reallocation
        VaultState memory stateAfter = _captureVaultState();

        // Verify balances are unchanged (reallocation was a no-op)
        assertEq(stateAfter.aaveBalance, stateBefore.aaveBalance, "Aave balance should be unchanged");
        assertEq(stateAfter.blpBalance, stateBefore.blpBalance, "BLP balance should be unchanged");
    }

    /// @notice Test reallocateAssets(uint256) pulls exact amount from Aave to BLP
    /// @dev This is the borrower priority function called by BLP when liquidity is needed
    function test_reallocate_withAmount_pullsFromAave() public withDeposit(LARGE_DEPOSIT) {
        // Capture initial state
        VaultState memory stateBefore = _captureVaultState();
        uint256 amountToPull = STANDARD_DEPOSIT; // Pull 10k USDC

        // Ensure there's enough in Aave to pull
        assertTrue(stateBefore.aaveBalance >= amountToPull, "Not enough in Aave to test");

        // The reallocateAssets(uint256) function calculates how much to pull from Aave
        // to maintain ratio after the amount is withdrawn from BLP
        // Call from BLP address
        _rebalanceWithAmount(amountToPull);

        // Capture state after reallocation
        VaultState memory stateAfter = _captureVaultState();

        // Verify Aave balance decreased
        assertLt(stateAfter.aaveBalance, stateBefore.aaveBalance, "Aave balance should decrease");

        // Verify BLP balance increased to accommodate the borrower demand
        assertGt(stateAfter.blpBalance, stateBefore.blpBalance, "BLP balance should increase");

        // The total should remain approximately the same
        _assertApproxEqBps(
            stateAfter.totalAssets,
            stateBefore.totalAssets,
            STRICT_TOLERANCE_BPS,
            "Total assets should be preserved"
        );
    }

    // ============ Section 3.2: Security ============

    /// @notice Test protection against ERC4626 inflation attack (frontrun + donation)
    /// @dev Attacker deposits 1 wei, donates large amount, victim's deposit gets diluted
    function test_security_inflationAttack() public {
        // Fund attacker with small amount for initial deposit
        uint256 attackerInitialDeposit = 1; // 1 wei
        _fundLenderWithUsdc(attacker, attackerInitialDeposit);

        // Attacker deposits 1 wei to become first depositor
        vm.prank(attacker);
        uint256 attackerShares = vault.deposit(attackerInitialDeposit, attacker);

        // Attacker donates large amount directly to inflate share price
        uint256 donationAmount = STANDARD_DEPOSIT;
        _donate(address(strategy), donationAmount);

        // Record share price after donation
        uint256 sharePriceAfterDonation = _getSharePrice();

        // Victim deposits
        uint256 victimDeposit = STANDARD_DEPOSIT;
        _fundLenderWithUsdc(lender, victimDeposit);
        vm.prank(lender);
        uint256 victimShares = vault.deposit(victimDeposit, lender);

        // Victim should still receive shares proportional to their deposit
        // If attack works, victim gets 0 or very few shares
        // With proper protection (virtual shares/offset), victim should get reasonable shares
        assertTrue(victimShares > 0, "Victim should receive shares");

        // Check that victim's shares represent approximately their deposit value
        uint256 victimAssetsValue = vault.convertToAssets(victimShares);

        // Victim should not lose more than a small percentage due to rounding
        // Allow up to 1% loss due to rounding in worst case
        uint256 maxAcceptableLoss = victimDeposit / 100;
        assertGe(
            victimAssetsValue,
            victimDeposit - maxAcceptableLoss,
            "Victim lost too much value - inflation attack succeeded"
        );
    }

    /// @notice Test that direct USDC transfer to vault doesn't affect share price
    /// @dev Donation attack via direct transfer should not steal from depositors
    function test_security_donationToVault() public withDeposit(LARGE_DEPOSIT) {
        // Capture share price before donation
        uint256 sharePriceBefore = _getSharePrice();
        uint256 lenderSharesBefore = vault.balanceOf(lender);

        // Donate directly to vault contract
        uint256 donationAmount = STANDARD_DEPOSIT;
        _donate(address(vault), donationAmount);

        // Share price should not significantly change
        // The donation to vault contract address should not affect totalAssets()
        // because totalAssets() queries the strategy's balance in Aave + BLP
        uint256 sharePriceAfter = _getSharePrice();

        // Share price should remain the same (donation to vault doesn't affect strategy balances)
        assertEq(sharePriceAfter, sharePriceBefore, "Share price should not change from vault donation");

        // Lender's shares should still be worth the same
        uint256 lenderAssetsAfter = vault.convertToAssets(lenderSharesBefore);
        uint256 expectedAssets = (lenderSharesBefore * sharePriceBefore) / SHARE_PRICE_PRECISION;

        _assertApproxEqBps(lenderAssetsAfter, expectedAssets, STRICT_TOLERANCE_BPS, "Lender value should be unchanged");
    }

    /// @notice Test that direct USDC transfer to Aave aToken doesn't affect share price
    /// @dev This tests donation to the strategy's Aave position
    function test_security_donationToAToken() public withDeposit(LARGE_DEPOSIT) {
        // Capture share price before donation
        uint256 sharePriceBefore = _getSharePrice();
        UserState memory userStateBefore = _captureUserState(lender);

        // Donate directly to the aToken contract (where strategy holds aTokens)
        uint256 donationAmount = STANDARD_DEPOSIT;
        _donate(aaveAToken, donationAmount);

        // The aToken balance of strategy might increase, but this should benefit all shareholders
        // proportionally, not allow extraction
        uint256 sharePriceAfter = _getSharePrice();

        // Share price should either stay the same or increase (benefiting all shareholders equally)
        assertGe(sharePriceAfter, sharePriceBefore, "Share price should not decrease from donation");

        // If share price increased, verify all shareholders benefit proportionally
        if (sharePriceAfter > sharePriceBefore) {
            // Lender's asset value should have increased
            uint256 lenderAssetsAfter = vault.convertToAssets(userStateBefore.shareBalance);
            assertGt(lenderAssetsAfter, userStateBefore.assetValue, "Lender should benefit from donation");
        }

        // Critically, no single actor should be able to extract this donated value unfairly
        // A new depositor after donation should pay the new higher share price
        _fundLenderWithUsdc(lender2, STANDARD_DEPOSIT);
        vm.prank(lender2);
        uint256 lender2Shares = vault.deposit(STANDARD_DEPOSIT, lender2);

        // lender2 should receive fewer shares than lender got for same deposit (if price increased)
        // This ensures lender2 isn't stealing from existing depositors
        uint256 lender2AssetsValue = vault.convertToAssets(lender2Shares);
        _assertApproxEqBps(
            lender2AssetsValue,
            STANDARD_DEPOSIT,
            LOOSE_TOLERANCE_BPS,
            "New depositor should get fair value"
        );
    }

    /// @notice Test that share price never decreases over normal operations
    /// @dev Share price should be monotonically increasing (or stable) to protect depositors
    function test_security_sharePriceMonotonic() public {
        uint256[] memory sharePrices = new uint256[](6);

        // Initial deposit
        _fundLenderWithUsdc(lender, LARGE_DEPOSIT);
        vm.prank(lender);
        vault.deposit(LARGE_DEPOSIT, lender);
        sharePrices[0] = _getSharePrice();

        // Second deposit from different user
        _fundLenderWithUsdc(lender2, STANDARD_DEPOSIT);
        vm.prank(lender2);
        vault.deposit(STANDARD_DEPOSIT, lender2);
        sharePrices[1] = _getSharePrice();
        assertGe(sharePrices[1], sharePrices[0], "Price decreased after second deposit");

        // Partial withdrawal
        vm.prank(lender);
        vault.withdraw(STANDARD_DEPOSIT, lender, lender);
        sharePrices[2] = _getSharePrice();
        assertGe(sharePrices[2], sharePrices[1], "Price decreased after withdrawal");

        // Reallocation (change allocation and rebalance)
        vm.prank(curator);
        strategy.setAaveAllocation(HALF_ALLOCATION_BPS);
        _rebalance();
        sharePrices[3] = _getSharePrice();
        assertGe(sharePrices[3], sharePrices[2], "Price decreased after reallocation");

        // Simulate time passing (yield accrual in Aave)
        _warpDays(7);
        sharePrices[4] = _getSharePrice();
        // Note: Share price might stay same if no yield, but should not decrease
        assertGe(sharePrices[4], sharePrices[3], "Price decreased over time");

        // Another reallocation back to original ratio
        vm.prank(curator);
        strategy.setAaveAllocation(DEFAULT_AAVE_ALLOCATION_BPS);
        _rebalance();
        sharePrices[5] = _getSharePrice();
        assertGe(sharePrices[5], sharePrices[4], "Price decreased after second reallocation");
    }

    // ============ Section 3.3: Access Control ============

    /// @notice Test that only MANAGER can call setStrategy
    function test_accessControl_setStrategy_onlyManager() public {
        // Deploy a new strategy to set
        USDCStrategy newStrategy = new USDCStrategy(address(vault), aavePool, bitmorPool, deployer);

        // Attacker cannot set strategy
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, attacker, MANAGER_ROLE
            )
        );
        vault.setStrategy(address(newStrategy));

        // Allocator cannot set strategy
        vm.prank(allocator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, allocator, MANAGER_ROLE
            )
        );
        vault.setStrategy(address(newStrategy));

        // Curator cannot set strategy
        vm.prank(curator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, curator, MANAGER_ROLE
            )
        );
        vault.setStrategy(address(newStrategy));

        // Manager CAN set strategy
        vm.prank(manager);
        vault.setStrategy(address(newStrategy));

        // Verify strategy was updated
        assertEq(vault.getStrategy(), address(newStrategy), "Strategy should be updated");
    }

    /// @notice Test that only ALLOCATOR can call reallocateAssets()
    function test_accessControl_reallocate_onlyAllocator() public withDeposit(STANDARD_DEPOSIT) {
        // Attacker cannot reallocate
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, attacker, ALLOCATOR_ROLE
            )
        );
        vault.reallocateAssets();

        // Manager cannot reallocate (different role)
        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, manager, ALLOCATOR_ROLE
            )
        );
        vault.reallocateAssets();

        // Lender cannot reallocate
        vm.prank(lender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, lender, ALLOCATOR_ROLE
            )
        );
        vault.reallocateAssets();

        // Allocator CAN reallocate
        vm.prank(allocator);
        vault.reallocateAssets(); // Should not revert
    }

    /// @notice Test that only BLP address can call reallocateAssets(uint256)
    function test_accessControl_reallocateWithAmount_onlyBLP() public withDeposit(LARGE_DEPOSIT) {
        uint256 amount = STANDARD_DEPOSIT;

        // Attacker cannot call reallocateAssets with amount
        vm.prank(attacker);
        vm.expectRevert(Errors.UnauthorizedCaller.selector);
        vault.reallocateAssets(amount);

        // Manager cannot call reallocateAssets with amount
        vm.prank(manager);
        vm.expectRevert(Errors.UnauthorizedCaller.selector);
        vault.reallocateAssets(amount);

        // Allocator cannot call reallocateAssets with amount
        vm.prank(allocator);
        vm.expectRevert(Errors.UnauthorizedCaller.selector);
        vault.reallocateAssets(amount);

        // Lender cannot call reallocateAssets with amount
        vm.prank(lender);
        vm.expectRevert(Errors.UnauthorizedCaller.selector);
        vault.reallocateAssets(amount);

        // BLP CAN call reallocateAssets with amount
        vm.prank(bitmorPool);
        vault.reallocateAssets(amount); // Should not revert
    }

    /// @notice Test that only MANAGER can call updateMinimumDeltaRequired
    function test_accessControl_updateMinDelta_onlyManager() public {
        uint256 newMinDelta = 500; // 5%

        // Attacker cannot update min delta
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, attacker, MANAGER_ROLE
            )
        );
        vault.updateMinimumDeltaRequired(newMinDelta);

        // Allocator cannot update min delta
        vm.prank(allocator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, allocator, MANAGER_ROLE
            )
        );
        vault.updateMinimumDeltaRequired(newMinDelta);

        // Curator cannot update min delta
        vm.prank(curator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, curator, MANAGER_ROLE
            )
        );
        vault.updateMinimumDeltaRequired(newMinDelta);

        // Manager CAN update min delta
        vm.prank(manager);
        vault.updateMinimumDeltaRequired(newMinDelta); // Should not revert
    }
}
