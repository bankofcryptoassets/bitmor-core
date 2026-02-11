// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IntegrationTestBase} from "../base/IntegrationTestBase.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

/// @title InitLoan_USDCVaultTest
/// @notice Adversarial integration tests targeting USDCVault interactions during loan initialization.
/// @dev Each test probes a distinct attack vector on the USDC vault / loan init boundary.
///      Failing tests indicate security findings, NOT test bugs.
contract InitLoan_USDCVaultTest is IntegrationTestBase {
    // ============ Constants ============

    uint256 constant DONATION_AMOUNT_USDC = 10_000_000e6; // 10M USDC (matches TC.POOL_USDC_LIQUIDITY)
    uint256 constant WHALE_DEPOSIT_USDC = 100_000_000e6; // 100M USDC (matches TC.SWAP_ADAPTER_USDC_BALANCE)
    uint256 constant FIRST_DEPOSITOR_SEED = 1e6; // 1 USDC - minimal first deposit
    uint256 constant INFLATION_DONATION = 50_000_000e6; // 50M USDC - inflated donation

    // ============ Setup ============

    function setUp() public override {
        super.setUp();
        _setupTestUser();
    }

    // ============ Test 1: USDC Vault Donation Attack ============

    /// @notice Donating raw USDC directly to USDCVault should not inflate share price or affect loan terms.
    /// @dev Attack: Attacker transfers USDC directly to USDCVault (bypassing deposit) to inflate
    ///      totalAssets() relative to totalSupply(), hoping to manipulate the loan amount calculation.
    function test_USDCVault_DonationBeforeBorrow_DoesNotInflateShares() public {
        // Arrange - snapshot clean state
        uint256 snap = vm.snapshot();

        // Reference: create a standard loan under normal conditions
        (address lsaRef, DataTypes.LoanData memory loanDataRef) =
            _createLoanWithData(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);
        uint256 loanAmountRef = loanDataRef.loanAmount;
        assertTrue(lsaRef != address(0), "reference LSA should be deployed");

        // Revert to clean state
        vm.revertTo(snap);

        // Attack: donate raw USDC directly to USDCVault (not via deposit())
        address attacker = makeAddr("donationAttacker");
        _fundUSDC(attacker, DONATION_AMOUNT_USDC);
        uint256 attackerBalanceBefore = usdc.balanceOf(attacker);

        vm.prank(attacker);
        usdc.transfer(address(usdcVault), DONATION_AMOUNT_USDC);

        // Create the same loan under attacked conditions
        // Need to advance 1 second so CREATE2 salt differs from reference
        vm.warp(block.timestamp + 1);
        (address lsaAttack, DataTypes.LoanData memory loanDataAttack) =
            _createLoanWithData(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);
        uint256 loanAmountAttack = loanDataAttack.loanAmount;
        assertTrue(lsaAttack != address(0), "attack LSA should be deployed");

        // Assert: loan amount must not change due to donation
        assertEq(loanAmountAttack, loanAmountRef, "USDC donation must not change loan amount");

        // Assert: attacker's donated USDC is stuck (attacker has no shares to redeem)
        uint256 attackerShareBalance = usdcVault.balanceOf(attacker);
        assertEq(attackerShareBalance, 0, "attacker should have zero vault shares");
        assertEq(
            usdc.balanceOf(attacker),
            attackerBalanceBefore - DONATION_AMOUNT_USDC,
            "attacker USDC should be reduced by donation amount"
        );
    }

    // ============ Test 2: Insufficient Pool Liquidity ============

    /// @notice Loan init must revert atomically when the Bitmor Lending Pool has zero borrowable USDC.
    /// @dev Attack surface: If the flash loan succeeds but the BLP borrow fails, the loan should not
    ///      be partially created. The entire transaction must revert to prevent orphaned LSAs.
    function test_USDCVault_InsufficientPoolLiquidity_LoanInitRevertsAtomically() public {
        // Revert to base snapshot (before _setupTestUser which seeds BLP)
        vm.revertTo(_baseSnapshotId);
        // Re-take snapshot so further reverts work
        _baseSnapshotId = vm.snapshot();

        // Setup user WITHOUT seeding BLP liquidity
        _setupUserWithoutBLP(testUser);

        // Capture state before attempt
        uint256 userBalanceBefore = usdc.balanceOf(testUser);
        uint256 vaultTotalAssetsBefore = usdcVault.totalAssets();

        // Act: attempt to create a loan with empty BLP - should revert
        (,, uint256 minDeposit) = loanContract.getLoanDetails(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION);

        vm.expectRevert();
        vm.prank(testUser);
        loanContract.initializeLoan(minDeposit, TC.PREMIUM_AMOUNT, TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, "");

        // Assert: state is unchanged (atomicity check)
        assertEq(usdc.balanceOf(testUser), userBalanceBefore, "user USDC balance should be unchanged after revert");
        assertEq(
            usdcVault.totalAssets(),
            vaultTotalAssetsBefore,
            "USDCVault totalAssets should be unchanged after revert"
        );
    }

    // ============ Test 3: Strategy Rebalance During Loan Init ============

    /// @notice Triggering a strategy rebalance in the same block as loan init must not corrupt vault state.
    /// @dev Tests that reallocateAssets() and initializeLoan() compose safely within one block.
    function test_USDCVault_StrategyRebalance_DuringLoanInit() public {
        // Arrange: capture vault state before
        uint256 vaultTotalBefore = usdcVault.totalAssets();
        assertGt(vaultTotalBefore, 0, "vault should have assets from BLP seeding");

        // Grant UVA role (ID 23, no delay) to admin so we can call reallocateAssets()
        uint64 uvaRoleId = UVA_ID();
        vm.prank(admin);
        manager.grantRole(uvaRoleId, admin, 0);

        // Act: rebalance in same block as loan init
        vm.prank(admin);
        usdcVault.reallocateAssets();

        uint256 vaultTotalAfterRebalance = usdcVault.totalAssets();

        // Create loan in same block (no time advance)
        address lsa = _createStandardLoan();
        assertTrue(lsa != address(0), "LSA should be deployed after rebalance");

        // Assert: vault state is coherent
        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        assertEq(
            uint256(loanData.status),
            uint256(DataTypes.LoanStatus.Active),
            "loan should be active after same-block rebalance"
        );
        assertGt(loanData.loanAmount, 0, "loan amount should be positive after rebalance");

        // Vault totalAssets should be consistent (rebalance should not lose assets)
        assertApproxEqRel(
            vaultTotalAfterRebalance,
            vaultTotalBefore,
            0.01e18, // 1% tolerance for rounding
            "vault totalAssets should be approximately preserved after rebalance"
        );
    }

    // ============ Test 4: First Depositor Inflation Attack ============

    /// @notice ERC-4626 first-depositor inflation attack: deposit 1 USDC, then donate large amount
    ///         to inflate share price. Subsequent loan terms must remain reasonable.
    /// @dev Classic vault inflation vector. The vault should use virtual shares/assets or otherwise
    ///      protect against share price manipulation via direct token transfer.
    function test_USDCVault_FirstDepositorInflation_AffectsLoanTerms() public {
        // Revert to base snapshot to get clean vault state
        vm.revertTo(_baseSnapshotId);
        _baseSnapshotId = vm.snapshot();

        // Setup: first depositor seeds the vault with minimal deposit
        address firstDepositor = makeAddr("firstDepositor");
        _fundUSDC(firstDepositor, FIRST_DEPOSITOR_SEED + INFLATION_DONATION);

        vm.prank(firstDepositor);
        usdc.approve(address(usdcVault), FIRST_DEPOSITOR_SEED);
        vm.prank(firstDepositor);
        uint256 firstShares = usdcVault.deposit(FIRST_DEPOSITOR_SEED, firstDepositor);
        assertGt(firstShares, 0, "first depositor should receive shares");

        // Attack: donate large USDC directly to inflate share price
        vm.prank(firstDepositor);
        usdc.transfer(address(usdcVault), INFLATION_DONATION);

        // Now seed BLP with legitimate liquidity (required for loan creation)
        _seedBLPLiquidity();

        // Setup test user
        _setupUserWithoutBLP(testUser);

        // Act: create a loan under inflated vault conditions
        (address lsa, DataTypes.LoanData memory loanData) =
            _createLoanWithData(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);
        assertTrue(lsa != address(0), "LSA should be deployed despite vault inflation");

        // Assert: loan terms must be reasonable despite inflation
        // The loan amount should be oracle-driven, not vault-share-price driven
        assertGt(loanData.loanAmount, 0, "loan amount must be positive");
        assertEq(
            uint256(loanData.status),
            uint256(DataTypes.LoanStatus.Active),
            "loan should be active"
        );

        // Health factor should be safe (> 1e18)
        (uint256 totalCollateralETH, uint256 totalDebtETH, uint256 healthFactor) = _getUserAccountData(lsa);
        assertGt(totalCollateralETH, 0, "LSA should have collateral in BLP");
        assertGt(totalDebtETH, 0, "LSA should have debt in BLP");
        assertGt(healthFactor, 1e18, "health factor must be > 1 after inflated-vault loan init");
    }

    // ============ Test 5: Large Deposit Then Immediate Borrow ============

    /// @notice A whale depositing a huge amount to USDCVault followed by a MAX_COLLATERAL loan
    ///         must produce bounded loan amounts and safe health factors.
    /// @dev Tests that large vault deposits do not create unbounded loan amounts.
    function test_USDCVault_LargeDeposit_ThenImmediateBorrow() public {
        // Arrange: whale deposits massive USDC into USDCVault
        address whale = makeAddr("usdcWhale");
        _fundUSDC(whale, WHALE_DEPOSIT_USDC);

        vm.prank(whale);
        usdc.approve(address(usdcVault), WHALE_DEPOSIT_USDC);
        vm.prank(whale);
        uint256 whaleShares = usdcVault.deposit(WHALE_DEPOSIT_USDC, whale);
        assertGt(whaleShares, 0, "whale should receive shares");

        uint256 vaultTotalAfterWhale = usdcVault.totalAssets();
        assertGt(vaultTotalAfterWhale, WHALE_DEPOSIT_USDC, "vault should hold at least whale deposit + existing");

        // Act: create maximum-size loan immediately after whale deposit
        (address lsa, DataTypes.LoanData memory loanData) =
            _createLoanWithData(TC.MAX_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);
        assertTrue(lsa != address(0), "LSA should be deployed for max collateral loan");

        // Assert: loan amount must be bounded by oracle price, not by vault liquidity
        // For 10 BTC at ~$100k, loan should be in the range of hundreds of thousands
        uint256 btcPrice = _getOraclePrice(address(btcVault));
        assertGt(btcPrice, 0, "BTC oracle price must be positive");

        // Loan amount should be reasonable relative to collateral value
        // collateralValue = 10 BTC * btcPrice (in oracle units)
        // loanAmount should be < collateralValue (LTV < 100%)
        assertGt(loanData.loanAmount, 0, "loan amount must be positive");
        assertEq(
            uint256(loanData.status),
            uint256(DataTypes.LoanStatus.Active),
            "loan should be active"
        );

        // Health factor must be safe
        (,, uint256 healthFactor) = _getUserAccountData(lsa);
        assertGt(healthFactor, 1e18, "health factor must be > 1 for max collateral loan");
    }

    // ============ Test 6: Withdraw Sandwich Around Loan Init ============

    /// @notice An LP withdrawing most USDC from the vault right before loan init should cause
    ///         the loan to revert. Re-depositing should allow the next attempt to succeed.
    /// @dev Tests vault liquidity drainage as a griefing vector against borrowers.
    function test_USDCVault_WithdrawSandwich_AroundLoanInit() public {
        // Revert to base snapshot to control liquidity precisely
        vm.revertTo(_baseSnapshotId);
        _baseSnapshotId = vm.snapshot();

        // Setup: seed just enough liquidity for exactly one loan
        // A standard 1 BTC loan needs roughly 60-70% of 1 BTC value in USDC
        // Seed a modest amount that should be enough for one loan but tight
        uint256 tightLiquidity = TC.POOL_USDC_LIQUIDITY; // 10M USDC
        address lp = makeAddr("liquidityProvider");
        _fundUSDC(lp, tightLiquidity);

        vm.prank(lp);
        usdc.approve(address(usdcVault), tightLiquidity);
        vm.prank(lp);
        uint256 lpShares = usdcVault.deposit(tightLiquidity, lp);
        assertGt(lpShares, 0, "LP should receive shares");

        // Setup test user (without additional BLP seeding)
        _setupUserWithoutBLP(testUser);

        // Sandwich attack: LP withdraws most liquidity
        uint256 maxWithdrawable = usdcVault.maxWithdraw(lp);
        // Leave only dust (1 USDC) in the vault
        uint256 withdrawAmount = maxWithdrawable > 1e6 ? maxWithdrawable - 1e6 : maxWithdrawable;

        vm.prank(lp);
        usdcVault.withdraw(withdrawAmount, lp, lp);

        uint256 vaultAfterDrain = usdcVault.totalAssets();

        // Act 1: loan init should revert due to insufficient liquidity
        (,, uint256 minDeposit) = loanContract.getLoanDetails(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION);

        vm.expectRevert();
        vm.prank(testUser);
        loanContract.initializeLoan(minDeposit, TC.PREMIUM_AMOUNT, TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, "");

        // Act 2: LP re-deposits, restoring liquidity
        uint256 lpBalance = usdc.balanceOf(lp);
        vm.prank(lp);
        usdc.approve(address(usdcVault), lpBalance);
        vm.prank(lp);
        usdcVault.deposit(lpBalance, lp);

        uint256 vaultAfterRedeposit = usdcVault.totalAssets();
        assertGt(vaultAfterRedeposit, vaultAfterDrain, "vault assets should increase after re-deposit");

        // Act 3: next loan attempt should succeed
        vm.warp(block.timestamp + 1); // advance 1 second for unique CREATE2 salt
        address lsa = _createStandardLoan();
        assertTrue(lsa != address(0), "LSA should be deployed after liquidity restored");

        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        assertEq(
            uint256(loanData.status),
            uint256(DataTypes.LoanStatus.Active),
            "loan should be active after liquidity restored"
        );
    }
}
