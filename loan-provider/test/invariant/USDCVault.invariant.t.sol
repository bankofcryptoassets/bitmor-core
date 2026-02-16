// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {USDCVaultHandler} from "./handlers/USDCVaultHandler.sol";
import {USDCVault} from "@bitmor/vaults/usdc-vault/USDCVault.sol";
import {USDCStrategy} from "@bitmor/vaults/usdc-vault/USDCStrategy.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

/**
 * @title USDCVaultInvariantTest
 * @author Bitmor Protocol
 * @notice Invariant tests for USDCVault with real vault + strategy
 * @dev Configures `USDCVaultHandler` as the target contract and validates
 *      6 invariants across randomized deposit/withdraw/redeem/mint sequences.
 *
 * ## Invariants
 * - INV-USDC-01: totalSupply == ghost_minted - ghost_redeemed
 * - INV-USDC-02: totalAssets >= totalSupply (share price floor)
 * - INV-USDC-03: totalAssets == strategy.totalAssets() + vault USDC balance
 * - INV-USDC-04: convertToAssets(convertToShares(x)) <= x (no free money)
 * - INV-USDC-05: Vault not paused during normal operations
 * - INV-USDC-06: Call summary (observability)
 *
 * @custom:audit-category Invariant Testing, ERC-4626 Compliance
 */
contract USDCVaultInvariantTest is Test {
    /// @dev The handler contract (also deploys vault + strategy in setUp)
    USDCVaultHandler internal handler;

    /// @dev Cached references to vault and strategy from handler
    USDCVault internal vault;
    USDCStrategy internal strategy;

    /// @dev Reference amount for conversion round-trip test
    uint256 internal constant CONVERSION_TEST_AMOUNT = 1_000e6;

    function setUp() public {
        handler = new USDCVaultHandler();
        handler.setUp();

        // Cache vault and strategy references
        vault = handler.getVault();
        strategy = handler.getStrategy();

        // Configure invariant test targets
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = USDCVaultHandler.handler_deposit.selector;
        selectors[1] = USDCVaultHandler.handler_redeem.selector;
        selectors[2] = USDCVaultHandler.handler_withdraw.selector;
        selectors[3] = USDCVaultHandler.handler_mint.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    // ============ Invariants ============

    /**
     * @notice INV-USDC-01: Total supply equals ghost minted minus ghost redeemed
     * @dev Validates that the vault's on-chain totalSupply stays in sync with
     *      the handler's ghost tracking of minted and redeemed shares.
     */
    function invariant_USDC_01_TotalSupplyMatchesGhostShares() public view {
        uint256 expectedSupply = handler.ghost_totalSharesMinted() - handler.ghost_totalSharesRedeemed();
        uint256 actualSupply = vault.totalSupply();

        assertEq(actualSupply, expectedSupply, "INV-USDC-01: totalSupply != ghost_minted - ghost_redeemed");
    }

    /**
     * @notice INV-USDC-02: Share price floor — totalAssets >= totalSupply
     * @dev For USDC (6 decimals), 1 share should always be worth >= 1 asset unit.
     *      This invariant catches share dilution bugs.
     */
    function invariant_USDC_02_SharePriceFloor() public view {
        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();

        if (totalSupply > 0) {
            assertGe(totalAssets, totalSupply, "INV-USDC-02: totalAssets < totalSupply (share price below 1:1)");
        }
    }

    /**
     * @notice INV-USDC-03: totalAssets consistency — equals strategy balance + vault USDC balance
     * @dev Ensures totalAssets() correctly sums assets across all locations:
     *      strategy's deployed assets (Aave + BLP) and vault's direct USDC holdings.
     */
    function invariant_USDC_03_TotalAssetsConsistency() public view {
        uint256 vaultTotalAssets = vault.totalAssets();
        uint256 strategyAssets = strategy.totalAssets();
        uint256 vaultUsdcBalance = IERC20(vault.asset()).balanceOf(address(vault));

        assertEq(
            vaultTotalAssets,
            strategyAssets + vaultUsdcBalance,
            "INV-USDC-03: totalAssets != strategy.totalAssets() + vault USDC balance"
        );
    }

    /**
     * @notice INV-USDC-04: No free money — convertToAssets(convertToShares(x)) <= x
     * @dev Validates that the share/asset conversion round-trip never inflates value.
     *      Uses a fixed test amount; the fuzz harness exercises varied vault states.
     */
    function invariant_USDC_04_NoFreeMoney() public view {
        uint256 totalSupply = vault.totalSupply();
        if (totalSupply == 0) return;

        uint256 shares = vault.convertToShares(CONVERSION_TEST_AMOUNT);
        uint256 assetsBack = vault.convertToAssets(shares);

        assertLe(assetsBack, CONVERSION_TEST_AMOUNT, "INV-USDC-04: conversion round-trip created free money");
    }

    /**
     * @notice INV-USDC-05: Vault not paused during normal operations
     * @dev No handler function pauses the vault, so it should remain unpaused throughout.
     */
    function invariant_USDC_05_VaultNotPaused() public view {
        assertFalse(vault.paused(), "INV-USDC-05: vault is paused during normal operations");
    }

    /**
     * @notice INV-USDC-06: Call summary — logs handler call counts for observability
     * @dev Always passes. Provides visibility into how many of each operation type
     *      the fuzzer exercised during the invariant run.
     */
    function invariant_USDC_06_CallSummary() public view {
        // This invariant always passes — it exists for observability
        uint256 totalCalls = handler.ghost_totalCalls();
        uint256 deposits = handler.ghost_depositCount();
        uint256 redeems = handler.ghost_redeemCount();
        uint256 withdraws = handler.ghost_withdrawCount();
        uint256 mints = handler.ghost_mintCount();

        // Silence unused variable warnings while keeping observability
        assertTrue(totalCalls >= 0, "INV-USDC-06: call summary");
        assertTrue(deposits >= 0, "INV-USDC-06: deposits");
        assertTrue(redeems >= 0, "INV-USDC-06: redeems");
        assertTrue(withdraws >= 0, "INV-USDC-06: withdraws");
        assertTrue(mints >= 0, "INV-USDC-06: mints");
    }
}
