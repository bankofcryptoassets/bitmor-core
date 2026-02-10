// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {IntegrationTestBase} from "../base/IntegrationTestBase.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";
import {AaveTokenizedStrategy} from "@btcVault/TokenizedStrategy/AaveTokenizedStrategy.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

/// @title VaultStrategyTest
/// @notice Integration tests for BTCVault and USDCVault with real strategies
contract VaultStrategyTest is IntegrationTestBase {
    function setUp() public override {
        super.setUp();
        _setupTestUser();
    }

    // ============ Vault Asset Configuration ============

    function test_BTCVault_HasCorrectAsset() public view {
        assertEq(address(btcVault.asset()), address(cbBTC), "BTCVault asset should be cbBTC");
    }

    function test_USDCVault_HasCorrectAsset() public view {
        assertEq(address(usdcVault.asset()), address(usdc), "USDCVault asset should be USDC");
    }

    // ============ Vault Deposits via Loan ============

    /// @notice After loan init, BTCVault should hold collateral via strategy
    function test_BTCVault_DepositViaLoanInit() public {
        uint256 btcVaultTotalBefore = btcVault.totalAssets();

        address lsa = _createStandardLoan();
        assertTrue(lsa != address(0), "LSA should be deployed");

        uint256 btcVaultTotalAfter = btcVault.totalAssets();
        assertGt(btcVaultTotalAfter, btcVaultTotalBefore, "BTCVault totalAssets should increase after loan init");
    }

    // ============ Direct Vault Deposits ============

    /// @notice Direct USDC deposit into USDCVault should mint shares
    /// @dev User already funded with TC.USER_USDC_BALANCE by `_setupTestUser()` - no additional minting needed
    function test_USDCVault_Deposit_ReceivesShares() public {
        uint256 depositAmount = TC.POOL_DEPOSIT_AMOUNT; // 100k USDC

        vm.prank(testUser);
        IERC20(address(usdc)).approve(address(usdcVault), depositAmount);

        vm.prank(testUser);
        uint256 shares = usdcVault.deposit(depositAmount, testUser);

        assertGt(shares, 0, "should receive shares for deposit");
        assertEq(usdcVault.balanceOf(testUser), shares, "user balance should match minted shares");
    }

    // ============ Strategy Configuration ============

    function test_AaveTokenizedStrategy_YieldSource() public view {
        address strategy = config.getAaveTokenizedStrategy();
        AaveTokenizedStrategy ats = AaveTokenizedStrategy(strategy);
        assertEq(ats.i_yieldSource(), aaveV3Pool, "strategy yield source should be external Aave pool");
        assertEq(ats.i_vault(), address(btcVault), "strategy vault should be BTCVault");
    }
}
