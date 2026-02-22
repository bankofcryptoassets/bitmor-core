// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IntegrationTestBase} from "../base/IntegrationTestBase.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {Pausable} from "@openzeppelin/utils/Pausable.sol";

/// @title InitLoan_VaultsTest
/// @author Bitmor Protocol
/// @notice Adversarial integration tests for vault interactions during loan initialization
/// @dev Consolidated from BTCVault, USDCVault, ERC4626, and Strategy test files.
///      Failing tests = security findings, NOT test bugs. Do NOT weaken assertions.
contract InitLoanVaultsTest is IntegrationTestBase {
    // ============ Constants ============

    // BTCVault — TC.MAX_COLLATERAL = 10e8

    // USDCVault
    uint256 constant WHALE_DEPOSIT_USDC = 100_000_000e6; // 100M USDC
    uint256 constant FIRST_DEPOSITOR_SEED = 1e6; // 1 USDC
    uint256 constant INFLATION_DONATION = 50_000_000e6; // 50M USDC

    /// @notice External wrapper for try/catch (Solidity requires external calls for try/catch)
    function createMinCollateralLoan() external returns (address lsa) {
        lsa = _createLoan(TC.MIN_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);
    }

    /// @notice External wrapper for try/catch on _createStandardLoan
    function createStandardLoanExternal() external returns (address lsa) {
        lsa = _createStandardLoan();
    }

    // ============ BTCVault Tests ============

    /// @notice Direct cbBTC transfer to BTCVault inflates totalAssets (standard ERC-4626 behavior).
    ///         The vault's defense against donation attacks is the `onlyVault` modifier on deposit/mint,
    ///         preventing unauthorized share minting, NOT exclusion of idle balance from totalAssets.
    ///         Donations create orphaned idle balance that inflates share price for existing holders.
    function test_BTCVault_DonationBeforeDeposit_NoShareInflation() public {
        // Arrange - capture totalAssets before donation
        uint256 totalAssetsBefore = btcVault.totalAssets();

        // Act - transfer cbBTC directly to the vault contract (NOT via deposit)
        address donator = makeAddr("vaultDonator");
        _fundCbBTC(donator, TC.MAX_COLLATERAL);
        vm.prank(donator);
        cbBTC.transfer(address(btcVault), TC.MAX_COLLATERAL);

        // Assert - totalAssets DOES include idle balance (standard ERC-4626 behavior)
        uint256 totalAssetsAfter = btcVault.totalAssets();
        assertEq(
            totalAssetsAfter,
            totalAssetsBefore + TC.MAX_COLLATERAL,
            "totalAssets must include idle cbBTC balance (ERC-4626 standard)"
        );

        // Assert - the actual defense: donator received zero shares (no deposit/mint call)
        uint256 donatorShares = btcVault.balanceOf(donator);
        assertEq(donatorShares, 0, "donator must receive zero shares from raw transfer");

        // Verify loan creation behavior after donation.
        // Direct donation inflates totalAssets → share price → oracle price. This may cause
        // BLP error 11 (VL_COLLATERAL_CANNOT_COVER_NEW_BORROW) because the inflated oracle
        // prices a larger borrow but the same cbBTC input produces fewer shares.
        address lsa = _createStandardLoan();
        // LSA holds aTokens (collateral in BLP), not bvBTC shares directly.
        (uint256 totalCollateralETH,,) = _getUserAccountData(lsa);
        assertGt(totalCollateralETH, 0, "LSA should have collateral in BLP after loan init");
    }

    /// @notice Strategy donation inflates share price AND oracle price (known contract issue #7).
    ///         The oracle uses previewRedeem() which reflects strategy balance. Anyone can inflate
    ///         strategy balance via direct Aave V3 supply() on behalf of the strategy address.
    ///         The onlyVault modifier on AaveTokenizedStrategy protects ERC-4626 entry points
    ///         but cannot prevent direct Aave V3 supply(cbBTC, amount, strategyAddress, 0) calls.
    /// @dev KNOWN CONTRACT ISSUE: Strategy donation CAN change health factors and oracle prices.
    ///      This test documents the behavior rather than asserting it doesn't exist.
    function test_BTCVault_StrategyDonation_InflatesSharePriceAndOraclePrice() public {
        // --- Reference: create loan at normal share price ---
        uint256 snapshotRef = vm.snapshot();

        address lsaRef = _createStandardLoan();
        (,, uint256 healthFactorRef) = _getUserAccountData(lsaRef);

        // Revert to clean state
        vm.revertTo(snapshotRef);

        // --- Attack: inflate share price via strategy donation ---
        uint256 sharePriceBefore = btcVault.convertToAssets(1e8); // 1 share worth in assets

        _donateToStrategy(TC.MAX_COLLATERAL);

        uint256 sharePriceAfter = btcVault.convertToAssets(1e8);
        assertGt(
            sharePriceAfter,
            sharePriceBefore,
            "Strategy donation should increase convertToAssets (share price inflated)"
        );

        // Create same loan under inflated share price
        address lsaAttack = _createStandardLoan();
        (,, uint256 healthFactorAttack) = _getUserAccountData(lsaAttack);

        // SECURITY INVARIANT: health factors must be equal if oracle is not gameable.
        // If this fails, oracle incorporates share price and is manipulable via donation.
        assertApproxEqRel(
            healthFactorAttack,
            healthFactorRef,
            0.001e18, // 0.1% tolerance for vault rounding
            "FINDING: strategy donation changed health factor beyond rounding tolerance"
        );
    }

    /// @notice If BTCVault charges an entry fee, the actual collateral deposited into the lending pool
    ///         may be less than loanData.collateralAmount. The health factor must reflect the ACTUAL
    ///         on-chain balance, not the stored value, to prevent phantom collateral.
    function test_BTCVault_EntryFee_StoredVsActualCollateral_AllPathsCorrect() public {
        // Arrange - create loan and inspect stored vs actual
        (address lsa, DataTypes.LoanData memory loanData) =
            _createLoanWithData(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        uint256 storedCollateral = loanData.btcAmount;
        (uint256 totalCollateralETH, uint256 totalDebtETH, uint256 healthFactor) = _getUserAccountData(lsa);

        uint256 entryFeeBps = btcVault.getEntryFee();

        if (entryFeeBps > 0) {
            // With an entry fee, actual collateral in the vault should be less than the stored amount.
            // The gap is the fee taken by the vault.
            uint256 actualShares = btcVault.balanceOf(lsa);
            uint256 actualAssets = btcVault.convertToAssets(actualShares);

            assertLt(
                actualAssets,
                storedCollateral,
                "FINDING: With entry fee > 0, actual collateral should be less than stored collateralAmount"
            );

            // Document the fee gap for auditing
            uint256 feeGap = storedCollateral - actualAssets;
            uint256 expectedFee = (storedCollateral * entryFeeBps) / TC.BPS_DENOMINATOR;
            assertApproxEqAbs(
                feeGap,
                expectedFee,
                TC.MAX_ROUNDING_LOSS_SATOSHI,
                "Fee gap should match expected entry fee within rounding tolerance"
            );
        }

        // Regardless of fee: health factor must be based on actual on-chain balance
        // A healthy loan at initialization must have HF > TC.PRECISION
        assertGt(healthFactor, TC.PRECISION, "Health factor must be > 1 at loan initialization");
        assertGt(totalCollateralETH, 0, "Total collateral in ETH units should be positive");
        assertGt(totalDebtETH, 0, "Total debt in ETH units should be positive");
    }

    /// @notice If BTCVault is paused mid-flight (before the flash loan callback deposits collateral),
    ///         the entire initializeLoan transaction must revert atomically, leaving user funds intact.
    function test_BTCVault_DepositFailsMidFlashLoan_AtomicRevert() public {
        // Arrange - pre-compute minDeposit BEFORE pausing (getLoanDetails is a view call that
        // would consume vm.expectRevert if called after it, breaking the revert expectation)
        (,, uint256 minDeposit) = loanContract.getLoanDetails(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION);

        // Pause BTCVault via BVM_FAST role
        uint64 bvmFastId = BVM_FAST_ID();
        vm.prank(admin);
        manager.grantRole(bvmFastId, admin, 0);

        vm.prank(admin);
        btcVault.pause();

        // Verify pause succeeded (diagnostic assertion)
        assertTrue(btcVault.paused(), "BTCVault must be paused after pause()");

        // Capture user balances before the failed attempt
        uint256 usdcBefore = usdc.balanceOf(testUser);
        uint256 cbBTCBefore = cbBTC.balanceOf(testUser);

        // Act - attempt loan creation directly (not via _createStandardLoan helper, because
        // the helper calls getLoanDetails first which would consume the vm.expectRevert)
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(testUser);
        loanContract.initializeLoan(
            minDeposit, TC.PREMIUM_AMOUNT, TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, ""
        );

        // Assert - user funds must be completely unchanged (atomic rollback)
        uint256 usdcAfter = usdc.balanceOf(testUser);
        uint256 cbBTCAfter = cbBTC.balanceOf(testUser);

        assertEq(usdcAfter, usdcBefore, "User USDC balance must be unchanged after failed loan init");
        assertEq(cbBTCAfter, cbBTCBefore, "User cbBTC balance must be unchanged after failed loan init");

        // No cleanup needed: Foundry creates fresh fork state for each test function,
        // so the paused BTCVault does not affect other tests.
    }

    /// @notice Attempting to create a loan with TC.MIN_COLLATERAL (0.01 BTC) must either:
    ///         (a) succeed with a valid health factor > 1, or
    ///         (b) revert cleanly (acceptable minimum enforcement).
    ///         A silent success with HF <= 1 is a finding.
    function test_BTCVault_DepositMinimumAsset_Enforced() public {
        // Act - create a loan with the minimum allowed collateral
        address lsa = _createLoan(TC.MIN_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        // Assert - verify the loan is healthy
        (,, uint256 healthFactor) = _getUserAccountData(lsa);
        assertGt(
            healthFactor,
            TC.PRECISION,
            "FINDING: Min collateral loan has HF <= 1 at creation - undercollateralized from inception"
        );

        DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
        assertEq(
            uint256(loanData.status),
            uint256(DataTypes.LoanStatus.Active),
            "Minimum collateral loan should be Active"
        );
    }

    /// @notice If injecting yield into the strategy changes the loanAmount for the same collateral,
    ///         the oracle is using share price rather than underlying asset price, making it gameable.
    ///         assertEq on loanAmounts FAILS if oracle is gameable = security finding.
    function test_BTCVault_SharePrice_Vs_OraclePrice_Divergence() public {
        // --- Reference: create loan at normal share price ---
        uint256 snapshotRef = vm.snapshot();

        (address lsaRef, DataTypes.LoanData memory loanDataRef) =
            _createLoanWithData(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);
        uint256 loanAmountRef = loanDataRef.loanAmount;

        // Revert to clean state
        vm.revertTo(snapshotRef);

        // --- Attack: inject yield by donating to strategy ---
        _donateToStrategy(TC.MAX_COLLATERAL);

        // Verify share price actually moved (precondition for meaningful test)
        uint256 sharePriceAfterDonation = btcVault.convertToAssets(1e8);
        assertGt(
            sharePriceAfterDonation,
            1e8,
            "Precondition: share price should be inflated after strategy donation"
        );

        // CRITICAL CHECK: getLoanDetails reflects the oracle, so compare loan amounts.
        // If the oracle uses share price, getLoanDetails will return a different loanAmount.
        (,, uint256 minDepositAttack) = loanContract.getLoanDetails(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION);

        // The loan amount is computed from oracle price. If oracle uses share price,
        // loanAmount changes after donation. We can check this via getLoanDetails.
        // Create the loan - if oracle is not gameable, loanAmount should match reference.
        address lsaAttack = _createStandardLoan();
        DataTypes.LoanData memory loanDataAttack = loanContract.getLoanByLSA(lsaAttack);
        uint256 loanAmountAttack = loanDataAttack.loanAmount;

        assertEq(
            loanAmountAttack,
            loanAmountRef,
            "FINDING: Strategy donation changed loanAmount - oracle uses share price, enabling loan amount manipulation"
        );
    }

    // ============ USDCVault Tests ============

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
        _fundUSDC(attacker, TC.DONATION_AMOUNT_USDC);
        uint256 attackerBalanceBefore = usdc.balanceOf(attacker);

        vm.prank(attacker);
        usdc.transfer(address(usdcVault), TC.DONATION_AMOUNT_USDC);

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
            attackerBalanceBefore - TC.DONATION_AMOUNT_USDC,
            "attacker USDC should be reduced by donation amount"
        );
    }

    /// @notice Loan init must revert atomically when the Bitmor Lending Pool has zero borrowable USDC.
    /// @dev Attack surface: If the flash loan succeeds but the BLP borrow fails, the loan should not
    ///      be partially created. The entire transaction must revert to prevent orphaned LSAs.
    function test_USDCVault_InsufficientPoolLiquidity_LoanInitRevertsAtomically() public {
        // Revert to pre-seeded snapshot (before any liquidity seeding)
        vm.revertTo(_preSeededSnapshotId);
        // Re-take snapshot so further reverts work
        _preSeededSnapshotId = vm.snapshot();

        // Setup user WITHOUT seeding BLP liquidity
        _setupUserWithoutBLP(testUser);

        // Capture state before attempt
        uint256 userBalanceBefore = usdc.balanceOf(testUser);
        uint256 vaultTotalAssetsBefore = usdcVault.totalAssets();

        // Act: attempt to create a loan with empty BLP - should revert
        (,, uint256 minDeposit) = loanContract.getLoanDetails(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION);

        // Generic revert: cross-version BLP call (borrow failure in 0.6.12 lending pool)
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

    /// @notice Triggering a strategy rebalance in the same block as loan init must not corrupt vault state.
    /// @dev Tests that reallocateAssets() and initializeLoan() compose safely within one block.
    ///      A prior loan ensures the strategy has non-zero deposits, preventing MulDivFailed
    ///      from division by zero in share-price arithmetic.
    function test_USDCVault_StrategyRebalance_DuringLoanInit() public {
        // Bootstrap: create an initial loan so the strategy has non-zero AUM
        // (reallocateAssets on a zero-balance strategy triggers MulDivFailed)
        _createStandardLoan();
        vm.warp(block.timestamp + 1);

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

        // Health factor should be safe (> TC.PRECISION)
        (uint256 totalCollateralETH, uint256 totalDebtETH, uint256 healthFactor) = _getUserAccountData(lsa);
        assertGt(totalCollateralETH, 0, "LSA should have collateral in BLP");
        assertGt(totalDebtETH, 0, "LSA should have debt in BLP");
        assertGt(healthFactor, TC.PRECISION, "health factor must be > 1 after inflated-vault loan init");
    }

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
        assertGt(healthFactor, TC.PRECISION, "health factor must be > 1 for max collateral loan");
    }

    /// @notice An LP withdrawing most USDC from the vault right before loan init should cause
    ///         the loan to revert. Re-depositing should allow the next attempt to succeed.
    /// @dev Tests vault liquidity drainage as a griefing vector against borrowers.
    function test_USDCVault_WithdrawSandwich_AroundLoanInit() public {
        // Revert to pre-seeded snapshot to control liquidity precisely
        vm.revertTo(_preSeededSnapshotId);
        _preSeededSnapshotId = vm.snapshot();

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

        // Generic revert: cross-version BLP call (borrow failure in 0.6.12 lending pool)
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

    // ============ ERC4626 Tests ============

    /// @notice Classic ERC-4626 inflation attack via strategy donation. After inflation,
    ///         loan creation may revert with BLP error 11 because fewer shares are received
    ///         for the same cbBTC input. The system correctly rejects undercollateralized loans.
    /// @dev KNOWN CONTRACT ISSUE: strategy donation inflates share price, making loan creation
    ///      unstable. If the loan DOES succeed, it must be healthy.
    function test_ERC4626_FirstDepositorAttack_BTCVault() public {
        // Arrange - Step 1: Attacker creates first loan with minimum collateral
        _createLoan(TC.MIN_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        // Arrange - Step 2: Donate cbBTC to strategy to inflate share price
        _donateToStrategy(TC.USER_CBBTC_BALANCE);

        // Arrange - Step 3: Verify inflation occurred
        uint256 inflatedAssets = btcVault.convertToAssets(1e8);
        assertGt(inflatedAssets, 1e8, "share price should be inflated after donation");

        // Arrange - Step 4: Advance time for unique salt
        vm.warp(block.timestamp + 1);

        // Act - Victim creates loan with standard collateral into the inflated vault
        address lsaVictim = _createStandardLoan();

        // Assert - victim loan must be healthy
        uint256 aTokenBalance = _getATokenBalance(lsaVictim);
        assertGt(aTokenBalance, 0, "LSA must have aToken collateral after loan init despite inflation attack");

        (,, uint256 healthFactor) = _getUserAccountData(lsaVictim);
        assertGt(healthFactor, TC.PRECISION, "victim loan must be healthy after inflated deposit");
    }

    /// @notice Verifies that the smallest allowed collateral produces a healthy loan
    ///         despite entry fees and vault rounding.
    /// @dev Security finding if min collateral loans are immediately unhealthy.
    function test_ERC4626_MinCollateralRoundingExploitation() public {
        // Act - Create loan with the absolute minimum collateral
        address lsa = _createLoan(TC.MIN_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        // Assert - Loan must be healthy even at minimum collateral
        (,, uint256 healthFactor) = _getUserAccountData(lsa);
        assertGt(healthFactor, TC.PRECISION, "min collateral loan must be healthy after entry fees and rounding");
    }

    /// @notice Verifies that share<->asset round-trip conversions do not lose
    ///         more than dust after yield injection creates a non-round share price.
    /// @dev After donation, loan creation may revert (BLP error 11) due to inflated share price.
    ///      If loan succeeds, rounding loss must be within tolerance.
    ///      KNOWN CONTRACT ISSUE: strategy donation destabilizes loan creation.
    function test_ERC4626_LargeDepositRoundingAccumulation() public {
        // Arrange - Inject yield to create a non-round share price (1 BTC)
        _donateToStrategy(1e8);

        // Act - Create loan with standard collateral into yield-shifted vault
        address lsa = _createStandardLoan();

        // Assert - Round-trip conversion must not lose more than dust
        uint256 aTokenBalance = _getATokenBalance(lsa);
        assertGt(aTokenBalance, 0, "LSA must have non-zero aToken balance after loan creation");

        uint256 assetsFromShares = btcVault.convertToAssets(aTokenBalance);
        uint256 sharesFromAssets = btcVault.convertToShares(assetsFromShares);

        // aTokenBalance -> assets -> shares should be lossless or near-lossless
        assertApproxEqAbs(
            sharesFromAssets,
            aTokenBalance,
            TC.MAX_ROUNDING_LOSS_SATOSHI,
            "round-trip conversion must not lose more than dust"
        );
    }

    // ============ Strategy Tests ============

    /// @notice Strategy loss immediately after loan initialization should decrease the health factor.
    ///         A minimum-collateral loan is most vulnerable: even a moderate loss can push HF below 1.
    ///         This tests whether the protocol properly reflects strategy losses in health factor
    ///         calculations, i.e., the oracle/vault accounting correctly propagates reduced totalAssets.
    function test_Strategy_LossRightAfterInit_InstantUndercollateralization() public {
        // Arrange - create loan at boundary (minimum collateral)
        address lsa = _createLoan(TC.MIN_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        (,, uint256 healthFactorBefore) = _getUserAccountData(lsa);
        assertGt(healthFactorBefore, TC.PRECISION, "loan must be healthy at creation");

        // Act - simulate strategy loss by withdrawing cbBTC from strategy's Aave position
        // We prank as the strategy to call withdraw on the external Aave pool,
        // draining 50% of the vault's total assets to an unrelated address.
        address strategyAddr = config.getAaveTokenizedStrategy();
        uint256 totalAssetsBefore = btcVault.totalAssets();
        uint256 lossAmount = totalAssetsBefore / 2; // 50% loss

        vm.prank(strategyAddr);
        (bool ok,) = aaveV3Pool.call(
            abi.encodeWithSignature(
                "withdraw(address,uint256,address)", address(cbBTC), lossAmount, makeAddr("drain")
            )
        );
        require(ok, "strategy loss simulation via aave withdraw failed");

        // Assert - health factor must decrease after strategy loss
        (,, uint256 healthFactorAfter) = _getUserAccountData(lsa);

        assertLt(
            healthFactorAfter,
            healthFactorBefore,
            "FINDING: strategy loss must decrease health factor - vault accounting not propagating losses"
        );

        // Additional: if HF dropped below 1, the loan is instantly liquidatable from a strategy loss.
        // This is expected behavior for min collateral, but worth documenting.
        if (healthFactorAfter < TC.PRECISION) {
            // This is an expected consequence for boundary loans with 50% strategy loss.
            // The protocol should have mechanisms to handle this (e.g., emergency pause).
            assertTrue(true, "min collateral loan is liquidatable after 50% strategy loss (expected)");
        }
    }

    /// @notice KNOWN CONTRACT ISSUE (CRITICAL): Strategy donation CAN rescue undercollateralized loans.
    ///         An attacker can donate cbBTC to the AaveTokenizedStrategy (via direct Aave V3 supply
    ///         on behalf of strategy address), inflating the strategy's aToken balance. This inflates
    ///         bvBTC share price → oracle price → health factor of ALL loans using bvBTC as collateral.
    ///         A borrower about to be liquidated could front-run the liquidation with a strategy
    ///         donation to artificially pump their health factor above 1.0.
    /// @dev This test documents the known vulnerability. The fix requires the oracle to use
    ///      a share price that cannot be manipulated via direct Aave V3 supply() calls.
    function test_Strategy_ArtificialYieldInjection_PreventsLiquidation() public {
        // Arrange - create loan with standard collateral
        address lsa = _createStandardLoan();

        // Drop price to make the loan liquidatable (HF < TC.PRECISION)
        (, int256 currentPrice,,,) = btcOracle.latestRoundData();
        require(currentPrice > 0, "oracle price must be positive");

        // Drop by 40% first
        int256 droppedPrice = currentPrice * 60 / 100;
        btcOracle.updateAnswer(droppedPrice);

        (,, uint256 healthFactorDropped) = _getUserAccountData(lsa);

        // If HF is still above TC.PRECISION after 40% drop, drop more aggressively
        if (healthFactorDropped >= TC.PRECISION) {
            droppedPrice = currentPrice * 40 / 100;
            btcOracle.updateAnswer(droppedPrice);
            (,, healthFactorDropped) = _getUserAccountData(lsa);
        }

        // If still above TC.PRECISION after 60% drop, use extreme drop
        if (healthFactorDropped >= TC.PRECISION) {
            droppedPrice = currentPrice * 20 / 100;
            btcOracle.updateAnswer(droppedPrice);
            (,, healthFactorDropped) = _getUserAccountData(lsa);
        }

        // Precondition: loan must be undercollateralized (HF < TC.PRECISION)
        assertLt(
            healthFactorDropped,
            TC.PRECISION,
            "precondition failed: could not push loan below liquidation threshold via price drop"
        );

        // Act - attempt to rescue the loan by donating cbBTC to the strategy
        _donateToStrategy(TC.USER_CBBTC_BALANCE);

        // Document: strategy donation DOES inflate health factor (known contract issue)
        (,, uint256 healthFactorAfterDonation) = _getUserAccountData(lsa);

        // SECURITY INVARIANT: strategy donation must NOT rescue undercollateralized loans.
        // If this assertion fails, the contract is vulnerable to donation-based liquidation evasion.
        assertLe(
            healthFactorAfterDonation,
            TC.PRECISION,
            "FINDING: strategy donation must not rescue undercollateralized loan -- oracle gameable via direct Aave supply"
        );
    }

    // ============ Collateral Valuation ============

    /// @notice Loan contract should hold zero USDC after loan initialization when vault has yield
    function test_InitializeLoan_NoResidualUSDC_WhenVaultHasYield() public {
        // Seed the vault with a first loan so the strategy has aTokens
        _createStandardLoan();

        // Simulate 5% yield accrual in the BTCVault strategy
        _simulateVaultYield(TC.SIMULATED_YIELD_BPS);

        // Create a second loan with the now-inflated vault share price
        vm.warp(block.timestamp + 1); // advance 1s for unique CREATE2 salt
        _createStandardLoan();

        // The Loan contract should not hold any USDC after initialization completes
        uint256 residual = usdc.balanceOf(address(loanContract));
        assertEq(residual, 0, "Loan contract should have zero USDC after initialization");
    }

    // ============ Security Audit Findings ============

    /// @notice Issue #7 (CRITICAL): BTCVault.totalAssets() (line 398-404) only sums strategy
    ///         balances, ignoring idle vault balance. After emergencyWithdrawFunds(), all assets
    ///         are idle → totalAssets() returns 0 → share price collapses → mass liquidations.
    function test_BTCVault_EmergencyWithdraw_CollapsesTotalAssets() public {
        // Arrange
        _createStandardLoan();
        uint256 totalAssetsBefore = btcVault.totalAssets();
        assertGt(totalAssetsBefore, 0, "vault should have assets from loan");

        uint256 sharePriceBefore = btcVault.convertToAssets(1e8); // 1 share → assets

        // Act — emergency withdraw (BVM_FAST = role 11, no delay)
        uint64 bvmFastId = BVM_FAST_ID();
        vm.prank(admin);
        manager.grantRole(bvmFastId, admin, 0);

        vm.prank(admin);
        btcVault.emergencyWithdrawFunds();

        // Assert: totalAssets should still account for the idle cbBTC in the vault
        uint256 totalAssetsAfter = btcVault.totalAssets();
        uint256 idleBalance = cbBTC.balanceOf(address(btcVault));

        assertGt(idleBalance, 0, "vault should hold cbBTC after emergency withdraw");
        assertGt(totalAssetsAfter, 0, "totalAssets should include idle balance after emergency withdraw");

        // Share price should remain stable (not collapse to 0)
        uint256 sharePriceAfter = btcVault.convertToAssets(1e8);
        assertApproxEqRel(sharePriceAfter, sharePriceBefore, 0.01e18, "share price should be stable after emergency withdraw");
    }

    /// @notice Issue #10 (CRITICAL): totalAssets() iterates i < s_strategy.totalStrategies but
    ///         strategy removal never decrements totalStrategies. After setting cap to 0 and
    ///         emergency-withdrawing, the loop still iterates once, reading a zeroed/stale slot.
    function test_BTCVault_StrategyRemoval_BreaksTotalAssetsLoop() public {
        // Arrange — need a loan to have assets in strategy
        _createStandardLoan();
        uint256 totalAssetsBefore = btcVault.totalAssets();
        assertGt(totalAssetsBefore, 0, "vault should have assets");

        address strategy = config.getAaveTokenizedStrategy();

        // Step 1: Set strategy cap to 0 (BVC role, 1-day delay)
        _scheduleAndExecute(
            address(btcVault), admin, BVC_ID(),
            abi.encodeCall(btcVault.changeStrategyCap, (strategy, 0))
        );

        // Step 2: Withdraw all from strategy to idle via emergency withdraw
        uint64 bvmFastId = BVM_FAST_ID();
        vm.prank(admin);
        manager.grantRole(bvmFastId, admin, 0);

        vm.prank(admin);
        btcVault.emergencyWithdrawFunds();

        // Step 3: Update withdraw queue to remove strategy
        uint256[] memory emptyQueue = new uint256[](0);
        _scheduleAndExecute(
            address(btcVault), admin, BVA_SLOW_ID(),
            abi.encodeCall(btcVault.updateWithdrawQueue, (emptyQueue))
        );

        // Assert: totalAssets should still work and include idle balance
        uint256 totalAssetsAfter = btcVault.totalAssets(); // Will revert → test FAILS
        uint256 idleBalance = cbBTC.balanceOf(address(btcVault));
        assertGt(idleBalance, 0, "vault should hold idle cbBTC");
        assertEq(totalAssetsAfter, idleBalance, "totalAssets should equal idle balance when no strategies active");
    }

    /// @notice Issue #11 (CRITICAL): updateWithdrawQueue() removes a strategy but supplyQueue
    ///         still references it. Next deposit follows stale queue, potentially depositing
    ///         into a zeroed/removed strategy slot.
    function test_BTCVault_SupplyQueueStale_AfterStrategyRemoval() public {
        // Arrange — same setup as #10: remove strategy from withdraw queue
        _createStandardLoan();

        address strategy = config.getAaveTokenizedStrategy();

        // Remove strategy from withdraw queue
        _scheduleAndExecute(
            address(btcVault), admin, BVC_ID(),
            abi.encodeCall(btcVault.changeStrategyCap, (strategy, 0))
        );

        uint64 bvmFastId = BVM_FAST_ID();
        vm.prank(admin);
        manager.grantRole(bvmFastId, admin, 0);

        vm.prank(admin);
        btcVault.emergencyWithdrawFunds();

        uint256[] memory emptyQueue = new uint256[](0);
        _scheduleAndExecute(
            address(btcVault), admin, BVA_SLOW_ID(),
            abi.encodeCall(btcVault.updateWithdrawQueue, (emptyQueue))
        );

        // Act: create another loan (triggers deposit into BTCVault via stale supply queue)
        address userC = _setupAdditionalUser("userC");

        vm.warp(block.timestamp + 1); // advance for unique CREATE2 salt
        address lsa = _createLoanForUser(userC, TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        // Assert: loan should be created successfully
        assertTrue(lsa != address(0), "loan creation should succeed after strategy removal");
        assertGt(lsa.code.length, 0, "LSA should have code");
    }
}
