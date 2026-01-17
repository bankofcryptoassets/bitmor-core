// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseTestForUSDCVault} from "../BaseTestForUSDCVault.t.sol";
import {USDCVault} from "@bitmor/vaults/usdc-vault/USDCVault.sol";
import {USDCStrategy} from "@bitmor/vaults/usdc-vault/USDCStrategy.sol";
import {IERC20} from "@bitmor/dependencies/openzeppelin/IERC20.sol";
import {ERC20} from "@solady/tokens/ERC20.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {IAccessManaged} from "@openzeppelin/access/manager/IAccessManaged.sol";

/// @title USDCVaultReallocationAndSecurityTest
/// @notice Test suite for vault security measures and access control
/// @dev Tests security against attacks and access control with AccessManager pattern
contract USDCVaultReallocationAndSecurityTest is BaseTestForUSDCVault {
    address internal unauthorized;

    function setUp() public override {
        super.setUp();
        unauthorized = makeAddr("UNAUTHORIZED");
    }

    // ============ Section: Security ============

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
        vm.prank(networkConfig.usdc_holder);
        IERC20(networkConfig.usdc).transfer(address(vault), donationAmount);

        // Share price should not significantly decrease
        uint256 sharePriceAfter = _getSharePrice();

        // Allow for small variance but ensure no significant decrease
        uint256 minAcceptable = (sharePriceBefore * 9900) / 10000; // 1% tolerance
        assertGe(sharePriceAfter, minAcceptable, "Share price decreased significantly from vault donation");
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
        _scheduleAndExecute(
            uvm_slow, UVM_SLOW_ID, abi.encodeCall(USDCVault.setStrategy, (address(newStrategy)))
        );

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
        _scheduleAndExecute(uvm_slow, UVM_SLOW_ID, abi.encodeCall(USDCVault.unpause, ()));

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
        _scheduleAndExecute(uvm_slow, UVM_SLOW_ID, abi.encodeCall(USDCVault.unpause, ()));

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
            uvm_slow, UVM_SLOW_ID, abi.encodeCall(USDCVault.updateMinimumDeltaRequired, (newMinDelta))
        );

        // Note: No getter for minimum delta, but the call should succeed without revert
    }
}
