// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BTCVaultFuzzTestBase} from "../../fuzz/base/BTCVaultFuzzTestBase.sol";
import {FuzzConstants as FC} from "../../fuzz/helpers/FuzzConstants.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {DataTypes} from "@bitmor/libraries/types/DataTypes.sol";
import {MockERC20} from "../../mock/MockERC20.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

/**
 * @title BTCVaultHandler
 * @author Bitmor Protocol
 * @notice Handler contract for invariant testing of BTCVault with real vault + multi-strategy
 * @dev Provides 8 handler functions with ghost state tracking for accounting invariants.
 *      Extends `BTCVaultFuzzTestBase` to get real `BTCVault` and `AaveTokenizedStrategy` backed by mocks.
 *      Multi-actor: rotates through `depositor`/`depositor2`/`depositor3`.
 *      All operations use `try/catch` for graceful failure on boundary conditions.
 *
 *      Fee tracking uses actual balance deltas on the fee recipient to avoid precision
 *      mismatches between Solady's 512-bit mulDivUp and 256-bit Solidity arithmetic.
 *      Yield tracking uses actual totalAssets deltas to handle virtual share rounding.
 *
 * @custom:audit-category Invariant Testing, ERC-4626 Compliance
 */
contract BTCVaultHandler is BTCVaultFuzzTestBase {
    // ============ Ghost State ============

    /// @dev Total cbBTC deposited across all handler operations (gross, before fees)
    uint256 public ghost_totalDeposited;

    /// @dev Total cbBTC withdrawn across all handler operations (net, what user receives)
    uint256 public ghost_totalWithdrawn;

    /// @dev Total entry fees collected (measured from fee recipient balance delta)
    uint256 public ghost_totalEntryFees;

    /// @dev Total exit fees collected (measured from fee recipient balance delta)
    uint256 public ghost_totalExitFees;

    /// @dev Total yield injected via `_simulateYield` (measured from totalAssets delta)
    uint256 public ghost_totalYieldInjected;

    /// @dev Total vault shares minted across all handler operations
    uint256 public ghost_totalSharesMinted;

    /// @dev Total vault shares redeemed/burned across all handler operations
    uint256 public ghost_totalSharesRedeemed;

    /// @dev Cumulative totalAssets delta from deposits (actual increase in vault.totalAssets)
    uint256 public ghost_netAssetsIn;

    /// @dev Cumulative totalAssets delta from withdrawals (actual decrease in vault.totalAssets)
    uint256 public ghost_netAssetsOut;

    // ============ Per-User Ghost State ============

    /// @dev Per-user total deposited amount (gross)
    mapping(address => uint256) public ghost_userDeposited;

    /// @dev Per-user total withdrawn amount (net)
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

    /// @dev Number of successful reallocate operations
    uint256 public ghost_reallocateCount;

    /// @dev Number of successful yield injection operations
    uint256 public ghost_yieldCount;

    // ============ Setup ============

    /// @notice Deploys vault with two strategies and configures queues
    function setUp() public override {
        super.setUp();
        _deploySecondStrategy();
        _addStrategy(address(strategy2), FC.SMALL_STRATEGY_CAP);

        // Update queues to include both strategies
        uint256[] memory queue = new uint256[](2);
        queue[0] = 0;
        queue[1] = 1;
        _updateSupplyQueue(queue);
        _updateWithdrawQueue(queue);
    }

    // ============ Internal Helpers ============

    /// @notice Returns the current cbBTC balance of the fee recipient
    function _feeRecipientBalance() internal view returns (uint256) {
        return IERC20(address(mockCbBTC)).balanceOf(feeRecipient);
    }

    // ============ Handler Functions ============

    /**
     * @notice Handler for vault deposit operations
     * @dev Funds the actor with cbBTC, approves vault, and deposits.
     *      Measures actual fee via fee recipient balance delta and actual assets via totalAssets delta.
     * @param amountSeed Seed for bounded deposit amount
     * @param actorSeed Seed for actor selection
     * @custom:audit-invariant INV-BTC-02, INV-BTC-05
     */
    function handler_deposit(uint256 amountSeed, uint256 actorSeed) external {
        address actor = _selectActor(actorSeed);
        uint256 amount = bound(amountSeed, FC.MIN_STRATEGY_DEPOSIT + 1000, FC.MAX_BTC_AMOUNT);

        _fundCbBTCAndApprove(actor, address(vault), amount);

        uint256 feeBalBefore = _feeRecipientBalance();
        uint256 assetsBefore = vault.totalAssets();
        uint256 supplyBefore = vault.totalSupply();

        vm.prank(actor);
        try vault.deposit(amount, actor) returns (uint256 shares) {
            uint256 actualFee = _feeRecipientBalance() - feeBalBefore;
            uint256 assetsAfter = vault.totalAssets();
            uint256 assetsDelta = assetsAfter > assetsBefore ? assetsAfter - assetsBefore : 0;

            ghost_totalDeposited += amount;
            ghost_totalSharesMinted += shares;
            ghost_totalEntryFees += actualFee;
            ghost_netAssetsIn += assetsDelta;
            ghost_userDeposited[actor] += amount;
            ghost_depositCount++;

            // Track dust shares burned by BTCVault._deposit() cleanup
            uint256 supplyAfter = vault.totalSupply();
            uint256 expectedSupply = supplyBefore + shares;
            if (expectedSupply > supplyAfter) {
                ghost_totalSharesRedeemed += expectedSupply - supplyAfter;
            }
        } catch {
            // Graceful failure
        }
    }

    /**
     * @notice Handler for vault mint operations
     * @dev Mints a bounded number of shares by depositing the required assets.
     *      Measures actual fee via fee recipient balance delta.
     * @param sharesSeed Seed for bounded shares to mint
     * @param actorSeed Seed for actor selection
     * @custom:audit-invariant INV-BTC-02, INV-BTC-05
     */
    function handler_mint(uint256 sharesSeed, uint256 actorSeed) external {
        address actor = _selectActor(actorSeed);
        uint256 shares = bound(sharesSeed, 1, 50e8);

        uint256 assetsNeeded = vault.previewMint(shares);
        if (assetsNeeded < FC.MIN_STRATEGY_DEPOSIT + 1000 || assetsNeeded > FC.MAX_BTC_AMOUNT) return;

        _fundCbBTCAndApprove(actor, address(vault), assetsNeeded);

        uint256 feeBalBefore = _feeRecipientBalance();
        uint256 assetsBefore = vault.totalAssets();
        uint256 supplyBefore = vault.totalSupply();

        vm.prank(actor);
        try vault.mint(shares, actor) returns (uint256 assetsUsed) {
            uint256 actualFee = _feeRecipientBalance() - feeBalBefore;
            uint256 assetsAfter = vault.totalAssets();
            uint256 assetsDelta = assetsAfter > assetsBefore ? assetsAfter - assetsBefore : 0;

            ghost_totalDeposited += assetsUsed;
            ghost_totalSharesMinted += shares;
            ghost_totalEntryFees += actualFee;
            ghost_netAssetsIn += assetsDelta;
            ghost_userDeposited[actor] += assetsUsed;
            ghost_mintCount++;

            // Track dust shares burned by BTCVault._deposit() cleanup
            uint256 supplyAfter = vault.totalSupply();
            uint256 expectedSupply = supplyBefore + shares;
            if (expectedSupply > supplyAfter) {
                ghost_totalSharesRedeemed += expectedSupply - supplyAfter;
            }
        } catch {
            // Graceful failure
        }
    }

    /**
     * @notice Handler for vault withdraw operations
     * @dev Withdraws a bounded portion of the actor's maxWithdraw.
     *      Measures actual fee via fee recipient balance delta.
     * @param assetsSeed Seed for bounded assets to withdraw
     * @param actorSeed Seed for actor selection
     * @custom:audit-invariant INV-BTC-02, INV-BTC-05
     */
    function handler_withdraw(uint256 assetsSeed, uint256 actorSeed) external {
        address actor = _selectActor(actorSeed);
        uint256 maxAssets = vault.maxWithdraw(actor);
        if (maxAssets == 0) return;

        uint256 assets = bound(assetsSeed, 1, maxAssets);

        uint256 feeBalBefore = _feeRecipientBalance();
        uint256 assetsBefore = vault.totalAssets();
        uint256 supplyBefore = vault.totalSupply();

        vm.prank(actor);
        try vault.withdraw(assets, actor, actor) returns (uint256 sharesBurned) {
            uint256 actualFee = _feeRecipientBalance() - feeBalBefore;
            uint256 assetsDelta = assetsBefore > vault.totalAssets() ? assetsBefore - vault.totalAssets() : 0;

            ghost_totalWithdrawn += assets;
            ghost_totalSharesRedeemed += sharesBurned;
            ghost_totalExitFees += actualFee;
            ghost_netAssetsOut += assetsDelta;
            ghost_userWithdrawn[actor] += assets;
            ghost_withdrawCount++;

            // Track dust shares burned by BTCVault._withdraw() cleanup
            uint256 supplyAfter = vault.totalSupply();
            if (supplyBefore > sharesBurned + supplyAfter) {
                ghost_totalSharesRedeemed += supplyBefore - sharesBurned - supplyAfter;
            }
        } catch {
            // Graceful failure
        }
    }

    /**
     * @notice Handler for vault redeem operations
     * @dev Redeems a bounded portion of the actor's shares.
     *      Measures actual fee via fee recipient balance delta.
     * @param sharesSeed Seed for bounded shares to redeem
     * @param actorSeed Seed for actor selection
     * @custom:audit-invariant INV-BTC-02, INV-BTC-06
     */
    function handler_redeem(uint256 sharesSeed, uint256 actorSeed) external {
        address actor = _selectActor(actorSeed);
        uint256 actorShares = vault.balanceOf(actor);
        if (actorShares == 0) return;

        uint256 shares = bound(sharesSeed, 1, actorShares);

        uint256 feeBalBefore = _feeRecipientBalance();
        uint256 assetsBefore = vault.totalAssets();
        uint256 supplyBefore = vault.totalSupply();

        vm.prank(actor);
        try vault.redeem(shares, actor, actor) returns (uint256 assetsReturned) {
            uint256 actualFee = _feeRecipientBalance() - feeBalBefore;
            uint256 assetsDelta = assetsBefore > vault.totalAssets() ? assetsBefore - vault.totalAssets() : 0;

            ghost_totalWithdrawn += assetsReturned;
            ghost_totalSharesRedeemed += shares;
            ghost_totalExitFees += actualFee;
            ghost_netAssetsOut += assetsDelta;
            ghost_userWithdrawn[actor] += assetsReturned;
            ghost_redeemCount++;

            // Track dust shares burned by BTCVault._withdraw() cleanup
            uint256 supplyAfter = vault.totalSupply();
            if (supplyBefore > shares + supplyAfter) {
                ghost_totalSharesRedeemed += supplyBefore - shares - supplyAfter;
            }
        } catch {
            // Graceful failure
        }
    }

    /**
     * @notice Handler for fund reallocation between strategies
     * @dev Moves a fraction of assets between strategies. Direction chosen by seed parity.
     *      Skips if source strategy has no assets.
     * @param amountSeed Seed for bounded reallocation amount and direction selection
     * @custom:audit-invariant INV-BTC-03
     */
    function handler_reallocate(uint256 amountSeed) external {
        uint256 total = vault.totalAssets();
        if (total == 0) return;

        uint256 s1Balance = vault.getAssetInStrategy(address(strategy1));
        uint256 s2Balance = vault.getAssetInStrategy(address(strategy2));

        // Pick direction based on seed parity
        bool s1ToS2 = (amountSeed % 2 == 0);
        uint256 srcBalance = s1ToS2 ? s1Balance : s2Balance;
        if (srcBalance == 0) return;

        uint256 moveAmount = bound(amountSeed, 1, srcBalance);

        DataTypes.Allocation[] memory allocations = new DataTypes.Allocation[](2);
        if (s1ToS2) {
            allocations[0] = DataTypes.Allocation({index: 0, amount: s1Balance - moveAmount});
            allocations[1] = DataTypes.Allocation({index: 1, amount: s2Balance + moveAmount});
        } else {
            allocations[0] = DataTypes.Allocation({index: 0, amount: s1Balance + moveAmount});
            allocations[1] = DataTypes.Allocation({index: 1, amount: s2Balance - moveAmount});
        }

        uint256 assetsBefore = vault.totalAssets();

        try this.doReallocate(allocations) {
            uint256 assetsAfter = vault.totalAssets();
            // Reallocations can lose assets through strategy share rounding
            if (assetsBefore > assetsAfter) {
                ghost_netAssetsOut += assetsBefore - assetsAfter;
            } else if (assetsAfter > assetsBefore) {
                ghost_netAssetsIn += assetsAfter - assetsBefore;
            }
            ghost_reallocateCount++;
        } catch {
            // Graceful failure
        }
    }

    /**
     * @notice External wrapper for reallocation to use with try/catch
     * @dev Must be `external` so `try this.doReallocate(...)` compiles. Not targeted by the fuzzer
     *      since `targetSelector` only lists `handler_*` functions.
     * @param allocations The reallocation instructions
     */
    function doReallocate(DataTypes.Allocation[] memory allocations) external {
        _reallocate(allocations);
    }

    /**
     * @notice Handler for yield simulation via aToken minting
     * @dev Simulates Aave yield accrual. Measures actual totalAssets delta.
     * @param yieldSeed Seed for bounded yield amount
     * @custom:audit-invariant INV-BTC-02
     */
    function handler_simulateYield(uint256 yieldSeed) external {
        uint256 yieldAmount = bound(yieldSeed, 0, 10e8);
        if (yieldAmount == 0 || vault.totalSupply() == 0) return;

        // Measure actual totalAssets change
        uint256 assetsBefore = vault.totalAssets();
        _simulateYield(yieldAmount);
        uint256 assetsAfter = vault.totalAssets();

        uint256 actualYield = assetsAfter > assetsBefore ? assetsAfter - assetsBefore : 0;
        ghost_totalYieldInjected += actualYield;
        ghost_netAssetsIn += actualYield;
        ghost_yieldCount++;
    }

    /**
     * @notice Handler for entry fee changes
     * @param feeSeed Seed for bounded fee value
     */
    function handler_setEntryFee(uint256 feeSeed) external {
        _setEntryFee(_boundFee(feeSeed));
    }

    /**
     * @notice Handler for exit fee changes
     * @param feeSeed Seed for bounded fee value
     */
    function handler_setExitFee(uint256 feeSeed) external {
        _setExitFee(_boundFee(feeSeed));
    }

    // ============ View Functions ============

    /// @notice Returns the total number of successful handler calls
    function ghost_totalCalls() external view returns (uint256) {
        return ghost_depositCount + ghost_redeemCount + ghost_withdrawCount + ghost_mintCount + ghost_reallocateCount
            + ghost_yieldCount;
    }

    /// @notice Returns the total number of deposit/mint/withdraw/redeem operations
    function ghost_totalOps() external view returns (uint256) {
        return ghost_depositCount + ghost_mintCount + ghost_withdrawCount + ghost_redeemCount;
    }

    /// @notice Exposes the internal `vault` for invariant test assertions
    function getVault() external view returns (BTCVault) {
        return vault;
    }

    /// @notice Exposes the internal `mockCbBTC` for invariant test assertions
    function getMockCbBTC() external view returns (MockERC20) {
        return mockCbBTC;
    }

    /// @notice Exposes the internal `feeRecipient` for invariant test assertions
    function getFeeRecipient() external view returns (address) {
        return feeRecipient;
    }
}
