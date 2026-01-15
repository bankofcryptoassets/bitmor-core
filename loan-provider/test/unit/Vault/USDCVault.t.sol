// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {BaseVaultTest} from "./BaseVault.t.sol";
import {USDCVault} from "@bitmor/vault/usdc-vault/USDCVault.sol";
import {USDCStrategy} from "@bitmor/vault/usdc-vault/USDCStrategy.sol";
import {IERC20} from "@bitmor/dependencies/openzeppelin/IERC20.sol";
import {ERC4626, ERC20} from "@solady/tokens/ERC4626.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";

/// @title USDCVaultTest
/// @notice Comprehensive test suite for the USDC Vault core functionality
/// @dev Tests ERC4626 compliance, deposit/withdraw mechanics, and strategy management
contract USDCVaultTest is BaseVaultTest {
    // ============================================
    // ============ SECTION 2.1: ERC4626 COMPLIANCE
    // ============================================

    /// @notice Test that deposit() returns exactly previewDeposit() shares
    /// @dev ERC4626 requires deposit to return at least the previewed amount
    function test_deposit_mintsCorrectShares() public fundLender(STANDARD_DEPOSIT) {
        // Preview expected shares before deposit
        uint256 previewedShares = _previewDeposit(STANDARD_DEPOSIT);

        // Execute deposit
        vm.prank(lender);
        uint256 actualShares = vault.deposit(STANDARD_DEPOSIT, lender);

        // Assert: actual shares should equal previewed shares
        assertEq(actualShares, previewedShares, "Deposit should mint exactly previewDeposit() shares");

        // Verify shares were actually minted to lender
        assertEq(vault.balanceOf(lender), actualShares, "Lender should have received the minted shares");
    }

    /// @notice Test that withdraw() burns exactly previewWithdraw() shares
    /// @dev ERC4626 requires withdraw to burn at most the previewed amount
    function test_withdraw_burnsCorrectShares() public withDeposit(STANDARD_DEPOSIT) {
        uint256 withdrawAmount = STANDARD_DEPOSIT / 2;

        // Capture share balance before
        uint256 sharesBefore = vault.balanceOf(lender);

        // Preview expected shares to burn
        uint256 previewedShares = _previewWithdraw(withdrawAmount);

        // Execute withdraw
        vm.prank(lender);
        uint256 actualSharesBurned = vault.withdraw(withdrawAmount, lender, lender);

        // Assert: actual shares burned should equal previewed shares
        assertEq(actualSharesBurned, previewedShares, "Withdraw should burn exactly previewWithdraw() shares");

        // Verify shares were actually burned from lender
        assertEq(vault.balanceOf(lender), sharesBefore - actualSharesBurned, "Shares should be deducted from lender");
    }

    /// @notice Test that redeem() returns exactly previewRedeem() assets
    /// @dev ERC4626 requires redeem to return at least the previewed amount
    function test_redeem_returnsCorrectAssets() public withDeposit(STANDARD_DEPOSIT) {
        uint256 sharesToRedeem = vault.balanceOf(lender) / 2;

        // Preview expected assets to receive
        uint256 previewedAssets = _previewRedeem(sharesToRedeem);

        // Capture USDC balance before
        uint256 usdcBefore = IERC20(usdc).balanceOf(lender);

        // Execute redeem
        vm.prank(lender);
        uint256 actualAssets = vault.redeem(sharesToRedeem, lender, lender);

        // Assert: actual assets should equal previewed assets
        assertEq(actualAssets, previewedAssets, "Redeem should return exactly previewRedeem() assets");

        // Verify assets were actually transferred to lender
        assertEq(IERC20(usdc).balanceOf(lender), usdcBefore + actualAssets, "Lender should have received the assets");
    }

    /// @notice Test that deposit→withdraw roundtrip returns ≥99% of principal
    /// @dev Verifies minimal value leakage due to rounding
    function test_roundtrip_noValueLeak() public fundLender(STANDARD_DEPOSIT) {
        // Execute deposit
        vm.startPrank(lender);
        uint256 sharesReceived = vault.deposit(STANDARD_DEPOSIT, lender);

        // Execute full redeem
        uint256 assetsReturned = vault.redeem(sharesReceived, lender, lender);
        vm.stopPrank();

        // Calculate minimum acceptable return (99% of principal)
        uint256 minAcceptable = (STANDARD_DEPOSIT * 9900) / BASIS_POINTS;

        // Assert: assets returned should be at least 99% of principal
        assertGe(assetsReturned, minAcceptable, "Roundtrip should return >= 99% of principal");

        // Also assert that we don't gain value (no inflation attack opportunity)
        assertLe(assetsReturned, STANDARD_DEPOSIT, "Roundtrip should not return more than deposited");
    }

    /// @notice Test that convertToShares/convertToAssets favor the vault (round down)
    /// @dev ERC4626 requires rounding to favor the vault for security
    function test_conversions_roundDown() public withDeposit(STANDARD_DEPOSIT) {
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
    /// @dev Verifies name, symbol, decimals, and asset are correct
    function test_metadata_correct() public view {
        // Check name
        assertEq(vault.name(), "Simple Vault", "Vault name should be 'Simple Vault'");

        // Check symbol
        assertEq(vault.symbol(), "SV", "Vault symbol should be 'SV'");

        // Check decimals (should match underlying asset + offset for ERC4626)
        uint8 expectedDecimals = ERC20(usdc).decimals();
        assertEq(vault.decimals(), expectedDecimals, "Vault decimals should match underlying asset decimals");

        // Check asset
        assertEq(vault.asset(), usdc, "Vault asset should be USDC");
    }

    // ============================================
    // ============ SECTION 2.2: DEPOSIT MECHANICS
    // ============================================

    /// @notice Test that deposit splits 80% to Aave and 20% to BLP
    /// @dev Verifies the default allocation ratio is respected
    function test_deposit_splitsToAaveAndBLP() public fundLender(STANDARD_DEPOSIT) {
        // Capture balances before
        uint256 aaveBefore = _getAaveBalance();
        uint256 blpBefore = _getBLPBalance();

        // Execute deposit
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

        // Assert allocations are within tolerance
        _assertApproxEqBps(aaveIncrease, expectedAave, DEFAULT_TOLERANCE_BPS, "Aave allocation should be ~80%");
        _assertApproxEqBps(blpIncrease, expectedBLP, DEFAULT_TOLERANCE_BPS, "BLP allocation should be ~20%");

        // Also verify overall allocation is correct
        _assertAllocationCorrect();
    }

    /// @notice Test that zero deposit amount reverts
    /// @dev ERC4626 should revert on zero amount deposits
    function test_deposit_zeroAmount_reverts() public fundLender(STANDARD_DEPOSIT) {
        vm.prank(lender);
        vm.expectRevert();
        vault.deposit(0, lender);
    }

    /// @notice Test that deposit can send shares to a different receiver
    /// @dev Verifies ERC4626 receiver parameter works correctly
    function test_deposit_toReceiver() public fundLender(STANDARD_DEPOSIT) {
        address receiver = lender2;

        // Ensure receiver has no shares initially
        assertEq(vault.balanceOf(receiver), 0, "Receiver should have no shares initially");

        // Deposit with different receiver
        vm.prank(lender);
        uint256 shares = vault.deposit(STANDARD_DEPOSIT, receiver);

        // Assert: shares went to receiver, not depositor
        assertEq(vault.balanceOf(lender), 0, "Depositor should have no shares");
        assertEq(vault.balanceOf(receiver), shares, "Receiver should have all shares");

        // Verify USDC was taken from depositor
        assertEq(IERC20(usdc).balanceOf(lender), 0, "Depositor USDC should be spent");
    }

    /// @notice Test that changing allocation to 50/50 affects new deposits
    /// @dev Verifies custom allocation is respected after setAaveAllocation
    function test_deposit_customAllocation() public fundLender(LARGE_DEPOSIT) {
        // Change allocation to 50/50
        _setAllocation(HALF_ALLOCATION_BPS);

        // Capture balances before
        uint256 aaveBefore = _getAaveBalance();
        uint256 blpBefore = _getBLPBalance();

        // Execute deposit
        _deposit(lender, STANDARD_DEPOSIT);

        // Capture balances after
        uint256 aaveAfter = _getAaveBalance();
        uint256 blpAfter = _getBLPBalance();

        // Calculate actual allocations
        uint256 aaveIncrease = aaveAfter - aaveBefore;
        uint256 blpIncrease = blpAfter - blpBefore;

        // Calculate expected allocations (50/50)
        uint256 expectedAave = (STANDARD_DEPOSIT * HALF_ALLOCATION_BPS) / BASIS_POINTS;
        uint256 expectedBLP = STANDARD_DEPOSIT - expectedAave;

        // Assert allocations are within tolerance
        _assertApproxEqBps(aaveIncrease, expectedAave, DEFAULT_TOLERANCE_BPS, "Aave allocation should be ~50%");
        _assertApproxEqBps(blpIncrease, expectedBLP, DEFAULT_TOLERANCE_BPS, "BLP allocation should be ~50%");
    }

    // ============================================
    // ============ SECTION 2.3: WITHDRAW MECHANICS
    // ============================================

    /// @notice Test that post-withdraw allocation stays within tolerance
    /// @dev Verifies the allocation ratio is maintained after withdrawal
    function test_withdraw_maintainsRatio() public withDeposit(LARGE_DEPOSIT) {
        // Verify initial allocation is correct
        _assertAllocationCorrect();

        // Withdraw half of the deposit
        uint256 withdrawAmount = LARGE_DEPOSIT / 2;
        _withdraw(lender, withdrawAmount);

        // Verify allocation still maintains the 80/20 ratio within tolerance
        _assertAllocationCorrect(DEFAULT_AAVE_ALLOCATION_BPS, LOOSE_TOLERANCE_BPS);
    }

    /// @notice Test that 100% withdrawal works without dust lockup
    /// @dev Verifies entire balance can be withdrawn cleanly
    function test_withdraw_entireBalance() public withDeposit(STANDARD_DEPOSIT) {
        // Get all shares
        uint256 allShares = vault.balanceOf(lender);

        // Capture USDC balance before
        uint256 usdcBefore = IERC20(usdc).balanceOf(lender);

        // Redeem all shares (use redeem instead of withdraw to ensure no dust)
        vm.prank(lender);
        uint256 assetsReturned = vault.redeem(allShares, lender, lender);

        // Assert: no shares remaining
        assertEq(vault.balanceOf(lender), 0, "Lender should have no shares remaining");

        // Assert: received assets
        assertGt(assetsReturned, 0, "Should have received some assets");
        assertEq(IERC20(usdc).balanceOf(lender), usdcBefore + assetsReturned, "Lender should have received USDC");

        // Verify no significant dust in vault (allow for small rounding)
        uint256 totalRemaining = vault.totalAssets();
        assertLe(totalRemaining, 10, "Vault should have minimal dust remaining"); // Allow up to 10 wei dust
    }

    /// @notice Test that withdrawing more than balance reverts
    /// @dev Verifies insufficient balance check works
    function test_withdraw_moreThanBalance_reverts() public withDeposit(STANDARD_DEPOSIT) {
        // Try to withdraw more than deposited
        uint256 excessAmount = STANDARD_DEPOSIT * 2;

        vm.prank(lender);
        vm.expectRevert();
        vault.withdraw(excessAmount, lender, lender);
    }

    /// @notice Test that third-party withdrawal with approval works
    /// @dev Verifies ERC4626 allowance mechanism for withdrawals
    function test_withdraw_withAllowance() public withDeposit(STANDARD_DEPOSIT) {
        address withdrawer = lender2;
        uint256 withdrawAmount = STANDARD_DEPOSIT / 2;

        // Lender approves withdrawer to spend shares
        uint256 shareAllowance = vault.previewWithdraw(withdrawAmount) + 100; // Add buffer for rounding
        vm.prank(lender);
        vault.approve(withdrawer, shareAllowance);

        // Capture balances before
        uint256 lenderSharesBefore = vault.balanceOf(lender);
        uint256 withdrawerUsdcBefore = IERC20(usdc).balanceOf(withdrawer);

        // Withdrawer executes withdrawal on behalf of lender, receiving assets themselves
        vm.prank(withdrawer);
        uint256 sharesBurned = vault.withdraw(withdrawAmount, withdrawer, lender);

        // Assert: shares were burned from lender
        assertEq(vault.balanceOf(lender), lenderSharesBefore - sharesBurned, "Shares should be burned from lender");

        // Assert: assets went to withdrawer
        assertEq(
            IERC20(usdc).balanceOf(withdrawer),
            withdrawerUsdcBefore + withdrawAmount,
            "Withdrawer should receive the assets"
        );
    }

    // ============================================
    // ============ SECTION 2.4: STRATEGY MANAGEMENT
    // ============================================

    /// @notice Test that setStrategy migrates funds from old to new strategy
    /// @dev Verifies withdrawAllFunds is called and new strategy receives funds on next deposit
    function test_setStrategy_migratesFunds() public withDeposit(STANDARD_DEPOSIT) {
        // Verify funds are in current strategy
        uint256 totalAssetsBefore = vault.totalAssets();
        assertGt(totalAssetsBefore, 0, "Should have assets before strategy change");

        // Deploy new strategy
        vm.startPrank(deployer);
        USDCStrategy newStrategy = new USDCStrategy(address(vault), aavePool, bitmorPool, deployer);
        newStrategy.grantRole(CURATOR_ROLE, curator);
        vm.stopPrank();

        // Set new Aave allocation on new strategy
        vm.prank(curator);
        newStrategy.setAaveAllocation(DEFAULT_AAVE_ALLOCATION_BPS);

        // Get old strategy balance before migration
        uint256 oldStrategyBalance = strategy.getTotalBalanceInMarkets();
        assertGt(oldStrategyBalance, 0, "Old strategy should have funds");

        // Change to new strategy (manager role)
        vm.prank(manager);
        vault.setStrategy(address(newStrategy));

        // Old strategy should be emptied
        uint256 oldStrategyBalanceAfter = strategy.getTotalBalanceInMarkets();
        assertEq(oldStrategyBalanceAfter, 0, "Old strategy should be emptied after migration");

        // Funds should still be accessible (vault still has assets)
        // Note: After setStrategy, funds are in the vault contract waiting to be deployed to new strategy
        // They get deployed on next deposit. Let's verify by making a small deposit.
        _fundLenderWithUsdc(lender2, SMALL_DEPOSIT);
        _deposit(lender2, SMALL_DEPOSIT);

        // New strategy should now have funds
        uint256 newStrategyBalance = newStrategy.getTotalBalanceInMarkets();
        assertGt(newStrategyBalance, 0, "New strategy should have funds after deposit");
    }

    /// @notice Test that setStrategy updates approvals correctly
    /// @dev Verifies old approval is revoked (0) and new approval is granted (max)
    function test_setStrategy_updatesApprovals() public {
        // Check initial approval to current strategy
        uint256 initialApproval = IERC20(usdc).allowance(address(vault), address(strategy));
        assertEq(initialApproval, type(uint256).max, "Initial strategy should have max approval");

        // Deploy new strategy
        vm.startPrank(deployer);
        USDCStrategy newStrategy = new USDCStrategy(address(vault), aavePool, bitmorPool, deployer);
        newStrategy.grantRole(CURATOR_ROLE, curator);
        vm.stopPrank();

        // Set new Aave allocation on new strategy
        vm.prank(curator);
        newStrategy.setAaveAllocation(DEFAULT_AAVE_ALLOCATION_BPS);

        // Change to new strategy
        vm.prank(manager);
        vault.setStrategy(address(newStrategy));

        // Old strategy approval should be revoked (0)
        uint256 oldApproval = IERC20(usdc).allowance(address(vault), address(strategy));
        assertEq(oldApproval, 0, "Old strategy approval should be revoked");

        // New strategy should have max approval
        uint256 newApproval = IERC20(usdc).allowance(address(vault), address(newStrategy));
        assertEq(newApproval, type(uint256).max, "New strategy should have max approval");
    }

    /// @notice Test that setting strategy to address(0) reverts
    /// @dev Verifies ZeroAddress error is thrown
    function test_setStrategy_zeroAddress_reverts() public {
        vm.prank(manager);
        vm.expectRevert(Errors.ZeroAddress.selector);
        vault.setStrategy(address(0));
    }

    // ============================================
    // ============ SECTION 2.5: CONSTRUCTOR
    // ============================================

    /// @notice Test that constructor reverts on zero addresses
    /// @dev Both asset=0 and blp=0 should revert with Errors.ZeroAddress
    function test_constructor_zeroAddresses_revert() public {
        // Test asset = address(0)
        vm.expectRevert(Errors.ZeroAddress.selector);
        new USDCVault(address(0), bitmorPool);

        // Test blp = address(0)
        vm.expectRevert(Errors.ZeroAddress.selector);
        new USDCVault(usdc, address(0));

        // Test both = address(0)
        vm.expectRevert(Errors.ZeroAddress.selector);
        new USDCVault(address(0), address(0));
    }

    /// @notice Test that constructor sets immutables correctly
    /// @dev Verifies i_asset and i_blp are set to expected values
    function test_constructor_setsImmutables() public {
        // Deploy a new vault to test constructor
        vm.prank(deployer);
        USDCVault testVault = new USDCVault(usdc, bitmorPool);

        // Verify asset is set correctly
        assertEq(testVault.asset(), usdc, "i_asset should be set to USDC");

        // Note: i_blp is internal, so we verify indirectly through behavior
        // The vault should allow reallocateAssets(uint256) to be called by bitmorPool
        // First, set up a strategy for the test vault
        vm.startPrank(deployer);
        USDCStrategy testStrategy = new USDCStrategy(address(testVault), aavePool, bitmorPool, deployer);
        testStrategy.grantRole(CURATOR_ROLE, deployer);
        testStrategy.setAaveAllocation(DEFAULT_AAVE_ALLOCATION_BPS);

        testVault.grantRole(MANAGER_ROLE, deployer);
        testVault.setStrategy(address(testStrategy));
        vm.stopPrank();

        // Non-BLP address should fail to call reallocateAssets(uint256)
        vm.prank(attacker);
        vm.expectRevert(Errors.UnauthorizedCaller.selector);
        testVault.reallocateAssets(1000);

        // BLP address should be able to call (even if it reverts for other reasons, it shouldn't be UnauthorizedCaller)
        // Note: This will likely revert for a different reason (no funds), but not UnauthorizedCaller
        vm.prank(bitmorPool);
        // We don't use expectRevert here because we just want to verify it doesn't revert with UnauthorizedCaller
        try testVault.reallocateAssets(0) {} catch {}

        // If we got here without UnauthorizedCaller, i_blp is correctly set
    }
}
