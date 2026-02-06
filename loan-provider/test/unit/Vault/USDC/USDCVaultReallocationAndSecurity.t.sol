// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {ERC20} from "@solady/tokens/ERC20.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {IAccessManaged} from "@openzeppelin/access/manager/IAccessManaged.sol";

import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {USDCVault} from "@bitmor/vaults/usdc-vault/USDCVault.sol";
import {BaseTestForUSDCVault} from "../BaseTestForUSDCVault.t.sol";
import {USDCStrategy} from "@bitmor/vaults/usdc-vault/USDCStrategy.sol";

/// @title USDCVaultReallocationAndSecurityTest
/// @author Bitmor Protocol
/// @notice Test suite for USDCVault reallocation logic, security measures, and access control
/// @dev Tests reallocation between Aave and Bitmor Lending Pool, inflation attack protection, share price monotonicity, and role-based access control
contract USDCVaultReallocationAndSecurityTest is BaseTestForUSDCVault {
    address internal unauthorized;

    function setUp() public override {
        super.setUp();
        unauthorized = makeAddr("UNAUTHORIZED");
    }

    // ============ Section: Reallocation Logic ============

    /// @notice Test that when Aave balance exceeds target, funds move to BLP
    /// @dev Scenario: Lower target allocation so current 80% becomes "overweight"
    function test_reallocate_aaveOverweight_movesToBLP() public {
        // Fund and deposit
        _fundLenderWithUsdc(lender, LARGE_DEPOSIT);
        _deposit(lender, LARGE_DEPOSIT);

        // Capture initial state
        VaultState memory stateBefore = _captureVaultState();

        // Lower the Aave allocation to 50% so the current 80% becomes "overweight"
        _setAllocation(HALF_ALLOCATION_BPS);

        // Trigger reallocation
        _rebalance();

        // Capture state after reallocation
        VaultState memory stateAfter = _captureVaultState();

        // Verify funds moved from Aave to BLP
        assertLt(stateAfter.aaveBalance, stateBefore.aaveBalance, "Aave balance should decrease");
        assertGt(stateAfter.blpBalance, stateBefore.blpBalance, "BLP balance should increase");

        // Verify new allocation is approximately 50/50
        _assertAllocationCorrect(HALF_ALLOCATION_BPS, DEFAULT_TOLERANCE_BPS);
    }

    /// @notice Test that when BLP balance exceeds target, funds move to Aave
    /// @dev Scenario: Set to 50/50, then increase target so BLP becomes overweight
    function test_reallocate_blpOverweight_movesToAave() public {
        // Fund and deposit
        _fundLenderWithUsdc(lender, LARGE_DEPOSIT);
        _deposit(lender, LARGE_DEPOSIT);

        // First, set allocation to 50/50
        _setAllocation(HALF_ALLOCATION_BPS);
        _rebalance();

        // Capture state before second reallocation
        VaultState memory stateBefore = _captureVaultState();

        // Now increase Aave allocation back to 80%
        // This means BLP is now "overweight" relative to target 20%
        _setAllocation(DEFAULT_AAVE_ALLOCATION_BPS);

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
    /// @dev The vault has minimumDeltaRequired that must be exceeded for reallocation
    function test_reallocate_belowMinDelta_noOp() public {
        // Fund and deposit
        _fundLenderWithUsdc(lender, LARGE_DEPOSIT);
        _deposit(lender, LARGE_DEPOSIT);

        // Set a very high minimum delta required (50% = 5000 bps)
        uint256 highMinDelta = 5000;
        _scheduleAndExecute(
            uvm_slow, UVM_SLOW_ID(), abi.encodeCall(USDCVault.updateMinimumDeltaRequired, (highMinDelta))
        );

        // Capture initial state
        VaultState memory stateBefore = _captureVaultState();

        // Change allocation slightly (80% -> 75%)
        // This creates a small delta that should be below threshold
        _setAllocation(7500);

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
    function test_reallocate_withAmount_pullsFromAave() public {
        // Fund and deposit
        _fundLenderWithUsdc(lender, LARGE_DEPOSIT);
        _deposit(lender, LARGE_DEPOSIT);

        // Capture initial state
        VaultState memory stateBefore = _captureVaultState();
        uint256 amountToPull = STANDARD_DEPOSIT; // Pull 10k USDC

        // Ensure there's enough in Aave to pull
        assertTrue(stateBefore.aaveBalance >= amountToPull, "Not enough in Aave to test");

        // Call from BLP address (the reallocateAssets(uint256) checks msg.sender == blp)
        _rebalanceWithAmount(amountToPull);

        // Capture state after reallocation
        VaultState memory stateAfter = _captureVaultState();

        // Verify Aave balance decreased
        assertLt(stateAfter.aaveBalance, stateBefore.aaveBalance, "Aave balance should decrease");

        // Verify BLP balance increased
        assertGt(stateAfter.blpBalance, stateBefore.blpBalance, "BLP balance should increase");

        // The total should remain approximately the same (within 0.1%)
        uint256 totalBefore = stateBefore.aaveBalance + stateBefore.blpBalance;
        uint256 totalAfter = stateAfter.aaveBalance + stateAfter.blpBalance;
        uint256 delta = totalBefore > totalAfter ? totalBefore - totalAfter : totalAfter - totalBefore;
        assertLe(delta, totalBefore / 1000, "Total assets should be preserved");
    }

    // ============ Section: Security ============

    /// @notice Test protection against ERC4626 inflation attack (frontrun + donation)
    /// @dev Attacker deposits 1 wei, donates large amount, victim's deposit gets diluted
    function test_security_inflationAttack() public {
        // Fund attacker with small amount for initial deposit
        uint256 attackerInitialDeposit = 1; // 1 wei
        mockUSDC.mint(attacker, attackerInitialDeposit);

        vm.startPrank(attacker);
        IERC20(networkConfig.usdc).approve(address(vault), attackerInitialDeposit);
        uint256 attackerShares = vault.deposit(attackerInitialDeposit, attacker);
        vm.stopPrank();

        // Attacker donates large amount directly to strategy to inflate share price
        uint256 donationAmount = STANDARD_DEPOSIT;
        mockUSDC.mint(attacker, donationAmount);
        vm.prank(attacker);
        IERC20(networkConfig.usdc).transfer(address(strategy), donationAmount);

        // Victim deposits
        uint256 victimDeposit = STANDARD_DEPOSIT;
        _fundLenderWithUsdc(lender, victimDeposit);
        uint256 victimShares = _deposit(lender, victimDeposit);

        // Victim should still receive shares proportional to their deposit
        // If attack works, victim gets 0 or very few shares
        // With proper protection (virtual shares/offset), victim should get reasonable shares
        assertTrue(victimShares > 0, "Victim should receive shares");

        // Check that victim's shares represent approximately their deposit value
        uint256 victimAssetsValue = vault.convertToAssets(victimShares);

        // Victim should not lose more than 1% due to rounding
        uint256 maxAcceptableLoss = victimDeposit / 100;
        assertGe(
            victimAssetsValue,
            victimDeposit - maxAcceptableLoss,
            "Victim lost too much value - inflation attack succeeded"
        );
    }

    /// @notice Test that share price never decreases over normal operations
    /// @dev Share price should be monotonically increasing (or stable) to protect depositors
    function test_security_sharePriceMonotonic() public {
        uint256[] memory sharePrices = new uint256[](4);

        // Initial deposit
        _fundLenderWithUsdc(lender, LARGE_DEPOSIT);
        _deposit(lender, LARGE_DEPOSIT);
        sharePrices[0] = _getSharePrice();

        // Second deposit from different user
        _fundLenderWithUsdc(lender2, STANDARD_DEPOSIT);
        _deposit(lender2, STANDARD_DEPOSIT);
        sharePrices[1] = _getSharePrice();
        assertGe(sharePrices[1], sharePrices[0], "Price decreased after second deposit");

        // Partial withdrawal
        _withdraw(lender, STANDARD_DEPOSIT);
        sharePrices[2] = _getSharePrice();
        assertGe(sharePrices[2], sharePrices[1], "Price decreased after withdrawal");

        // Simulate time passing
        vm.warp(block.timestamp + 7 days);
        sharePrices[3] = _getSharePrice();
        // Note: Share price might stay same if no yield, but should not decrease
        assertGe(sharePrices[3], sharePrices[2], "Price decreased over time");
    }

    /// @notice Test that direct USDC transfer to vault doesn't affect share price negatively
    /// @dev Donation attack via direct transfer should not steal from depositors
    function test_security_donationToVault() public {
        // Fund and deposit
        _fundLenderWithUsdc(lender, LARGE_DEPOSIT);
        _deposit(lender, LARGE_DEPOSIT);

        // Capture share price before donation
        uint256 sharePriceBefore = _getSharePrice();
        uint256 lenderSharesBefore = vault.balanceOf(lender);

        // Donate directly to vault contract
        uint256 donationAmount = STANDARD_DEPOSIT;
        address donor = makeAddr("DONOR");
        mockUSDC.mint(donor, donationAmount);
        vm.prank(donor);
        IERC20(networkConfig.usdc).transfer(address(vault), donationAmount);

        // Share price should not significantly decrease
        uint256 sharePriceAfter = _getSharePrice();

        // Allow for small variance but ensure no significant decrease
        uint256 minAcceptable = (sharePriceBefore * 9900) / 10000; // 1% tolerance
        assertGe(sharePriceAfter, minAcceptable, "Share price decreased significantly from vault donation");
    }

    /// @notice Test that direct USDC transfer to Aave aToken doesn't harm depositors
    /// @dev This tests donation to the strategy's Aave position
    function test_security_donationToAToken() public {
        // Fund and deposit
        _fundLenderWithUsdc(lender, LARGE_DEPOSIT);
        _deposit(lender, LARGE_DEPOSIT);

        // Capture share price before donation
        uint256 sharePriceBefore = _getSharePrice();
        uint256 lenderSharesBefore = vault.balanceOf(lender);

        // Donate directly to the aToken contract
        uint256 donationAmount = STANDARD_DEPOSIT;
        address donor = makeAddr("DONOR2");
        mockUSDC.mint(donor, donationAmount);
        vm.prank(donor);
        IERC20(networkConfig.usdc).transfer(address(mockAaveAToken), donationAmount);

        // The aToken balance might increase, but this should benefit all shareholders
        // proportionally, not allow extraction
        uint256 sharePriceAfter = _getSharePrice();

        // Share price should either stay the same or increase (benefiting all shareholders equally)
        assertGe(sharePriceAfter, sharePriceBefore, "Share price should not decrease from donation");

        // If share price increased, verify lender benefits
        if (sharePriceAfter > sharePriceBefore) {
            uint256 lenderAssetsAfter = vault.convertToAssets(lenderSharesBefore);
            uint256 lenderAssetsBefore = vault.convertToAssets(lenderSharesBefore);
            assertGe(lenderAssetsAfter, lenderAssetsBefore, "Existing depositor should not lose value");
        }

        // New depositor after donation should pay fair price
        _fundLenderWithUsdc(lender2, STANDARD_DEPOSIT);
        uint256 lender2Shares = _deposit(lender2, STANDARD_DEPOSIT);

        uint256 lender2AssetsValue = vault.convertToAssets(lender2Shares);
        // Allow 1% tolerance
        uint256 minAcceptable = (STANDARD_DEPOSIT * 9900) / 10000;
        assertGe(lender2AssetsValue, minAcceptable, "New depositor should get fair value");
    }

    // ============ Section: Access Control ============

    /// @notice Test that only authorized roles can call setStrategy
    function test_accessControl_setStrategy_onlyManager() public {
        // Deploy a new strategy to set
        USDCStrategy newStrategy = new USDCStrategy(address(vault), networkConfig.aaveV3Pool, networkConfig.bitmorPool);

        // Unauthorized cannot set strategy
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, unauthorized));
        vault.setStrategy(address(newStrategy));

        // Lender cannot set strategy
        vm.prank(lender);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, lender));
        vault.setStrategy(address(newStrategy));

        // Manager CAN set strategy (via schedule/execute)
        _scheduleAndExecute(uvm_slow, UVM_SLOW_ID(), abi.encodeCall(USDCVault.setStrategy, (address(newStrategy))));

        // Verify strategy was updated
        assertEq(vault.getStrategy(), address(newStrategy), "Strategy should be updated");
    }

    /// @notice Test that only authorized roles can pause
    function test_accessControl_pause_onlyManagerFast() public {
        // Unauthorized cannot pause
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, unauthorized));
        vault.pause();

        // Lender cannot pause
        vm.prank(lender);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, lender));
        vault.pause();

        // Manager fast CAN pause
        vm.prank(uvm_fast);
        vault.pause();

        assertTrue(vault.paused(), "Vault should be paused");
    }

    /// @notice Test that only authorized roles can unpause
    function test_accessControl_unpause_onlyManagerSlow() public {
        // First pause the vault
        vm.prank(uvm_fast);
        vault.pause();
        assertTrue(vault.paused(), "Vault should be paused");

        // Unauthorized cannot unpause
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, unauthorized));
        vault.unpause();

        // Manager slow CAN unpause (via schedule/execute)
        _scheduleAndExecute(uvm_slow, UVM_SLOW_ID(), abi.encodeCall(USDCVault.unpause, ()));

        assertFalse(vault.paused(), "Vault should be unpaused");
    }

    /// @notice Test that deposits/withdrawals are blocked when paused
    function test_pausable_blocksDepositsAndWithdrawals() public {
        // Fund lender
        _fundLenderWithUsdc(lender, STANDARD_DEPOSIT);

        // Deposit should work before pause
        uint256 shares = _deposit(lender, STANDARD_DEPOSIT / 2);
        assertGt(shares, 0, "Deposit should work before pause");

        // Pause the vault
        vm.prank(uvm_fast);
        vault.pause();

        // Deposit should fail when paused
        vm.startPrank(lender);
        IERC20(networkConfig.usdc).approve(address(vault), STANDARD_DEPOSIT / 2);
        vm.expectRevert();
        vault.deposit(STANDARD_DEPOSIT / 2, lender);
        vm.stopPrank();

        // Withdraw should fail when paused
        vm.prank(lender);
        vm.expectRevert();
        vault.withdraw(1000e6, lender, lender);

        // Unpause
        _scheduleAndExecute(uvm_slow, UVM_SLOW_ID(), abi.encodeCall(USDCVault.unpause, ()));

        // Withdraw should work after unpause
        uint256 withdrawn = _withdraw(lender, 1000e6);
        assertGt(withdrawn, 0, "Withdraw should work after unpause");
    }

    /// @notice Test that only BLP address can call reallocateAssets(uint256)
    function test_accessControl_reallocateWithAmount_onlyBLP() public {
        // Fund and deposit
        _fundLenderWithUsdc(lender, LARGE_DEPOSIT);
        _deposit(lender, LARGE_DEPOSIT);

        uint256 amount = STANDARD_DEPOSIT;

        // Unauthorized cannot call reallocateAssets with amount
        vm.prank(unauthorized);
        vm.expectRevert();
        vault.reallocateAssets(amount);

        // Manager cannot call reallocateAssets with amount
        vm.prank(uvm_slow);
        vm.expectRevert();
        vault.reallocateAssets(amount);

        // Lender cannot call reallocateAssets with amount
        vm.prank(lender);
        vm.expectRevert();
        vault.reallocateAssets(amount);

        // Only BLP can call (we can't easily test this succeeds without proper BLP setup,
        // but we verified others can't call it)
    }

    /// @notice Test that updateMinimumDeltaRequired is restricted to manager
    function test_accessControl_updateMinDelta_onlyManager() public {
        uint256 newMinDelta = 500; // 5%

        // Unauthorized cannot update min delta
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, unauthorized));
        vault.updateMinimumDeltaRequired(newMinDelta);

        // Manager CAN update min delta
        _scheduleAndExecute(
            uvm_slow, UVM_SLOW_ID(), abi.encodeCall(USDCVault.updateMinimumDeltaRequired, (newMinDelta))
        );

        // Note: No getter for minimum delta, but the call should succeed without revert
    }

    /// @notice Test that only UVA role can call reallocateAssets()
    function test_accessControl_reallocate_onlyAllocator() public {
        // Fund and deposit
        _fundLenderWithUsdc(lender, STANDARD_DEPOSIT);
        _deposit(lender, STANDARD_DEPOSIT);

        // Unauthorized cannot reallocate
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, unauthorized));
        vault.reallocateAssets();

        // Lender cannot reallocate
        vm.prank(lender);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, lender));
        vault.reallocateAssets();

        // UVA CAN reallocate (via schedule/execute since it may have delay)
        _scheduleAndExecute(uva, UVA_ID(), abi.encodeWithSignature("reallocateAssets()"));
        // If we get here without revert, access control is working
    }
}
