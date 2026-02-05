// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseTestForUSDCVault} from "../BaseTestForUSDCVault.t.sol";
import {USDCVault} from "@bitmor/vaults/usdc-vault/USDCVault.sol";
import {USDCStrategy} from "@bitmor/vaults/usdc-vault/USDCStrategy.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {ERC4626, ERC20} from "@solady/tokens/ERC4626.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {IAccessManager} from "@openzeppelin/access/manager/IAccessManager.sol";

/// @title USDCVaultTest
/// @author Bitmor Protocol
/// @notice Comprehensive test suite for the USDC Vault core functionality
/// @dev Tests ERC-4626 compliance, deposit/withdraw mechanics, and strategy management
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

    /// @notice Test that convertToShares/convertToAssets favor the vault (round down)
    /// @dev ERC4626 requires rounding to favor the vault for security
    function test_conversions_roundDown() public {
        // Fund and deposit to establish share price
        _fundLenderWithUsdc(lender, STANDARD_DEPOSIT);
        _deposit(lender, STANDARD_DEPOSIT);

        // Test with amounts that may cause rounding
        uint256 testAssets = 1000001; // Odd number likely to require rounding
        uint256 testShares = 1000001;

        // convertToShares should round down (favor vault - fewer shares for depositor)
        uint256 sharesFromConvert = vault.convertToShares(testAssets);
        uint256 assetsNeededForShares = vault.convertToAssets(sharesFromConvert);

        // Converting back should give same or fewer assets (proving round down)
        assertLe(assetsNeededForShares, testAssets, "convertToShares should round down");

        // convertToAssets should round down (favor vault - fewer assets for withdrawer)
        uint256 assetsFromConvert = vault.convertToAssets(testShares);
        uint256 sharesNeededForAssets = vault.convertToShares(assetsFromConvert);

        // Converting back should require same or fewer shares (proving round down)
        assertLe(sharesNeededForAssets, testShares, "convertToAssets should round down");
    }

    /// @notice Test that vault metadata returns expected values
    function test_metadata_correct() public view {
        // Check name
        assertEq(vault.name(), "Bitmor USDC Vault", "Vault name should be 'Bitmor USDC Vault'");

        // Check symbol
        assertEq(vault.symbol(), "bvUSDC", "Vault symbol should be 'bvUSDC'");

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

    /// @notice Test that deposit splits 80% to Aave and 20% to BLP
    /// @dev Verifies the default allocation ratio is respected (set in setUp via _setStrategy)
    function test_deposit_splitsToAaveAndBLP() public {
        // Capture balances before
        uint256 aaveBefore = _getAaveBalance();
        uint256 blpBefore = _getBLPBalance();

        // Fund and deposit
        _fundLenderWithUsdc(lender, STANDARD_DEPOSIT);
        _deposit(lender, STANDARD_DEPOSIT);

        // Capture balances after
        uint256 aaveAfter = _getAaveBalance();
        uint256 blpAfter = _getBLPBalance();

        // Calculate actual allocations
        uint256 aaveIncrease = aaveAfter - aaveBefore;
        uint256 blpIncrease = blpAfter - blpBefore;

        // Calculate expected allocations (80/20)
        uint256 expectedAave = (STANDARD_DEPOSIT * DEFAULT_AAVE_ALLOCATION_BPS) / BASIS_POINTS;
        uint256 expectedBLP = STANDARD_DEPOSIT - expectedAave;

        // Assert allocations are within tolerance (1%)
        uint256 aaveDelta = aaveIncrease > expectedAave ? aaveIncrease - expectedAave : expectedAave - aaveIncrease;
        uint256 blpDelta = blpIncrease > expectedBLP ? blpIncrease - expectedBLP : expectedBLP - blpIncrease;

        assertLe(aaveDelta, expectedAave / 100, "Aave allocation should be ~80%");
        assertLe(blpDelta, expectedBLP / 100, "BLP allocation should be ~20%");
    }

    /// @notice Test that changing allocation to 50/50 affects new deposits
    /// @dev Verifies custom allocation is respected after setAaveAllocation
    function test_deposit_customAllocation() public {
        // Change allocation to 50/50
        _setAllocation(HALF_ALLOCATION_BPS);

        // Capture balances before
        uint256 aaveBefore = _getAaveBalance();
        uint256 blpBefore = _getBLPBalance();

        // Fund and deposit
        _fundLenderWithUsdc(lender, STANDARD_DEPOSIT);
        _deposit(lender, STANDARD_DEPOSIT);

        // Capture balances after
        uint256 aaveAfter = _getAaveBalance();
        uint256 blpAfter = _getBLPBalance();

        // Calculate actual allocations
        uint256 aaveIncrease = aaveAfter - aaveBefore;
        uint256 blpIncrease = blpAfter - blpBefore;

        // Both should be approximately 50%
        uint256 expectedEach = STANDARD_DEPOSIT / 2;
        uint256 aaveDelta = aaveIncrease > expectedEach ? aaveIncrease - expectedEach : expectedEach - aaveIncrease;
        uint256 blpDelta = blpIncrease > expectedEach ? blpIncrease - expectedEach : expectedEach - blpIncrease;

        assertLe(aaveDelta, expectedEach / 10, "Aave allocation should be ~50%");
        assertLe(blpDelta, expectedEach / 10, "BLP allocation should be ~50%");
    }

    // ============================================
    // ============ SECTION: MINT MECHANICS
    // ============================================

    /// @notice Test that mint() returns expected assets required
    function test_mint_mintsCorrectAssets() public {
        uint256 sharesToMint = 1000e6;

        // Fund lender
        _fundLenderWithUsdc(lender, LARGE_DEPOSIT);

        // Preview expected assets before mint
        uint256 previewedAssets = vault.previewMint(sharesToMint);

        // Execute mint
        vm.startPrank(lender);
        IERC20(networkConfig.usdc).approve(address(vault), previewedAssets);
        uint256 actualAssets = vault.mint(sharesToMint, lender);
        vm.stopPrank();

        // Assert: actual assets should equal previewed assets
        assertEq(actualAssets, previewedAssets, "Mint should require previewMint() assets");

        // Verify shares were actually minted to lender
        assertEq(vault.balanceOf(lender), sharesToMint, "Lender should have received the minted shares");
    }

    /// @notice Test that mint() can send shares to a different receiver
    function test_mint_toReceiver() public {
        address receiver = lender2;
        uint256 sharesToMint = 1000e6;

        // Ensure receiver has no shares initially
        assertEq(vault.balanceOf(receiver), 0, "Receiver should have no shares initially");

        // Fund lender
        _fundLenderWithUsdc(lender, LARGE_DEPOSIT);
        uint256 assetsRequired = vault.previewMint(sharesToMint);

        // Mint with different receiver
        vm.startPrank(lender);
        IERC20(networkConfig.usdc).approve(address(vault), assetsRequired);
        vault.mint(sharesToMint, receiver);
        vm.stopPrank();

        // Assert: shares went to receiver, not minter
        assertEq(vault.balanceOf(lender), 0, "Minter should have no shares");
        assertEq(vault.balanceOf(receiver), sharesToMint, "Receiver should have all shares");
    }

    /// @notice Test that mint() reverts when paused
    function test_mint_RevertWhen_Paused() public {
        uint256 sharesToMint = 1000e6;

        // Fund lender
        _fundLenderWithUsdc(lender, LARGE_DEPOSIT);
        uint256 assetsRequired = vault.previewMint(sharesToMint);

        // Pause the vault
        vm.prank(uvm_fast);
        vault.pause();

        // Attempt to mint should revert
        vm.startPrank(lender);
        IERC20(networkConfig.usdc).approve(address(vault), assetsRequired);
        vm.expectRevert();
        vault.mint(sharesToMint, lender);
        vm.stopPrank();
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

    /// @notice Test that third-party withdrawal with approval works
    /// @dev Verifies ERC4626 allowance mechanism for withdrawals
    function test_withdraw_withAllowance() public {
        // Fund and deposit
        _fundLenderWithUsdc(lender, STANDARD_DEPOSIT);
        _deposit(lender, STANDARD_DEPOSIT);

        address withdrawer = lender2;
        uint256 withdrawAmount = STANDARD_DEPOSIT / 2;

        // Lender approves withdrawer to spend shares
        uint256 shareAllowance = vault.previewWithdraw(withdrawAmount) + 100; // Add buffer for rounding
        vm.prank(lender);
        vault.approve(withdrawer, shareAllowance);

        // Capture balances before
        uint256 lenderSharesBefore = vault.balanceOf(lender);
        uint256 withdrawerUsdcBefore = IERC20(networkConfig.usdc).balanceOf(withdrawer);

        // Withdrawer executes withdrawal on behalf of lender, receiving assets themselves
        vm.prank(withdrawer);
        uint256 sharesBurned = vault.withdraw(withdrawAmount, withdrawer, lender);

        // Assert: shares were burned from lender
        assertEq(vault.balanceOf(lender), lenderSharesBefore - sharesBurned, "Shares should be burned from lender");

        // Assert: assets went to withdrawer
        assertEq(
            IERC20(networkConfig.usdc).balanceOf(withdrawer),
            withdrawerUsdcBefore + withdrawAmount,
            "Withdrawer should receive the assets"
        );
    }

    /// @notice Test that post-withdraw allocation stays within tolerance
    /// @dev Verifies the allocation ratio is maintained after withdrawal (allocation set in setUp)
    function test_withdraw_maintainsRatio() public {
        // Fund and deposit large amount
        _fundLenderWithUsdc(lender, LARGE_DEPOSIT);
        _deposit(lender, LARGE_DEPOSIT);

        // Verify initial allocation is correct
        _assertAllocationCorrect();

        // Withdraw half of the deposit
        uint256 withdrawAmount = LARGE_DEPOSIT / 2;
        _withdraw(lender, withdrawAmount);

        // Verify allocation still maintains the 80/20 ratio within loose tolerance
        _assertAllocationCorrect(DEFAULT_AAVE_ALLOCATION_BPS, LOOSE_TOLERANCE_BPS);
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

    /// @notice Test that setStrategy withdraws funds from old strategy
    /// @dev Verifies withdrawAllFunds is called on old strategy during migration (allocation set in setUp)
    function test_setStrategy_migratesFunds() public {
        // Fund and deposit
        _fundLenderWithUsdc(lender, STANDARD_DEPOSIT);
        _deposit(lender, STANDARD_DEPOSIT);

        // Verify funds are in current strategy's markets
        uint256 oldStrategyMarketBalance = strategy.getTotalBalanceInMarkets();
        assertGt(oldStrategyMarketBalance, 0, "Old strategy should have funds in markets");

        // Deploy new strategy
        USDCStrategy newStrategy = new USDCStrategy(address(vault), networkConfig.aaveV3Pool, networkConfig.bitmorPool);

        // Change to new strategy (manager role with delay)
        _scheduleAndExecute(uvm_slow, UVM_SLOW_ID(), abi.encodeCall(USDCVault.setStrategy, (address(newStrategy))));

        // Old strategy markets should be emptied (withdrawn from Aave/BLP)
        uint256 oldStrategyMarketBalanceAfter = strategy.getTotalBalanceInMarkets();
        assertEq(oldStrategyMarketBalanceAfter, 0, "Old strategy markets should be emptied after migration");

        // Verify the old strategy withdrew from external protocols
        // The assets are now sitting in the old strategy contract (not in markets)
        uint256 oldStrategyUsdcBalance = IERC20(networkConfig.usdc).balanceOf(address(strategy));
        assertGt(oldStrategyUsdcBalance, 0, "Old strategy should hold withdrawn USDC");

        // Note: Current implementation does not transfer to vault - assets remain in old strategy
        // This test documents actual behavior; consider this a known limitation
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

    // ============================================
    // ============ SECTION: Pausability
    // ============================================

    function test_pause() public {
        vm.prank(uvm_fast);
        bytes memory data = abi.encodeWithSelector(vault.pause.selector);
        _scheduleAndExecute(uvm_fast, UVM_FAST_ID(), data);

        bool currentStatus = vault.paused();
        assertEq(currentStatus, true);
    }

    function test_pause_revertWhen_UnauthorizedCallerCalls() public {
        vm.prank(attacker);
        bytes memory data = abi.encodeWithSelector(vault.pause.selector);
        bytes memory revertData = abi.encodeWithSelector(
            IAccessManager.AccessManagerUnauthorizedCall.selector, attacker, address(vault), vault.pause.selector
        );
        _scheduleAndExpectRevert(attacker, UVM_FAST_ID(), data, revertData);
    }
}
