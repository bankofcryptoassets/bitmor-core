// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseTestForUSDCVault} from "../BaseTestForUSDCVault.t.sol";
import {USDCVault} from "@bitmor/vaults/usdc-vault/USDCVault.sol";
import {USDCStrategy} from "@bitmor/vaults/usdc-vault/USDCStrategy.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {ERC4626, ERC20} from "@solady/tokens/ERC4626.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";

/// @title USDCVaultTest
/// @notice Comprehensive test suite for the USDC Vault core functionality
/// @dev Tests ERC4626 compliance, deposit/withdraw mechanics, and strategy management
contract USDCVaultTest is BaseTestForUSDCVault {
    // ============================================
    // ============ SECTION: ERC4626 COMPLIANCE
    // ============================================

    /// @notice Test that deposit() returns expected shares
    function test_deposit_mintsCorrectShares() public {
        uint256 depositAmount = STANDARD_DEPOSIT;

        // Fund lender
        _fundLenderWithUsdc(lender, depositAmount);

        // Preview expected shares before deposit
        uint256 previewedShares = vault.previewDeposit(depositAmount);

        // Execute deposit
        uint256 actualShares = _deposit(lender, depositAmount);

        // Assert: actual shares should equal previewed shares
        assertEq(actualShares, previewedShares, "Deposit should mint previewDeposit() shares");

        // Verify shares were actually minted to lender
        assertEq(vault.balanceOf(lender), actualShares, "Lender should have received the minted shares");
    }

    /// @notice Test that withdraw() burns correct shares
    function test_withdraw_burnsCorrectShares() public {
        uint256 depositAmount = STANDARD_DEPOSIT;

        // Fund and deposit
        _fundLenderWithUsdc(lender, depositAmount);
        _deposit(lender, depositAmount);

        uint256 withdrawAmount = depositAmount / 2;

        // Capture share balance before
        uint256 sharesBefore = vault.balanceOf(lender);

        // Preview expected shares to burn
        uint256 previewedShares = vault.previewWithdraw(withdrawAmount);

        // Execute withdraw
        uint256 actualSharesBurned = _withdraw(lender, withdrawAmount);

        // Assert: actual shares burned should equal previewed shares
        assertEq(actualSharesBurned, previewedShares, "Withdraw should burn previewWithdraw() shares");

        // Verify shares were actually burned from lender
        assertEq(vault.balanceOf(lender), sharesBefore - actualSharesBurned, "Shares should be deducted from lender");
    }

    /// @notice Test that redeem() returns correct assets
    function test_redeem_returnsCorrectAssets() public {
        uint256 depositAmount = STANDARD_DEPOSIT;

        // Fund and deposit
        _fundLenderWithUsdc(lender, depositAmount);
        _deposit(lender, depositAmount);

        uint256 sharesToRedeem = vault.balanceOf(lender) / 2;

        // Preview expected assets to receive
        uint256 previewedAssets = vault.previewRedeem(sharesToRedeem);

        // Capture USDC balance before
        uint256 usdcBefore = IERC20(networkConfig.usdc).balanceOf(lender);

        // Execute redeem
        uint256 actualAssets = _redeem(lender, sharesToRedeem);

        // Assert: actual assets should equal previewed assets
        assertEq(actualAssets, previewedAssets, "Redeem should return previewRedeem() assets");

        // Verify assets were actually transferred to lender
        assertEq(
            IERC20(networkConfig.usdc).balanceOf(lender),
            usdcBefore + actualAssets,
            "Lender should have received assets"
        );
    }

    /// @notice Test that deposit->withdraw roundtrip returns most of principal
    function test_roundtrip_noValueLeak() public {
        uint256 depositAmount = STANDARD_DEPOSIT;

        // Fund lender
        _fundLenderWithUsdc(lender, depositAmount);

        // Execute deposit
        uint256 sharesReceived = _deposit(lender, depositAmount);

        // Execute full redeem
        uint256 assetsReturned = _redeem(lender, sharesReceived);

        // Calculate minimum acceptable return (99% of principal)
        uint256 minAcceptable = (depositAmount * 9900) / BASIS_POINTS;

        // Assert: assets returned should be at least 99% of principal
        assertGe(assetsReturned, minAcceptable, "Roundtrip should return >= 99% of principal");

        // Also assert that we don't gain value (no inflation attack opportunity)
        assertLe(assetsReturned, depositAmount, "Roundtrip should not return more than deposited");
    }

    /// @notice Test that vault metadata returns expected values
    function test_metadata_correct() public view {
        // Check name
        assertEq(vault.name(), "Simple Vault", "Vault name should be 'Simple Vault'");

        // Check symbol
        assertEq(vault.symbol(), "SV", "Vault symbol should be 'SV'");

        // Check asset
        assertEq(vault.asset(), networkConfig.usdc, "Vault asset should be USDC");
    }

    // ============================================
    // ============ SECTION: DEPOSIT MECHANICS
    // ============================================

    /// @notice Test that zero deposit amount reverts
    function test_deposit_zeroAmount_reverts() public {
        _fundLenderWithUsdc(lender, STANDARD_DEPOSIT);

        vm.prank(lender);
        vm.expectRevert();
        vault.deposit(0, lender);
    }

    /// @notice Test that deposit can send shares to a different receiver
    function test_deposit_toReceiver() public {
        address receiver = lender2;

        // Ensure receiver has no shares initially
        assertEq(vault.balanceOf(receiver), 0, "Receiver should have no shares initially");

        // Fund lender and approve vault
        _fundLenderWithUsdc(lender, STANDARD_DEPOSIT);

        // Deposit with different receiver
        vm.startPrank(lender);
        IERC20(networkConfig.usdc).approve(address(vault), STANDARD_DEPOSIT);
        uint256 shares = vault.deposit(STANDARD_DEPOSIT, receiver);
        vm.stopPrank();

        // Assert: shares went to receiver, not depositor
        assertEq(vault.balanceOf(lender), 0, "Depositor should have no shares");
        assertEq(vault.balanceOf(receiver), shares, "Receiver should have all shares");
    }

    // ============================================
    // ============ SECTION: WITHDRAW MECHANICS
    // ============================================

    /// @notice Test that 100% withdrawal works without dust lockup
    function test_withdraw_entireBalance() public {
        // Fund and deposit
        _fundLenderWithUsdc(lender, STANDARD_DEPOSIT);
        _deposit(lender, STANDARD_DEPOSIT);

        // Get all shares
        uint256 allShares = vault.balanceOf(lender);

        // Capture USDC balance before
        uint256 usdcBefore = IERC20(networkConfig.usdc).balanceOf(lender);

        // Redeem all shares
        uint256 assetsReturned = _redeem(lender, allShares);

        // Assert: no shares remaining
        assertEq(vault.balanceOf(lender), 0, "Lender should have no shares remaining");

        // Assert: received assets
        assertGt(assetsReturned, 0, "Should have received some assets");
        assertEq(
            IERC20(networkConfig.usdc).balanceOf(lender),
            usdcBefore + assetsReturned,
            "Lender should have received USDC"
        );
    }

    /// @notice Test that withdrawing more than balance reverts
    function test_withdraw_moreThanBalance_reverts() public {
        // Fund and deposit
        _fundLenderWithUsdc(lender, STANDARD_DEPOSIT);
        _deposit(lender, STANDARD_DEPOSIT);

        // Try to withdraw more than deposited
        uint256 excessAmount = STANDARD_DEPOSIT * 2;

        vm.prank(lender);
        vm.expectRevert();
        vault.withdraw(excessAmount, lender, lender);
    }

    // ============================================
    // ============ SECTION: STRATEGY MANAGEMENT
    // ============================================

    /// @notice Test that setStrategy updates the strategy
    function test_setStrategy_updatesStrategy() public {
        // Deploy new strategy
        USDCStrategy newStrategy = new USDCStrategy(address(vault), networkConfig.aaveV3Pool, networkConfig.bitmorPool);

        // Set new strategy via manager
        _scheduleAndExecute(uvm_slow, UVM_SLOW_ID(), abi.encodeCall(USDCVault.setStrategy, (address(newStrategy))));

        // Verify strategy was updated
        assertEq(vault.getStrategy(), address(newStrategy), "Strategy should be updated");
    }

    /// @notice Test that setting strategy to address(0) reverts
    function test_setStrategy_zeroAddress_reverts() public {
        bytes memory data = abi.encodeCall(USDCVault.setStrategy, (address(0)));
        _scheduleAndExpectRevert(uvm_slow, UVM_SLOW_ID(), data, abi.encodeWithSelector(Errors.ZeroAddress.selector));
    }

    // ============================================
    // ============ SECTION: CONSTRUCTOR
    // ============================================

    /// @notice Test that constructor reverts on zero addresses
    function test_constructor_zeroAddresses_revert() public {
        // Test asset = address(0)
        vm.expectRevert(Errors.ZeroAddress.selector);
        new USDCVault(address(manager), address(0), networkConfig.bitmorPool);

        // Test blp = address(0)
        vm.expectRevert(Errors.ZeroAddress.selector);
        new USDCVault(address(manager), networkConfig.usdc, address(0));
    }

    /// @notice Test that constructor sets immutables correctly
    function test_constructor_setsImmutables() public {
        // Deploy a new vault to test constructor
        USDCVault testVault = new USDCVault(address(manager), networkConfig.usdc, networkConfig.bitmorPool);

        // Verify asset is set correctly
        assertEq(testVault.asset(), networkConfig.usdc, "i_asset should be set to USDC");
    }
}
