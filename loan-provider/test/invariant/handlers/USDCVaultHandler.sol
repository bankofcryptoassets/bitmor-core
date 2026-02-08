// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {USDCStrategyFuzzTestBase} from "../../fuzz/base/USDCStrategyFuzzTestBase.sol";
import {FuzzConstants as FC} from "../../fuzz/helpers/FuzzConstants.sol";
import {USDCVault} from "@bitmor/vaults/usdc-vault/USDCVault.sol";
import {USDCStrategy} from "@bitmor/vaults/usdc-vault/USDCStrategy.sol";

/**
 * @title USDCVaultHandler
 * @author Bitmor Protocol
 * @notice Handler contract for invariant testing of USDCVault with real vault + strategy
 * @dev Provides 4 handler functions (deposit, redeem, withdraw, mint) with ghost state tracking.
 *      Extends `USDCStrategyFuzzTestBase` to get real `USDCVault` and `USDCStrategy` backed by mocks.
 *      Multi-actor: rotates through `depositor`/`depositor2`/`depositor3`.
 *      All operations use `try/catch` for graceful failure on boundary conditions.
 *
 * @custom:audit-category Invariant Testing, ERC-4626 Compliance
 */
contract USDCVaultHandler is USDCStrategyFuzzTestBase {
    // ============ Ghost State ============

    /// @dev Total USDC deposited across all handler operations
    uint256 public ghost_totalDeposited;

    /// @dev Total USDC withdrawn across all handler operations
    uint256 public ghost_totalWithdrawn;

    /// @dev Total vault shares minted across all handler operations
    uint256 public ghost_totalSharesMinted;

    /// @dev Total vault shares redeemed/burned across all handler operations
    uint256 public ghost_totalSharesRedeemed;

    // ============ Per-User Ghost State ============

    /// @dev Per-user total deposited amount
    mapping(address => uint256) public ghost_userDeposited;

    /// @dev Per-user total withdrawn amount
    mapping(address => uint256) public ghost_userWithdrawn;

    // ============ Call Counters ============

    /// @dev Number of successful deposit operations
    uint256 public ghost_depositCount;

    /// @dev Number of successful redeem operations
    uint256 public ghost_redeemCount;

    /// @dev Number of successful withdraw operations
    uint256 public ghost_withdrawCount;

    /// @dev Number of successful mint operations
    uint256 public ghost_mintCount;

    // ============ Actor Rotation ============

    /// @dev Array of depositor actors for rotation
    address[] internal _actors;

    // ============ Setup ============

    function setUp() public override {
        super.setUp();
        _actors.push(depositor);
        _actors.push(depositor2);
        _actors.push(depositor3);
    }

    // ============ Internal Helpers ============

    /// @notice Selects an actor from the rotation based on a seed
    /// @param seed Raw fuzzed value for actor selection
    /// @return actor The selected actor address
    function _selectActor(uint256 seed) internal view returns (address) {
        return _actors[seed % _actors.length];
    }

    // ============ Handler Functions ============

    /**
     * @notice Handler for vault deposit operations
     * @dev Funds the actor with USDC, approves vault, and deposits.
     *      Updates ghost state on success.
     * @param amountSeed Seed for bounded deposit amount
     * @param actorSeed Seed for actor selection
     */
    function handler_deposit(uint256 amountSeed, uint256 actorSeed) external {
        address actor = _selectActor(actorSeed);
        uint256 amount = _boundUsdcAmount(amountSeed);

        _fundUSDCAndApprove(actor, address(vault), amount);

        vm.prank(actor);
        try vault.deposit(amount, actor) returns (uint256 shares) {
            ghost_totalDeposited += amount;
            ghost_totalSharesMinted += shares;
            ghost_userDeposited[actor] += amount;
            ghost_depositCount++;
        } catch {
            // Graceful failure
        }
    }

    /**
     * @notice Handler for vault redeem operations
     * @dev Redeems a bounded portion of the actor's shares.
     *      Skips if actor has no shares.
     * @param sharesSeed Seed for bounded shares to redeem
     * @param actorSeed Seed for actor selection
     */
    function handler_redeem(uint256 sharesSeed, uint256 actorSeed) external {
        address actor = _selectActor(actorSeed);
        uint256 actorShares = vault.balanceOf(actor);
        if (actorShares == 0) return;

        uint256 shares = bound(sharesSeed, 1, actorShares);

        vm.prank(actor);
        try vault.redeem(shares, actor, actor) returns (uint256 assets) {
            ghost_totalWithdrawn += assets;
            ghost_totalSharesRedeemed += shares;
            ghost_userWithdrawn[actor] += assets;
            ghost_redeemCount++;
        } catch {
            // Graceful failure
        }
    }

    /**
     * @notice Handler for vault withdraw operations
     * @dev Withdraws a bounded portion of the actor's maxWithdraw.
     *      Skips if actor has no withdrawable assets.
     * @param assetsSeed Seed for bounded assets to withdraw
     * @param actorSeed Seed for actor selection
     */
    function handler_withdraw(uint256 assetsSeed, uint256 actorSeed) external {
        address actor = _selectActor(actorSeed);
        uint256 maxAssets = vault.maxWithdraw(actor);
        if (maxAssets == 0) return;

        uint256 assets = bound(assetsSeed, 1, maxAssets);

        vm.prank(actor);
        try vault.withdraw(assets, actor, actor) returns (uint256 shares) {
            ghost_totalWithdrawn += assets;
            ghost_totalSharesRedeemed += shares;
            ghost_userWithdrawn[actor] += assets;
            ghost_withdrawCount++;
        } catch {
            // Graceful failure
        }
    }

    /**
     * @notice Handler for vault mint operations
     * @dev Mints a bounded number of shares by depositing the required assets.
     *      Skips if the preview shows an unreasonable asset requirement.
     * @param sharesSeed Seed for bounded shares to mint
     * @param actorSeed Seed for actor selection
     */
    function handler_mint(uint256 sharesSeed, uint256 actorSeed) external {
        address actor = _selectActor(actorSeed);

        // Bound shares to a reasonable range
        uint256 shares = bound(sharesSeed, 1, FC.MAX_USDC_AMOUNT);

        // Preview assets needed
        uint256 assetsNeeded = vault.previewMint(shares);
        if (assetsNeeded == 0 || assetsNeeded > FC.MAX_USDC_AMOUNT) return;

        _fundUSDCAndApprove(actor, address(vault), assetsNeeded);

        vm.prank(actor);
        try vault.mint(shares, actor) returns (uint256 assetsUsed) {
            ghost_totalDeposited += assetsUsed;
            ghost_totalSharesMinted += shares;
            ghost_userDeposited[actor] += assetsUsed;
            ghost_mintCount++;
        } catch {
            // Graceful failure
        }
    }

    // ============ View Functions ============

    /// @notice Returns the total number of successful handler calls
    function ghost_totalCalls() external view returns (uint256) {
        return ghost_depositCount + ghost_redeemCount + ghost_withdrawCount + ghost_mintCount;
    }

    /// @notice Exposes the internal `vault` for invariant test assertions
    function getVault() external view returns (USDCVault) {
        return vault;
    }

    /// @notice Exposes the internal `strategy` for invariant test assertions
    function getStrategy() external view returns (USDCStrategy) {
        return strategy;
    }
}
