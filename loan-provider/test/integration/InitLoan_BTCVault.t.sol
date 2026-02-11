// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IntegrationTestBase} from "../base/IntegrationTestBase.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {AaveTokenizedStrategy} from "@btcVault/TokenizedStrategy/AaveTokenizedStrategy.sol";

/// @title InitLoan_BTCVaultTest
/// @notice Adversarial integration tests probing BTCVault interactions during loan initialization.
///         Failing tests are security findings, NOT test bugs.
contract InitLoan_BTCVaultTest is IntegrationTestBase {
    // ============ Constants ============

    uint256 constant DONATION_AMOUNT_CBBTC = 10e8; // 10 BTC (TC.MAX_COLLATERAL)
    uint256 constant MAX_ROUNDING_LOSS_SATOSHI = 100; // Max acceptable rounding dust
    uint256 constant SHARE_PRICE_IMPACT_TOLERANCE = 0.01e18; // 1%

    // ============ Setup ============

    function setUp() public override {
        super.setUp();
        _setupTestUser();
    }

    // ============ Helpers ============

    /// @notice Donates cbBTC to the AaveTokenizedStrategy by supplying to the external Aave pool
    ///         on behalf of the strategy address, inflating the strategy's aToken balance.
    /// @param amount The amount of cbBTC (8 decimals) to donate
    function _donateToStrategy(uint256 amount) internal {
        address strategyAddr = config.getAaveTokenizedStrategy();
        address donator = makeAddr("donator");
        _fundCbBTC(donator, amount);

        vm.prank(donator);
        cbBTC.approve(aaveV3Pool, amount);

        vm.prank(donator);
        (bool ok,) = aaveV3Pool.call(
            abi.encodeWithSignature(
                "supply(address,uint256,address,uint16)", address(cbBTC), amount, strategyAddr, 0
            )
        );
        require(ok, "strategy donation via Aave supply failed");
    }

    // ============ Test 7: Donation to BTCVault address (not strategy) ============

    /// @notice Direct cbBTC transfer to BTCVault address should NOT inflate totalAssets.
    ///         BTCVault.totalAssets() only counts strategy balances, not loose tokens.
    ///         If totalAssets changes, the vault is vulnerable to donation-based share inflation.
    function test_BTCVault_DonationBeforeDeposit_NoShareInflation() public {
        // Arrange - capture totalAssets before donation
        uint256 totalAssetsBefore = btcVault.totalAssets();

        // Act - transfer cbBTC directly to the vault contract (NOT via deposit)
        address donator = makeAddr("vaultDonator");
        _fundCbBTC(donator, DONATION_AMOUNT_CBBTC);
        vm.prank(donator);
        cbBTC.transfer(address(btcVault), DONATION_AMOUNT_CBBTC);

        // Assert - totalAssets must be unchanged; loose tokens are not counted
        uint256 totalAssetsAfter = btcVault.totalAssets();
        assertEq(
            totalAssetsAfter,
            totalAssetsBefore,
            "FINDING: BTCVault.totalAssets() changed from direct token transfer - donation attack vector"
        );

        // Verify loan creation still works normally after donation
        address lsa = _createStandardLoan();
        uint256 shares = btcVault.balanceOf(lsa);
        assertGt(shares, 0, "LSA should receive BTCVault shares after loan init");
    }

    // ============ Test 8: Strategy donation inflates share price ============

    /// @notice Donating cbBTC to the strategy (via Aave supply on behalf of strategy) inflates
    ///         the share price. If the oracle does not account for this, an attacker can manipulate
    ///         the health factor of newly created loans.
    ///         assertEq on healthFactors FAILS if manipulable = security finding.
    function test_BTCVault_StrategyDonation_InflatesSharePriceAndOraclePrice() public {
        // --- Reference: create loan at normal share price ---
        uint256 snapshotRef = vm.snapshot();

        address lsaRef = _createStandardLoan();
        (,, uint256 healthFactorRef) = _getUserAccountData(lsaRef);
        DataTypes.LoanData memory loanDataRef = loanContract.getLoanByLSA(lsaRef);

        // Revert to clean state
        vm.revertTo(snapshotRef);

        // --- Attack: inflate share price via strategy donation ---
        uint256 sharePriceBefore = btcVault.convertToAssets(1e8); // 1 share worth in assets

        _donateToStrategy(DONATION_AMOUNT_CBBTC);

        uint256 sharePriceAfter = btcVault.convertToAssets(1e8);
        assertGt(
            sharePriceAfter,
            sharePriceBefore,
            "Strategy donation should increase convertToAssets (share price inflated)"
        );

        // Create same loan under inflated share price
        address lsaAttack = _createStandardLoan();
        (,, uint256 healthFactorAttack) = _getUserAccountData(lsaAttack);
        DataTypes.LoanData memory loanDataAttack = loanContract.getLoanByLSA(lsaAttack);

        // CRITICAL ASSERTION: health factors must be equal.
        // If healthFactorAttack != healthFactorRef, the oracle is gameable via share price manipulation.
        assertEq(
            healthFactorAttack,
            healthFactorRef,
            "FINDING: Strategy donation changed health factor - oracle is gameable via share price inflation"
        );
    }

    // ============ Test 9: Entry fee creates stored vs actual collateral gap ============

    /// @notice If BTCVault charges an entry fee, the actual collateral deposited into the lending pool
    ///         may be less than loanData.collateralAmount. The health factor must reflect the ACTUAL
    ///         on-chain balance, not the stored value, to prevent phantom collateral.
    function test_BTCVault_EntryFee_StoredVsActualCollateral_AllPathsCorrect() public {
        // Arrange - create loan and inspect stored vs actual
        (address lsa, DataTypes.LoanData memory loanData) =
            _createLoanWithData(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);

        uint256 storedCollateral = loanData.collateralAmount;
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
                MAX_ROUNDING_LOSS_SATOSHI,
                "Fee gap should match expected entry fee within rounding tolerance"
            );
        }

        // Regardless of fee: health factor must be based on actual on-chain balance
        // A healthy loan at initialization must have HF > 1e18
        assertGt(healthFactor, 1e18, "Health factor must be > 1 at loan initialization");
        assertGt(totalCollateralETH, 0, "Total collateral in ETH units should be positive");
        assertGt(totalDebtETH, 0, "Total debt in ETH units should be positive");
    }

    // ============ Test 10: Paused BTCVault causes atomic flash loan revert ============

    /// @notice If BTCVault is paused mid-flight (before the flash loan callback deposits collateral),
    ///         the entire initializeLoan transaction must revert atomically, leaving user funds intact.
    function test_BTCVault_DepositFailsMidFlashLoan_AtomicRevert() public {
        // Arrange - pause BTCVault via BVM_FAST role
        uint64 bvmFastId = BVM_FAST_ID();
        vm.prank(admin);
        manager.grantRole(bvmFastId, admin, 0);

        vm.prank(admin);
        btcVault.pause();

        // Capture user balances before the failed attempt
        uint256 usdcBefore = usdc.balanceOf(testUser);
        uint256 cbBTCBefore = cbBTC.balanceOf(testUser);

        // Act - attempt loan creation; expect revert due to paused vault
        vm.expectRevert();
        _createStandardLoan();

        // Assert - user funds must be completely unchanged (atomic rollback)
        uint256 usdcAfter = usdc.balanceOf(testUser);
        uint256 cbBTCAfter = cbBTC.balanceOf(testUser);

        assertEq(usdcAfter, usdcBefore, "User USDC balance must be unchanged after failed loan init");
        assertEq(cbBTCAfter, cbBTCBefore, "User cbBTC balance must be unchanged after failed loan init");

        // Cleanup - unpause via BVM_SLOW (delayed operation) so other tests are unaffected
        uint64 bvmSlowId = BVM_SLOW_ID();
        vm.prank(admin);
        manager.grantRole(bvmSlowId, admin, _getDelay_BVM_SLOW());

        _scheduleAndExecute(address(btcVault), admin, bvmSlowId, abi.encodeCall(btcVault.unpause, ()));
    }

    // ============ Test 11: Minimum collateral enforcement ============

    /// @notice Attempting to create a loan with TC.MIN_COLLATERAL (0.01 BTC) must either:
    ///         (a) succeed with a valid health factor > 1, or
    ///         (b) revert cleanly (acceptable minimum enforcement).
    ///         A silent success with HF <= 1 is a finding.
    function test_BTCVault_DepositMinimumAsset_Enforced() public {
        // Act - try creating a loan with the minimum allowed collateral
        try this.createMinCollateralLoan() returns (address lsa) {
            // Success path: verify the loan is healthy
            (,, uint256 healthFactor) = _getUserAccountData(lsa);
            assertGt(
                healthFactor,
                1e18,
                "FINDING: Min collateral loan has HF <= 1 at creation - undercollateralized from inception"
            );

            DataTypes.LoanData memory loanData = loanContract.getLoanByLSA(lsa);
            assertEq(
                uint256(loanData.status),
                uint256(DataTypes.LoanStatus.Active),
                "Minimum collateral loan should be Active"
            );
        } catch {
            // Revert path: acceptable - protocol enforces a minimum.
            // No assertion needed; a clean revert is valid behavior.
        }
    }

    /// @notice External wrapper for try/catch (Solidity requires external calls for try/catch)
    function createMinCollateralLoan() external returns (address lsa) {
        lsa = _createLoan(TC.MIN_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);
    }

    // ============ Test 12: Share price vs oracle price divergence ============

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
        _donateToStrategy(DONATION_AMOUNT_CBBTC);

        // Verify share price actually moved (precondition for meaningful test)
        uint256 sharePriceAfterDonation = btcVault.convertToAssets(1e8);
        assertGt(
            sharePriceAfterDonation,
            1e8,
            "Precondition: share price should be inflated after strategy donation"
        );

        // Create same loan under inflated share price
        (, DataTypes.LoanData memory loanDataAttack) =
            _createLoanWithData(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION, TC.PREMIUM_AMOUNT);
        uint256 loanAmountAttack = loanDataAttack.loanAmount;

        // CRITICAL ASSERTION: loan amounts must be identical for the same collateral.
        // If loanAmountAttack != loanAmountRef, the oracle incorporates share price,
        // meaning an attacker can inflate yield to extract larger loans.
        assertEq(
            loanAmountAttack,
            loanAmountRef,
            "FINDING: Strategy donation changed loanAmount - oracle uses share price, enabling loan amount manipulation"
        );
    }
}
