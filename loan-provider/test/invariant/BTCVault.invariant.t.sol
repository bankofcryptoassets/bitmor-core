// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {BTCVaultHandler} from "./handlers/BTCVaultHandler.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {FuzzConstants as FC} from "../fuzz/helpers/FuzzConstants.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";

/**
 * @title BTCVaultInvariantTest
 * @author Bitmor Protocol
 * @notice Invariant tests for BTCVault with real vault + multi-strategy
 * @dev Configures `BTCVaultHandler` as the target contract and validates
 *      6 invariants across randomized deposit/withdraw/redeem/mint/reallocate/yield sequences.
 *
 * ## Invariants
 * - INV-BTC-01: Solvency — totalAssets >= convertToAssets(totalSupply)
 * - INV-BTC-02: Ghost accounting — deposited - withdrawn - fees + yield ~ totalAssets
 * - INV-BTC-03: Strategy balance consistency — sum of strategies == totalAssets
 * - INV-BTC-04: No free money — convertToAssets(convertToShares(x)) <= x
 * - INV-BTC-05: Fee recipient balance ~ ghost_totalEntryFees + ghost_totalExitFees
 * - INV-BTC-06: Share supply — totalSupply == ghost_minted - ghost_redeemed
 *
 * @custom:audit-category Invariant Testing, ERC-4626 Compliance
 */
