// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {USDCStrategyFuzzTestBase} from "../base/USDCStrategyFuzzTestBase.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";
import {USDCVault} from "@bitmor/vaults/usdc-vault/USDCVault.sol";
import {USDCStrategy} from "@bitmor/vaults/usdc-vault/USDCStrategy.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

/**
 * @title USDCVaultIntegrationFuzzTest
 * @author Bitmor Protocol
 * @notice Fuzz tests for the USDC vault integrated with a real strategy (USDC-19 through USDC-28)
 * @dev Validates that deposits and withdrawals flow correctly through the vault-strategy pipeline,
 *      ERC-4626 preview functions remain conservative, and multi-user interactions are independent.
 *      Uses real `USDCVault` and `USDCStrategy` backed by mock Aave and Bitmor Lending Pool.
 */
contract USDCVaultIntegrationFuzzTest is USDCStrategyFuzzTestBase {
    // ============ Test USDC-19: Deposit Flows Through Strategy ============

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

    // ============ Test USDC-20: Withdraw Flows Through Strategy ============

    /**
     * @notice Verifies that withdrawing from the vault decreases `strategy.totalAssets()` and returns USDC to the user
     * @dev Withdrawals flow through `_beforeWithdraw` -> `strategy.withdraw(assets)`, which pulls from Aave and BLP
     * @param depositSeed Seed for bounded deposit amount
     * @param withdrawFractionSeed Seed for bounded withdraw fraction
     * @custom:audit-property USDC-20: Withdraw flows through strategy, decreases totalAssets, user receives USDC
     * @custom:audit-category Vault-Strategy Integration
     * @custom:audit-severity Critical
     */
    function testFuzz_Withdraw_FlowsThroughStrategy(uint256 depositSeed, uint256 withdrawFractionSeed) public {
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

        assertLt(strategyAssetsAfter, strategyAssetsBefore, "strategy totalAssets should decrease after withdraw");
        assertEq(
            userBalanceAfter, userBalanceBefore + withdrawAmount, "user should receive exact withdraw amount in USDC"
        );
    }

    // ============ Test USDC-21: Deposit-Redeem Roundtrip With Strategy ============

    /**
     * @notice Verifies that depositing and then redeeming all shares returns approximately the original deposit
     * @dev Roundtrip loss may occur from share rounding but must stay within `FC.MAX_ROUNDTRIP_SLIPPAGE`
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property USDC-21: Deposit-redeem roundtrip with strategy preserves value within slippage
     * @custom:audit-category ERC-4626 Compliance
     * @custom:audit-severity Critical
     */
    function testFuzz_DepositRedeem_Roundtrip_WithStrategy(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        uint256 shares = _depositToVault(depositor, depositAmount);

        assertGt(shares, 0, "should receive shares on deposit");

        vm.prank(depositor);
        uint256 assetsReturned = vault.redeem(shares, depositor, depositor);

        assertApproxEqRel(
            assetsReturned,
            depositAmount,
            FC.MAX_ROUNDTRIP_SLIPPAGE,
            "roundtrip with strategy should preserve value within slippage"
        );
    }

    // ============ Test USDC-22: TotalAssets Equals Strategy Plus Vault Balance ============

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

        assertEq(vault.totalAssets(), expected, "totalAssets should equal strategy assets plus vault idle balance");
    }

    // ============ Test USDC-23: Multi-User Independent Shares With Strategy ============

    /**
     * @notice Verifies that multiple depositors receive independent shares and can each redeem approximately their deposit
     * @dev Tests that totalSupply equals the sum of individual shares and each user's redemption is proportional
     * @param a1Seed Seed for first depositor amount
     * @param a2Seed Seed for second depositor amount
     * @param a3Seed Seed for third depositor amount
     * @custom:audit-property USDC-23: Multi-user shares are independent with strategy
     * @custom:audit-category Multi-User
     * @custom:audit-severity High
     */
    function testFuzz_MultiUser_IndependentShares_WithStrategy(uint256 a1Seed, uint256 a2Seed, uint256 a3Seed) public {
        uint256 amount1 = _boundUsdcAmount(a1Seed);
        uint256 amount2 = _boundUsdcAmount(a2Seed);
        uint256 amount3 = _boundUsdcAmount(a3Seed);

        uint256 shares1 = _depositToVault(depositor, amount1);
        uint256 shares2 = _depositToVault(depositor2, amount2);
        uint256 shares3 = _depositToVault(depositor3, amount3);

        assertEq(vault.totalSupply(), shares1 + shares2 + shares3, "totalSupply should equal sum of all minted shares");

        // Each user redeems and receives approximately their original deposit
        vm.prank(depositor);
        uint256 returned1 = vault.redeem(shares1, depositor, depositor);

        vm.prank(depositor2);
        uint256 returned2 = vault.redeem(shares2, depositor2, depositor2);

        vm.prank(depositor3);
        uint256 returned3 = vault.redeem(shares3, depositor3, depositor3);

        assertApproxEqRel(
            returned1, amount1, FC.MAX_ROUNDTRIP_SLIPPAGE, "depositor1 should receive back approximately their deposit"
        );
        assertApproxEqRel(
            returned2, amount2, FC.MAX_ROUNDTRIP_SLIPPAGE, "depositor2 should receive back approximately their deposit"
        );
        assertApproxEqRel(
            returned3, amount3, FC.MAX_ROUNDTRIP_SLIPPAGE, "depositor3 should receive back approximately their deposit"
        );
    }

    // ============ Test USDC-24: SetStrategy Migrates Funds ============

    /**
     * @notice Verifies that calling `setStrategy` withdraws all funds from the old strategy's markets
     * @dev On `setStrategy`, the vault calls `withdrawAllFunds()` on the old strategy which pulls from
     *      Aave and BLP back to the strategy contract, then the vault revokes old approval and sets the new one.
     *      The old strategy's market positions are emptied.
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
        assertGt(oldStrategyMarketsBefore, 0, "old strategy should have funds in markets before migration");

        // Deploy a new strategy
        USDCStrategy newStrategy = new USDCStrategy(address(vault), address(mockAavePool), address(mockBitmorPool));

        // Migrate to new strategy via UVM_SLOW role
        _scheduleAndExecuteLocal(uvm_slow, UVM_SLOW_ID(), abi.encodeCall(USDCVault.setStrategy, (address(newStrategy))));

        uint256 oldStrategyMarketsAfter = oldStrategy.getTotalBalanceInMarkets();

        assertEq(oldStrategyMarketsAfter, 0, "old strategy markets should be empty after migration");

        // Funds were withdrawn from markets to the old strategy contract
        uint256 oldStrategyIdleBalance = mockUSDC.balanceOf(address(oldStrategy));
        assertApproxEqRel(
            oldStrategyIdleBalance,
            oldStrategyMarketsBefore,
            FC.MAX_ROUNDTRIP_SLIPPAGE,
            "old strategy should hold withdrawn funds as idle USDC"
        );
    }

    // ============ Test USDC-25: Convert Roundtrip No Free Money With Strategy ============

    /**
     * @notice Verifies that `convertToAssets(convertToShares(x)) <= x` when strategy has assets deployed
     * @dev Establishes share price with an initial deposit, then checks no free money from conversion roundtrip
     * @param assetsSeed Seed for bounded asset amount
     * @custom:audit-property USDC-25: convertToAssets(convertToShares(x)) <= x with strategy
     * @custom:audit-category ERC-4626 Compliance
     * @custom:audit-severity Critical
     */
    function testFuzz_ConvertRoundtrip_NoFreeMoney_WithStrategy(uint256 assetsSeed) public {
        uint256 assets = _boundUsdcAmount(assetsSeed);

        // Establish share price with an initial deposit
        _depositToVault(depositor, FC.MIN_USDC_AMOUNT);

        uint256 shares = vault.convertToShares(assets);
        uint256 assetsBack = vault.convertToAssets(shares);

        assertLe(assetsBack, assets, "conversion roundtrip should not create free money with strategy active");
    }

    // ============ Test USDC-26: Preview Deposit Conservative With Strategy ============

    /**
     * @notice Verifies that `previewDeposit` returns a conservative (lower-bound) estimate per ERC-4626 spec
     * @dev Actual shares minted must be >= preview shares when strategy is active
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property USDC-26: previewDeposit <= actual shares with strategy
     * @custom:audit-category ERC-4626 Compliance
     * @custom:audit-severity High
     */
    function testFuzz_PreviewDeposit_Conservative_WithStrategy(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        // Establish share price with an initial deposit
        _depositToVault(depositor2, FC.MIN_USDC_AMOUNT);

        uint256 previewShares = vault.previewDeposit(depositAmount);

        _fundUSDCAndApprove(depositor, address(vault), depositAmount);
        vm.prank(depositor);
        uint256 actualShares = vault.deposit(depositAmount, depositor);

        assertGe(actualShares, previewShares, "actual shares should be >= preview with strategy active");
    }

    // ============ Test USDC-27: Preview Redeem Conservative With Strategy ============

    /**
     * @notice Verifies that `previewRedeem` returns a conservative (lower-bound) estimate per ERC-4626 spec
     * @dev Actual assets received must be >= preview assets when strategy is active
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property USDC-27: previewRedeem <= actual assets with strategy
     * @custom:audit-category ERC-4626 Compliance
     * @custom:audit-severity High
     */
    function testFuzz_PreviewRedeem_Conservative_WithStrategy(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        uint256 shares = _depositToVault(depositor, depositAmount);

        vm.assume(shares > 0);

        uint256 previewAssets = vault.previewRedeem(shares);

        vm.prank(depositor);
        uint256 actualAssets = vault.redeem(shares, depositor, depositor);

        assertGe(actualAssets, previewAssets, "actual assets should be >= preview with strategy active");
    }

    // ============ Test USDC-28: Mint-Redeem Roundtrip With Strategy ============

    /**
     * @notice Verifies that minting exact shares and then redeeming them returns approximately the original cost
     * @dev Uses `vault.previewMint` to determine the required deposit, adds a buffer for safety
     * @param sharesSeed Seed for bounded share amount
     * @custom:audit-property USDC-28: Mint-redeem roundtrip with strategy preserves value within slippage
     * @custom:audit-category ERC-4626 Compliance
     * @custom:audit-severity Critical
     */
    function testFuzz_MintRedeem_Roundtrip_WithStrategy(uint256 sharesSeed) public {
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
            "mint-redeem roundtrip with strategy should preserve value within slippage"
        );
    }
}
