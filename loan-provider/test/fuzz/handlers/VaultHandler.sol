// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {FuzzTestBase} from "../base/FuzzTestBase.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";
import {MockBTCVault} from "../../mock/MockBTCVault.sol";

/**
 * @title VaultHandler
 * @author Bitmor Protocol
 * @notice Handler contract for stateful fuzz testing of BTCVault and USDCVault
 * @dev Tracks deposits and withdrawals for invariant verification
 */
contract VaultHandler is FuzzTestBase {
    // ============ Vault Infrastructure ============

    /// @dev Mock BTC vault for testing
    MockBTCVault public mockBTCVault;

    /// @dev Standard test user
    address public user;

    // ============ State Tracking ============

    /// @dev Total BTC deposited across all operations
    uint256 public totalBtcDeposited;

    /// @dev Total BTC withdrawn across all operations
    uint256 public totalBtcWithdrawn;

    /// @dev Total shares minted
    uint256 public totalSharesMinted;

    /// @dev Total shares redeemed
    uint256 public totalSharesRedeemed;

    /// @dev Counter for deposit operations
    uint256 public depositCount;

    /// @dev Counter for withdraw operations
    uint256 public withdrawCount;

    /// @dev Mapping of user to deposited amount
    mapping(address => uint256) public userDeposits;

    // ============ Setup ============

    function setUp() public override {
        super.setUp();

        user = makeAddr("vaultUser");

        // Deploy BTCVault that wraps cbBTC -> bvBTC shares
        vm.startPrank(admin);
        mockBTCVault = new MockBTCVault(
            address(mockCbBTC),
            "Bitmor BTC Vault",
            "bvBTC",
            8 // Same decimals as cbBTC
        );
        vm.stopPrank();
    }

    // ============ BTC Vault Handlers ============

    /**
     * @notice Handler for BTC vault deposit
     * @param amountSeed Seed for deposit amount
     */
    function handler_btcDeposit(uint256 amountSeed) external {
        uint256 amount = _boundBtcAmount(amountSeed);

        // Fund user
        _fundCbBTCAndApprove(user, address(mockBTCVault), amount);

        vm.prank(user);
        try mockBTCVault.deposit(amount, user) returns (uint256 shares) {
            totalBtcDeposited += amount;
            totalSharesMinted += shares;
            userDeposits[user] += amount;
            depositCount++;
        } catch {
            // Graceful failure
        }
    }

    /**
     * @notice Handler for BTC vault withdrawal
     * @param sharesSeed Seed for shares to redeem
     */
    function handler_btcWithdraw(uint256 sharesSeed) external {
        uint256 userShares = mockBTCVault.balanceOf(user);
        if (userShares == 0) return;

        uint256 shares = bound(sharesSeed, 1, userShares);

        vm.prank(user);
        try mockBTCVault.redeem(shares, user, user) returns (uint256 assets) {
            totalBtcWithdrawn += assets;
            totalSharesRedeemed += shares;
            withdrawCount++;
        } catch {
            // Graceful failure
        }
    }

    /**
     * @notice Handler for BTC vault mint (shares-based deposit)
     * @param sharesSeed Seed for shares to mint
     */
    function handler_btcMint(uint256 sharesSeed) external {
        uint256 shares = bound(sharesSeed, 1, FC.MAX_BTC_AMOUNT);

        // Preview assets needed
        uint256 assets = mockBTCVault.previewMint(shares);
        if (assets == 0 || assets > FC.MAX_BTC_AMOUNT) return;

        // Fund user
        _fundCbBTCAndApprove(user, address(mockBTCVault), assets);

        vm.prank(user);
        try mockBTCVault.mint(shares, user) returns (uint256 assetsUsed) {
            totalBtcDeposited += assetsUsed;
            totalSharesMinted += shares;
            depositCount++;
        } catch {
            // Graceful failure
        }
    }

    /**
     * @notice Handler for BTC vault withdraw (assets-based withdrawal)
     * @param assetsSeed Seed for assets to withdraw
     */
    function handler_btcWithdrawAssets(uint256 assetsSeed) external {
        uint256 maxWithdraw = mockBTCVault.maxWithdraw(user);
        if (maxWithdraw == 0) return;

        uint256 assets = bound(assetsSeed, 1, maxWithdraw);

        vm.prank(user);
        try mockBTCVault.withdraw(assets, user, user) returns (uint256 shares) {
            totalBtcWithdrawn += assets;
            totalSharesRedeemed += shares;
            withdrawCount++;
        } catch {
            // Graceful failure
        }
    }

    // ============ View Functions ============

    /**
     * @notice Returns net BTC flow (deposited - withdrawn)
     */
    function getNetBtcFlow() external view returns (int256) {
        return int256(totalBtcDeposited) - int256(totalBtcWithdrawn);
    }

    /**
     * @notice Returns net shares flow (minted - redeemed)
     */
    function getNetSharesFlow() external view returns (int256) {
        return int256(totalSharesMinted) - int256(totalSharesRedeemed);
    }
}
