// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { USDCVaultFuzzTestBase } from "../base/USDCVaultFuzzTestBase.sol";
import { FuzzConstants as FC } from "../helpers/FuzzConstants.sol";
import { USDCVault } from "@bitmor/vaults/usdc-vault/USDCVault.sol";
import { USDCStrategy } from "@bitmor/vaults/usdc-vault/USDCStrategy.sol";
import { Errors } from "@bitmor/libraries/helpers/Errors.sol";
import { IERC20 } from "@openzeppelin/interfaces/IERC20.sol";

/**
 * @title USDCVaultFuzzTest
 * @author Bitmor Protocol
 * @notice Fuzz tests for USDCVault and USDCStrategy (USDC-01 through USDC-40)
 * @dev Tests ERC-4626 compliance, vault-strategy integration, edge cases, and access control.
 *      Uses real `USDCVault` and `USDCStrategy` backed by `MockAaveV3Pool` and `MockBitmorLendingPool`.
 *
 * ## Test Coverage
 *
 * ### ERC-4626 Compliance
 * - USDC-01: Deposit/redeem roundtrip preserves value within slippage
 * - USDC-02: Shares minted proportional to deposit amount
 * - USDC-03: convertToAssets(convertToShares(x)) <= x (no free money)
 * - USDC-04: previewDeposit <= actual deposit shares
 * - USDC-05: previewRedeem <= actual redeem assets
 * - USDC-06: Withdrawal respects maxWithdraw limit
 * - USDC-07: Multiple users can deposit and withdraw independently
 * - USDC-28: Mint-redeem roundtrip preserves value within slippage
 *
 * ### Vault-Strategy Integration
 * - USDC-19: Deposit flows through strategy
 * - USDC-20: Withdraw flows through strategy
 * - USDC-22: totalAssets = strategy.totalAssets() + vault idle balance
 * - USDC-24: setStrategy migrates funds from old strategy markets
 *
 * ### Edge Cases & Access Control
 * - USDC-29: Deposit reverts on zero amount
 * - USDC-30: Deposit reverts when paused
 * - USDC-31: Withdraw reverts when paused
 * - USDC-32: Mint reverts when paused
 * - USDC-33: Redeem reverts when paused
 * - USDC-34: Withdraw reverts when exceeding balance
 * - USDC-35: Strategy supply reverts when caller is not vault
 * - USDC-36: Strategy withdraw reverts when caller is not vault
 * - USDC-37: Strategy supply works at any allocation
 * - USDC-38: Shares never exceed deposit (inflation resistance)
 * - USDC-39: reallocateAssets(uint256) reverts when caller is not BLP
 * - USDC-40: setStrategy reverts on zero address
 *
 * @custom:audit-category ERC-4626 Compliance, Vault-Strategy Integration, Access Control
 */