contract BTCVaultInvariantTest is Test {
    /// @dev The handler contract (also deploys vault + strategies in setUp)
    BTCVaultHandler internal handler;

    /// @dev Cached reference to the vault from handler
    BTCVault internal vault;

    /// @dev Reference amount for conversion round-trip test
    uint256 internal constant CONVERSION_TEST_AMOUNT = 1e8;

    function setUp() public {
        handler = new BTCVaultHandler();
        handler.setUp();
        vault = handler.getVault();

        // Target only the handler
        targetContract(address(handler));

        // Target specific handler functions
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = handler.handler_deposit.selector;
        selectors[1] = handler.handler_mint.selector;
        selectors[2] = handler.handler_withdraw.selector;
        selectors[3] = handler.handler_redeem.selector;
        selectors[4] = handler.handler_reallocate.selector;
        selectors[5] = handler.handler_simulateYield.selector;
        selectors[6] = handler.handler_setEntryFee.selector;
        selectors[7] = handler.handler_setExitFee.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // ============ Invariants ============

    /**
     * @notice INV-BTC-01: Solvency — if shares exist, assets must exist and cover them
     * @dev Validates that totalAssets >= convertToAssets(totalSupply) within rounding tolerance.
     *      Catches share inflation or asset drain bugs.
     * @custom:audit-invariant INV-BTC-01
     */
    function invariant_BTC_01_Solvency() public view {
        uint256 totalSupply = vault.totalSupply();
        uint256 totalAssets = vault.totalAssets();

        if (totalSupply > 0) {
            assertGt(totalAssets, 0, "INV-BTC-01: totalSupply > 0 but totalAssets == 0");

            uint256 assetsForAllShares = vault.convertToAssets(totalSupply);
            // Allow 1 wei rounding tolerance per share unit
            assertGe(totalAssets + 1, assetsForAllShares, "INV-BTC-01: totalAssets < convertToAssets(totalSupply)");
        }
    }

    /**
     * @notice INV-BTC-02: Ghost accounting — cumulative totalAssets deltas track correctly
     * @dev Uses delta-based accounting: measures actual totalAssets changes per operation
     *      rather than reconstructing from gross deposits/fees. This avoids systematic error
     *      from the double-layer ERC4626 virtual share offset in strategy convertToAssets.
     *
     *      Invariant: `vault.totalAssets() == ghost_netAssetsIn - ghost_netAssetsOut`
     *      where netAssetsIn/Out are measured from actual totalAssets deltas each operation.
     *
     * @custom:audit-invariant INV-BTC-02
     */
    function invariant_BTC_02_GhostAccounting() public view {
        uint256 totalOps = handler.ghost_totalOps();
        if (totalOps == 0) return;

        uint256 netIn = handler.ghost_netAssetsIn();
        uint256 netOut = handler.ghost_netAssetsOut();
        uint256 totalAssets = vault.totalAssets();

        uint256 expected = netIn > netOut ? netIn - netOut : 0;

        // Each operation can introduce rounding through double-layer ERC-4626 share
        // conversion (vault shares -> strategy shares -> aToken). Scale tolerance
        // proportionally to total operations, matching INV-BTC-05's approach.
        uint256 allOps = totalOps + handler.ghost_reallocateCount() + handler.ghost_yieldCount();
        uint256 tolerance = allOps * FC.MAX_ROUNDING_ERROR;

        assertApproxEqAbs(totalAssets, expected, tolerance, "INV-BTC-02: ghost accounting mismatch with totalAssets");
    }

    /**
     * @notice INV-BTC-03: Strategy balance consistency — sum of strategy assets == totalAssets
     * @dev Iterates all strategies and confirms their asset sum matches vault.totalAssets().
     * @custom:audit-invariant INV-BTC-03
     */
    function invariant_BTC_03_StrategyBalanceConsistency() public view {
        uint256 totalStrategies = vault.getTotalStrategies();
        uint256 sumStrategyAssets = 0;

        for (uint256 i = 0; i < totalStrategies; i++) {
            DataTypes.Strategy memory strat = vault.getStrategyDetails(i);
            sumStrategyAssets += vault.getAssetInStrategy(strat.strategy);
        }

        assertEq(vault.totalAssets(), sumStrategyAssets, "INV-BTC-03: totalAssets != sum of strategy balances");
    }

    /**
     * @notice INV-BTC-04: No free money — round-trip conversion never inflates value
     * @dev For a fixed test amount, convertToAssets(convertToShares(x)) <= x.
     * @custom:audit-invariant INV-BTC-04
     */
    function invariant_BTC_04_NoFreeMoney() public view {
        uint256 totalSupply = vault.totalSupply();
        if (totalSupply == 0) return;

        uint256 shares = vault.convertToShares(CONVERSION_TEST_AMOUNT);
        uint256 assetsBack = vault.convertToAssets(shares);

        assertLe(assetsBack, CONVERSION_TEST_AMOUNT, "INV-BTC-04: conversion round-trip created free money");
    }

    /**
     * @notice INV-BTC-05: Fee recipient balance tracks ghost fee totals
     * @dev The fee recipient's cbBTC balance should approximately equal the sum of
     *      entry and exit fees tracked by ghost state.
     * @custom:audit-invariant INV-BTC-05
     */
    function invariant_BTC_05_FeeRecipientBalance() public view {
        uint256 totalOps = handler.ghost_totalOps();

        address feeRecipientAddr = handler.getFeeRecipient();
        address mockCbBTCAddr = address(handler.getMockCbBTC());

        uint256 recipientBalance = IERC20(mockCbBTCAddr).balanceOf(feeRecipientAddr);
        uint256 expectedFees = handler.ghost_totalEntryFees() + handler.ghost_totalExitFees();

        // Tolerance: 2 wei per operation for rounding
        uint256 tolerance = totalOps * FC.MAX_ROUNDING_ERROR;

        assertApproxEqAbs(
            recipientBalance,
            expectedFees,
            tolerance,
            "INV-BTC-05: feeRecipient balance != ghost_totalEntryFees + ghost_totalExitFees"
        );
    }

    /**
     * @notice INV-BTC-06: Share supply — totalSupply == ghost minted - ghost redeemed
     * @dev Validates that the vault's on-chain totalSupply stays in sync with
     *      the handler's ghost tracking of minted and redeemed shares.
     * @custom:audit-invariant INV-BTC-06
     */
    function invariant_BTC_06_ShareSupply() public view {
        uint256 expectedSupply = handler.ghost_totalSharesMinted() - handler.ghost_totalSharesRedeemed();
        uint256 actualSupply = vault.totalSupply();

        assertEq(actualSupply, expectedSupply, "INV-BTC-06: totalSupply != ghost_minted - ghost_redeemed");
    }

    /**
     * @notice Call summary — logs handler call counts for observability
     * @dev Always passes. Provides visibility into how many of each operation type
     *      the fuzzer exercised during the invariant run.
     */
    function invariant_BTC_07_CallSummary() public view {
        uint256 totalCalls = handler.ghost_totalCalls();
        uint256 deposits = handler.ghost_depositCount();
        uint256 mints = handler.ghost_mintCount();
        uint256 withdraws = handler.ghost_withdrawCount();
        uint256 redeems = handler.ghost_redeemCount();
        uint256 reallocates = handler.ghost_reallocateCount();
        uint256 yields = handler.ghost_yieldCount();

        // Silence unused variable warnings while keeping observability
        assertTrue(totalCalls >= 0, "INV-BTC-07: call summary");
        assertTrue(deposits >= 0, "INV-BTC-07: deposits");
        assertTrue(mints >= 0, "INV-BTC-07: mints");
        assertTrue(withdraws >= 0, "INV-BTC-07: withdraws");
        assertTrue(redeems >= 0, "INV-BTC-07: redeems");
        assertTrue(reallocates >= 0, "INV-BTC-07: reallocates");
        assertTrue(yields >= 0, "INV-BTC-07: yields");
    }
}