contract USDCVaultFuzzTest is USDCVaultFuzzTestBase {
    // ============ Constants ============

    /// @dev Generous funding amount for approve-only scenarios
    uint256 internal constant GENEROUS_FUNDING = 100_000e6;

    /// @dev Minimum shares amount for mint fuzz bound
    uint256 internal constant MIN_SHARES = 1;

    /// @dev Maximum shares amount for mint fuzz bound
    uint256 internal constant MAX_SHARES = 1_000e6;

    // ============ Setup ============

    function setUp() public override {
        super.setUp();
    }

    // ══════════════════════════════════════════════════════════════════
    //                    ERC-4626 COMPLIANCE
    // ══════════════════════════════════════════════════════════════════

    /**
     * @notice Verifies deposit/redeem roundtrip preserves value within slippage
     * @dev Deposits into real vault with strategy, then redeems all shares.
     *      Roundtrip loss from share rounding must stay within `FC.MAX_ROUNDTRIP_SLIPPAGE`.
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property USDC-01: Deposit/redeem roundtrip preserves value within slippage
     * @custom:audit-category ERC-4626 Compliance
     * @custom:audit-severity Critical
     */
    function testFuzz_DepositRedeem_Roundtrip(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        uint256 shares = _depositToVault(depositor, depositAmount);
        assertGt(shares, 0, "should receive shares on deposit");

        vm.prank(depositor);
        uint256 assetsReturned = vault.redeem(shares, depositor, depositor);

        assertApproxEqRel(
            assetsReturned,
            depositAmount,
            FC.MAX_ROUNDTRIP_SLIPPAGE,
            "roundtrip should preserve value within slippage"
        );
    }

    /**
     * @notice Verifies shares minted are proportional to deposit amount
     * @dev Tests that the ratio of shares to assets is consistent across different deposits.
     *      Both deposits happen sequentially into the real vault with strategy.
     * @param amount1Seed Seed for first deposit amount
     * @param amount2Seed Seed for second deposit amount
     * @custom:audit-property USDC-02: Shares minted proportional to deposit amount
     * @custom:audit-category ERC-4626 Compliance
     * @custom:audit-severity High
     */
    function testFuzz_Deposit_SharesProportional(uint256 amount1Seed, uint256 amount2Seed) public {
        uint256 amount1 = _boundUsdcAmount(amount1Seed);
        uint256 amount2 = _boundUsdcAmount(amount2Seed);

        vm.assume(amount1 != amount2);
        vm.assume(amount1 > FC.MIN_USDC_AMOUNT && amount2 > FC.MIN_USDC_AMOUNT);

        uint256 shares1 = _depositToVault(depositor, amount1);
        uint256 shares2 = _depositToVault(depositor2, amount2);

        // Assert proportionality via cross-multiplication
        uint256 cross1 = shares1 * amount2;
        uint256 cross2 = shares2 * amount1;

        assertApproxEqRel(
            cross1,
            cross2,
            FC.MAX_ROUNDTRIP_SLIPPAGE,
            "shares should be proportional to deposit"
        );
    }

    /**
     * @notice Verifies conversion roundtrip does not create free money
     * @dev Tests that `convertToAssets(convertToShares(x)) <= x` with strategy active.
     *      Requires an initial deposit so the vault has a non-trivial share price.
     * @param assetsSeed Seed for bounded asset amount
     * @custom:audit-property USDC-03: convertToAssets(convertToShares(x)) <= x
     * @custom:audit-category ERC-4626 Compliance
     * @custom:audit-severity Critical
     */
    function testFuzz_ConvertRoundtrip_NoFreeMoney(uint256 assetsSeed) public {
        // Seed deposit to establish share price
        _depositToVault(depositor, FC.MIN_USDC_AMOUNT);

        uint256 assets = _boundUsdcAmount(assetsSeed);

        uint256 shares = vault.convertToShares(assets);
        uint256 assetsBack = vault.convertToAssets(shares);

        assertLe(assetsBack, assets, "conversion roundtrip should not create free money");
    }

    /**
     * @notice Verifies previewDeposit returns a conservative estimate
     * @dev Tests that actual shares >= previewDeposit (per ERC-4626 spec) with strategy active.
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property USDC-04: previewDeposit <= actual deposit shares
     * @custom:audit-category ERC-4626 Compliance
     * @custom:audit-severity High
     */
    function testFuzz_PreviewDeposit_Conservative(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        // Establish share price with initial deposit
        _depositToVault(depositor2, FC.MIN_USDC_AMOUNT);

        uint256 previewShares = vault.previewDeposit(depositAmount);

        _fundUSDCAndApprove(depositor, address(vault), depositAmount);
        vm.prank(depositor);
        uint256 actualShares = vault.deposit(depositAmount, depositor);

        assertGe(actualShares, previewShares, "actual shares should be >= preview");
    }

    /**
     * @notice Verifies previewRedeem returns a conservative estimate
     * @dev Tests that actual assets >= previewRedeem (per ERC-4626 spec)
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property USDC-05: previewRedeem <= actual redeem assets
     * @custom:audit-category ERC-4626 Compliance
     * @custom:audit-severity High
     */
    function testFuzz_PreviewRedeem_Conservative(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        uint256 shares = _depositToVault(depositor, depositAmount);
        vm.assume(shares > 0);

        uint256 previewAssets = vault.previewRedeem(shares);

        vm.prank(depositor);
        uint256 actualAssets = vault.redeem(shares, depositor, depositor);

        assertGe(actualAssets, previewAssets, "actual assets should be >= preview");
    }

    /**
     * @notice Verifies withdrawal at maxWithdraw succeeds
     * @dev Tests that withdrawing exactly `maxWithdraw` does not revert.
     *      The real vault caps `maxWithdraw` at actual strategy liquidity.
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property USDC-06: Withdrawal respects available liquidity
     * @custom:audit-category Liquidity Management
     * @custom:audit-severity High
     */
    function testFuzz_Withdraw_RespectsMaxWithdraw(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        _depositToVault(depositor, depositAmount);

        uint256 maxWithdraw = vault.maxWithdraw(depositor);
        vm.assume(maxWithdraw > 0);

        vm.prank(depositor);
        vault.withdraw(maxWithdraw, depositor, depositor);

        assertGe(
            mockUSDC.balanceOf(depositor),
            maxWithdraw,
            "depositor should receive at least maxWithdraw assets"
        );
    }

    /**
     * @notice Verifies multiple users can deposit and withdraw independently
     * @dev Tests that concurrent user operations maintain correct share accounting.
     *      Each user's redemption should return approximately their original deposit.
     * @param amount1Seed Seed for first user deposit amount
     * @param amount2Seed Seed for second user deposit amount
     * @param amount3Seed Seed for third user deposit amount
     * @custom:audit-property USDC-07: Multiple users can deposit and withdraw independently
     * @custom:audit-category Multi-User
     * @custom:audit-severity High
     */
    function testFuzz_MultiUser_DepositWithdraw(
        uint256 amount1Seed,
        uint256 amount2Seed,
        uint256 amount3Seed
    ) public {
        uint256 amount1 = _boundUsdcAmount(amount1Seed);
        uint256 amount2 = _boundUsdcAmount(amount2Seed);
        uint256 amount3 = _boundUsdcAmount(amount3Seed);

        uint256 shares1 = _depositToVault(depositor, amount1);
        uint256 shares2 = _depositToVault(depositor2, amount2);
        uint256 shares3 = _depositToVault(depositor3, amount3);

        assertEq(
            vault.totalSupply(),
            shares1 + shares2 + shares3,
            "totalSupply should equal sum of all minted shares"
        );

        vm.prank(depositor);
        uint256 returned1 = vault.redeem(shares1, depositor, depositor);

        vm.prank(depositor2);
        uint256 returned2 = vault.redeem(shares2, depositor2, depositor2);

        vm.prank(depositor3);
        uint256 returned3 = vault.redeem(shares3, depositor3, depositor3);

        assertApproxEqRel(
            returned1,
            amount1,
            FC.MAX_ROUNDTRIP_SLIPPAGE,
            "depositor1 should receive back ~deposit"
        );
        assertApproxEqRel(
            returned2,
            amount2,
            FC.MAX_ROUNDTRIP_SLIPPAGE,
            "depositor2 should receive back ~deposit"
        );
        assertApproxEqRel(
            returned3,
            amount3,
            FC.MAX_ROUNDTRIP_SLIPPAGE,
            "depositor3 should receive back ~deposit"
        );

        assertEq(vault.totalSupply(), 0, "vault should be empty after all withdrawals");
    }

    /**
     * @notice Verifies that minting exact shares and then redeeming them returns approximately the original cost
     * @dev Uses `vault.previewMint` to determine the required deposit, adds a buffer for safety
     * @param sharesSeed Seed for bounded share amount
     * @custom:audit-property USDC-28: Mint-redeem roundtrip preserves value within slippage
     * @custom:audit-category ERC-4626 Compliance
     * @custom:audit-severity Critical
     */
    function testFuzz_MintRedeem_Roundtrip(uint256 sharesSeed) public {
        // Establish share price with an initial deposit
        _depositToVault(depositor2, FC.MIN_USDC_AMOUNT);

        // Bound shares to a reasonable range (1 share to 1M shares, scaled to vault decimals)
        uint256 shares = bound(sharesSeed, 1e6, 1_000_000e6);

        uint256 assetsNeeded = vault.previewMint(shares);
        vm.assume(assetsNeeded > 0);

        // Fund with buffer to cover rounding
        uint256 fundAmount = assetsNeeded + FC.MIN_USDC_AMOUNT;
        _fundUSDCAndApprove(depositor, address(vault), fundAmount);

        vm.prank(depositor);
        uint256 assetsCost = vault.mint(shares, depositor);

        uint256 depositorShares = vault.balanceOf(depositor);

        vm.prank(depositor);
        uint256 assetsReturned = vault.redeem(depositorShares, depositor, depositor);

        assertApproxEqRel(
            assetsReturned,
            assetsCost,
            FC.MAX_ROUNDTRIP_SLIPPAGE,
            "mint-redeem roundtrip should preserve value within slippage"
        );
    }

    // ══════════════════════════════════════════════════════════════════
    //                  VAULT-STRATEGY INTEGRATION
    // ══════════════════════════════════════════════════════════════════

    /**
     * @notice Verifies that depositing into the vault increases `strategy.totalAssets()` by the deposit amount
     * @dev Deposits flow through `_afterDeposit` -> `strategy.supply(assets)`, which splits between Aave and BLP
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property USDC-19: Deposit flows through strategy and increases strategy totalAssets
     * @custom:audit-category Vault-Strategy Integration
     * @custom:audit-severity Critical
     */
    function testFuzz_Deposit_FlowsThroughStrategy(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        uint256 strategyAssetsBefore = strategy.totalAssets();

        _depositToVault(depositor, depositAmount);

        uint256 strategyAssetsAfter = strategy.totalAssets();

        assertEq(
            strategyAssetsAfter,
            strategyAssetsBefore + depositAmount,
            "strategy totalAssets should increase by deposit amount"
        );
    }

    /**
     * @notice Verifies that withdrawing from the vault decreases `strategy.totalAssets()` and returns USDC to the user
     * @dev Withdrawals flow through `_beforeWithdraw` -> `strategy.withdraw(assets)`, which pulls from Aave and BLP
     * @param depositSeed Seed for bounded deposit amount
     * @param withdrawFractionSeed Seed for bounded withdraw fraction
     * @custom:audit-property USDC-20: Withdraw flows through strategy, decreases totalAssets, user receives USDC
     * @custom:audit-category Vault-Strategy Integration
     * @custom:audit-severity Critical
     */
    function testFuzz_Withdraw_FlowsThroughStrategy(
        uint256 depositSeed,
        uint256 withdrawFractionSeed
    ) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        _depositToVault(depositor, depositAmount);

        uint256 maxWithdraw = vault.maxWithdraw(depositor);
        vm.assume(maxWithdraw > 0);

        uint256 withdrawAmount = bound(withdrawFractionSeed, 1, maxWithdraw);

        uint256 strategyAssetsBefore = strategy.totalAssets();
        uint256 userBalanceBefore = mockUSDC.balanceOf(depositor);

        vm.prank(depositor);
        vault.withdraw(withdrawAmount, depositor, depositor);

        uint256 strategyAssetsAfter = strategy.totalAssets();
        uint256 userBalanceAfter = mockUSDC.balanceOf(depositor);

        assertLt(
            strategyAssetsAfter,
            strategyAssetsBefore,
            "strategy totalAssets should decrease after withdraw"
        );
        assertEq(
            userBalanceAfter,
            userBalanceBefore + withdrawAmount,
            "user should receive exact withdraw amount in USDC"
        );
    }

    /**
     * @notice Verifies that `vault.totalAssets()` equals `strategy.totalAssets()` plus the vault's USDC balance
     * @dev The vault's `totalAssets()` implementation delegates to strategy and adds idle vault balance
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property USDC-22: totalAssets = strategy.totalAssets() + vault USDC balance
     * @custom:audit-category Vault Accounting
     * @custom:audit-severity Critical
     */
    function testFuzz_TotalAssets_EqualsStrategyPlusVaultBalance(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        _depositToVault(depositor, depositAmount);

        uint256 expected = strategy.totalAssets() + mockUSDC.balanceOf(address(vault));

        assertEq(
            vault.totalAssets(),
            expected,
            "totalAssets should equal strategy assets plus vault idle balance"
        );
    }

    /**
     * @notice Verifies that calling `setStrategy` withdraws all funds from the old strategy's markets
     * @dev On `setStrategy`, the vault calls `withdrawAllFunds()` on the old strategy which pulls from
     *      Aave and BLP back to the strategy contract, then the vault revokes old approval and sets the new one.
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property USDC-24: setStrategy migrates funds from old strategy markets
     * @custom:audit-category Strategy Migration
     * @custom:audit-severity Critical
     */
    function testFuzz_SetStrategy_MigratesFunds(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        _depositToVault(depositor, depositAmount);

        USDCStrategy oldStrategy = strategy;

        uint256 oldStrategyMarketsBefore = oldStrategy.getTotalBalanceInMarkets();
        assertGt(
            oldStrategyMarketsBefore,
            0,
            "old strategy should have funds in markets before migration"
        );

        // Deploy a new strategy
        USDCStrategy newStrategy = new USDCStrategy(
            address(vault),
            address(mockAavePool),
            address(mockBitmorPool)
        );

        // Migrate to new strategy via UVM_SLOW role
        _scheduleAndExecuteLocal(
            uvm_slow,
            UVM_SLOW_ID(),
            abi.encodeCall(USDCVault.setStrategy, (address(newStrategy)))
        );

        uint256 oldStrategyMarketsAfter = oldStrategy.getTotalBalanceInMarkets();

        assertEq(
            oldStrategyMarketsAfter,
            0,
            "old strategy markets should be empty after migration"
        );

        // Funds were withdrawn from markets to the old strategy contract
        uint256 oldStrategyIdleBalance = mockUSDC.balanceOf(address(oldStrategy));
        assertApproxEqRel(
            oldStrategyIdleBalance,
            oldStrategyMarketsBefore,
            FC.MAX_ROUNDTRIP_SLIPPAGE,
            "old strategy should hold withdrawn funds as idle USDC"
        );
    }

    // ══════════════════════════════════════════════════════════════════
    //                  EDGE CASES & ACCESS CONTROL
    // ══════════════════════════════════════════════════════════════════

    // ──── Input Validation ────

    /**
     * @notice Depositing zero assets must revert with `Errors.ZeroAmount()`
     * @dev The vault's `deposit` override explicitly checks for `assets == 0`
     * @custom:audit-property USDC-29: Deposit reverts when zero amount is provided
     * @custom:audit-category Input Validation
     * @custom:audit-severity High
     */
    function testFuzz_Deposit_RevertsWhenZeroAmount() public {
        _fundUSDCAndApprove(depositor, address(vault), GENEROUS_FUNDING);

        vm.expectRevert(Errors.ZeroAmount.selector);
        vm.prank(depositor);
        vault.deposit(0, depositor);
    }

    /**
     * @notice Withdrawing more than the deposited amount must revert
     * @param depositSeed Seed for bounded deposit amount
     * @param excessSeed Seed for bounded excess amount added on top
     * @custom:audit-property USDC-34: Withdraw reverts when amount exceeds balance
     * @custom:audit-category Input Validation
     * @custom:audit-severity High
     */
    function testFuzz_Withdraw_RevertsWhenExceedsBalance(
        uint256 depositSeed,
        uint256 excessSeed
    ) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);
        uint256 excess = bound(excessSeed, 1, FC.MAX_USDC_AMOUNT);

        _depositToVault(depositor, depositAmount);

        uint256 withdrawAmount = depositAmount + excess;

        vm.expectRevert();
        vm.prank(depositor);
        vault.withdraw(withdrawAmount, depositor, depositor);
    }

    /**
     * @notice `setStrategy(address(0))` must revert with `Errors.ZeroAddress()`
     * @custom:audit-property USDC-40: setStrategy reverts when zero address is provided
     * @custom:audit-category Input Validation
     * @custom:audit-severity High
     */
    function testFuzz_SetStrategy_RevertsWhenZeroAddress() public {
        _scheduleAndExpectRevertLocal(
            uvm_slow,
            UVM_SLOW_ID(),
            abi.encodeCall(USDCVault.setStrategy, (address(0))),
            abi.encodeWithSelector(Errors.ZeroAddress.selector)
        );
    }

    // ──── Pause Guards ────

    /**
     * @notice Depositing while the vault is paused must revert with `EnforcedPause()`
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property USDC-30: Deposit reverts when vault is paused
     * @custom:audit-category Pause Guard
     * @custom:audit-severity Critical
     */
    function testFuzz_Deposit_RevertsWhenPaused(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        _pauseVault();

        _fundUSDCAndApprove(depositor, address(vault), depositAmount);

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(depositor);
        vault.deposit(depositAmount, depositor);
    }

    /**
     * @notice Withdrawing while the vault is paused must revert with `EnforcedPause()`
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property USDC-31: Withdraw reverts when vault is paused
     * @custom:audit-category Pause Guard
     * @custom:audit-severity Critical
     */
    function testFuzz_Withdraw_RevertsWhenPaused(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        _depositToVault(depositor, depositAmount);

        _pauseVault();

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(depositor);
        vault.withdraw(depositAmount, depositor, depositor);
    }

    /**
     * @notice Minting shares while the vault is paused must revert with `EnforcedPause()`
     * @param sharesSeed Seed for bounded shares amount
     * @custom:audit-property USDC-32: Mint reverts when vault is paused
     * @custom:audit-category Pause Guard
     * @custom:audit-severity Critical
     */
    function testFuzz_Mint_RevertsWhenPaused(uint256 sharesSeed) public {
        uint256 sharesToMint = bound(sharesSeed, MIN_SHARES, MAX_SHARES);

        _pauseVault();

        _fundUSDCAndApprove(depositor, address(vault), GENEROUS_FUNDING);

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(depositor);
        vault.mint(sharesToMint, depositor);
    }

    /**
     * @notice Redeeming shares while the vault is paused must revert with `EnforcedPause()`
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property USDC-33: Redeem reverts when vault is paused
     * @custom:audit-category Pause Guard
     * @custom:audit-severity Critical
     */
    function testFuzz_Redeem_RevertsWhenPaused(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        uint256 shares = _depositToVault(depositor, depositAmount);

        _pauseVault();

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(depositor);
        vault.redeem(shares, depositor, depositor);
    }

    // ──── Access Control ────

    /**
     * @notice Calling `strategy.supply()` from a non-vault address must revert
     * @param amountSeed Seed for bounded supply amount
     * @custom:audit-property USDC-35: Strategy supply reverts when caller is not the vault
     * @custom:audit-category Access Control
     * @custom:audit-severity Critical
     */
    function testFuzz_Strategy_Supply_RevertsWhenNotVault(uint256 amountSeed) public {
        uint256 amount = _boundUsdcAmount(amountSeed);
        address randomCaller = makeAddr("randomCaller");

        vm.expectRevert(USDCStrategy.USDCStrategy__NotVault.selector);
        vm.prank(randomCaller);
        strategy.supply(amount);
    }

    /**
     * @notice Calling `strategy.withdraw()` from a non-vault address must revert
     * @param amountSeed Seed for bounded withdraw amount
     * @custom:audit-property USDC-36: Strategy withdraw reverts when caller is not the vault
     * @custom:audit-category Access Control
     * @custom:audit-severity Critical
     */
    function testFuzz_Strategy_Withdraw_RevertsWhenNotVault(uint256 amountSeed) public {
        uint256 amount = _boundUsdcAmount(amountSeed);
        address randomCaller = makeAddr("randomCaller");

        vm.expectRevert(USDCStrategy.USDCStrategy__NotVault.selector);
        vm.prank(randomCaller);
        strategy.withdraw(amount);
    }

    /**
     * @notice `reallocateAssets(uint256)` must revert with `UnauthorizedCaller` when called by
     *         an address that holds the UVA role but is not the Bitmor Lending Pool
     * @dev The function has both a `restricted` modifier (AccessManager role check) and an
     *      explicit `msg.sender != i_blp` guard.
     * @param amountSeed Seed for bounded reallocation amount
     * @custom:audit-property USDC-39: reallocateAssets(uint256) reverts when caller is not BLP
     * @custom:audit-category Access Control
     * @custom:audit-severity Critical
     */
    function testFuzz_ReallocateWithAmount_RevertsWhenNotBLP(uint256 amountSeed) public {
        uint256 depositAmount = _boundUsdcAmount(amountSeed);

        _depositToVault(depositor, depositAmount);

        uint256 amount = bound(amountSeed, 1, depositAmount);
        address randomCaller = makeAddr("notBLP");

        manager.grantRole(UVA_ID(), randomCaller, 0);

        vm.expectRevert(abi.encodeWithSelector(Errors.UnauthorizedCaller.selector));
        vm.prank(randomCaller);
        vault.reallocateAssets(amount);
    }

    // ──── Allocation & Inflation Resistance ────

    /**
     * @notice Strategy supply must succeed regardless of the current Aave allocation setting
     * @param amountSeed Seed for bounded supply amount
     * @param allocationSeed Seed for bounded allocation in basis points
     * @custom:audit-property USDC-37: Strategy supply works at any allocation setting
     * @custom:audit-category Allocation Robustness
     * @custom:audit-severity High
     */
    function testFuzz_Supply_WorksAtAnyAllocation(
        uint256 amountSeed,
        uint256 allocationSeed
    ) public {
        uint256 amount = _boundUsdcAmount(amountSeed);
        uint256 allocationBps = _boundAllocationBps(allocationSeed);

        _setAllocation(allocationBps);
        mockUSDC.mint(address(vault), amount);

        vm.prank(address(vault));
        strategy.supply(amount);

        uint256 totalBalance = strategy.totalAssets();
        assertGt(totalBalance, 0, "strategy totalAssets should be positive after supply");
    }

    /**
     * @notice The asset value of minted shares must never exceed the deposited amount
     * @dev Guards against share-inflation attacks where `convertToAssets(shares) > deposit`
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property USDC-38: Shares never exceed deposit value (no inflation attack)
     * @custom:audit-category ERC-4626 Security
     * @custom:audit-severity Critical
     */
    function testFuzz_SharesNeverExceedDeposit(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        uint256 shares = _depositToVault(depositor, depositAmount);

        uint256 assetsFromShares = vault.convertToAssets(shares);
        assertLe(
            assetsFromShares,
            depositAmount,
            "convertToAssets(shares) should never exceed original deposit amount"
        );
    }
}
