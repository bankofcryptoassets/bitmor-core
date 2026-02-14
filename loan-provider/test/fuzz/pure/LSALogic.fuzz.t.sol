// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {LoanVault} from "@bitmor/protocol/LoanVault.sol";
import {LSALogicHarness} from "../../harness/LSALogicHarness.sol";
import {MockBTCVault} from "../../mock/MockBTCVault.sol";
import {MockERC20} from "../../mock/MockERC20.sol";
import {MockAToken} from "../../mock/MockAToken.sol";
import {MockVariableDebtToken} from "../../mock/MockVariableDebtToken.sol";
import {MockBitmorLendingPool} from "../../mock/MockBitmorLendingPool.sol";
import {MockAddressesProvider} from "../../mock/MockAddressesProvider.sol";
import {MockPriceOracle} from "../../mock/MockPriceOracle.sol";
import {MockInterestRateStrategy} from "../../mock/MockInterestRateStrategy.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";

/**
 * @title LSALogicFuzzTest
 * @author Bitmor Protocol
 * @notice Stateless fuzz tests for `LSALogic.redeemBTC()` and `LSALogic.withdrawCollateral()`
 * @dev Tests 7 properties covering slippage checks, token flow conservation,
 *      monotonic share redemption, zero/excessive slippage edge cases,
 *      and withdrawal flow conservation.
 *
 * @custom:audit-category Financial Safety, Token Accounting, Edge Cases
 */
contract LSALogicFuzzTest is Test {
    // ============ Constants ============

    /// @dev Standard slippage for clean-vault tests: 95% (9500 BPS)
    uint256 private constant STANDARD_SLIPPAGE = 95_00;

    /// @dev Basis points denominator
    uint256 private constant BPS_DENOMINATOR = 100_00;

    /// @dev Default deposit for redeemBTC tests: 100 BTC
    uint256 private constant DEFAULT_DEPOSIT = 100e8;

    // ============ Infrastructure ============

    /// @notice Harness exposing LSALogic internal functions
    LSALogicHarness public harness;

    /// @notice Mock cbBTC token (underlying for the BTC vault)
    MockERC20 public cbBTC;

    /// @notice Mock BTC vault (ERC-4626, wraps cbBTC into bvBTC shares)
    MockBTCVault public btcVault;

    /// @notice LoanVault instance (LSA) owned by the harness
    LoanVault public vault;

    /// @notice Recipient address for redeemed/withdrawn tokens
    address public recipient;

    // ============ withdrawCollateral Infrastructure ============

    /// @notice Mock Bitmor lending pool for withdrawCollateral tests
    MockBitmorLendingPool public mockPool;

    /// @notice Mock aToken for bvBTC in the lending pool
    MockAToken public aTokenBvBTC;

    // ============ Setup ============

    function setUp() public {
        recipient = makeAddr("recipient");

        // Deploy tokens
        cbBTC = new MockERC20("Coinbase BTC", "cbBTC", 8);

        // Deploy BTC vault
        btcVault = new MockBTCVault(address(cbBTC), "Bitmor BTC Vault", "bvBTC", 8);

        // Deploy harness (will be the vault owner)
        harness = new LSALogicHarness();

        // Deploy vault owned by harness
        vault = new LoanVault();
        vault.initialize(address(harness), makeAddr("borrower"));

        // Deploy lending pool infrastructure for withdrawCollateral test
        _deployWithdrawalInfrastructure();
    }

    /// @notice Deploys mock lending pool infrastructure needed for withdrawCollateral tests
    function _deployWithdrawalInfrastructure() internal {
        MockPriceOracle oracle = new MockPriceOracle(address(btcVault), address(cbBTC));
        MockAddressesProvider provider = new MockAddressesProvider(address(0), address(oracle), address(this));

        mockPool = new MockBitmorLendingPool(address(provider));
        provider.setLendingPool(address(mockPool));

        // Deploy aToken for bvBTC (underlying = bvBTC, pool = mockPool)
        aTokenBvBTC = new MockAToken("aToken bvBTC", "abvBTC", 8, address(btcVault), address(mockPool));

        // Deploy a debt token (required for initReserveWithStrategy even though unused for withdraw)
        MockVariableDebtToken debtToken =
            new MockVariableDebtToken("Debt bvBTC", "dbvBTC", 8, address(btcVault), address(mockPool));

        // Deploy minimal interest rate strategy
        MockInterestRateStrategy irs = new MockInterestRateStrategy();

        // Initialize bvBTC reserve in lending pool
        mockPool.initReserveWithStrategy(address(btcVault), address(aTokenBvBTC), address(debtToken), address(irs));
    }

    // ============ Helpers ============

    /**
     * @notice Deposits cbBTC into the BTC vault, sending bvBTC shares to the LSA
     * @param amount Amount of cbBTC to deposit
     * @return shares Number of bvBTC shares received by the LSA
     */
    function _depositToVault(uint256 amount) internal returns (uint256 shares) {
        cbBTC.mint(address(this), amount);
        cbBTC.approve(address(btcVault), amount);
        shares = btcVault.deposit(amount, address(vault));
    }

    /**
     * @notice Deposits cbBTC into the BTC vault with additional yield to create non-1:1 ratio
     * @param depositAmount Amount of cbBTC to deposit
     * @param yieldAmount Extra cbBTC minted directly to vault (simulates yield accrual)
     * @return shares Number of bvBTC shares received by the LSA
     */
    function _depositToVaultWithYield(uint256 depositAmount, uint256 yieldAmount) internal returns (uint256 shares) {
        shares = _depositToVault(depositAmount);
        if (yieldAmount > 0) {
            cbBTC.mint(address(btcVault), yieldAmount);
        }
    }

    // ============ Tests — redeemBTC ============

    /**
     * @notice With real ERC4626 math at varying totalAssets/totalSupply ratios, the slippage
     *         check must always pass for clean vaults (where actual redeem output equals the
     *         estimated amount). This stresses Solady's `mulDiv` at extreme conversion ratios.
     * @dev Deposits cbBTC then adds yield to create varying share/asset ratios. Since no
     *      manipulation occurs between estimate and redeem, actual == estimated and the
     *      95% slippage check always passes.
     * @param depositAmount Amount of cbBTC to deposit (creates shares)
     * @param yieldAmount Extra cbBTC added to vault (changes the exchange rate)
     * @param sharesSeed Seed for bounded shares to redeem
     * @custom:audit-property Slippage passes at varying vault ratios
     * @custom:audit-category Financial Safety
     * @custom:audit-severity High
     */
    function testFuzz_redeemBTC_SlippagePassesWithVaryingRatios(
        uint256 depositAmount,
        uint256 yieldAmount,
        uint256 sharesSeed
    ) public {
        depositAmount = bound(depositAmount, 1e5, 100e8);
        yieldAmount = bound(yieldAmount, 0, depositAmount);

        uint256 sharesReceived = _depositToVaultWithYield(depositAmount, yieldAmount);

        uint256 sharesToRedeem = bound(sharesSeed, 1, sharesReceived);

        // Clean vault: actual redeem == convertToAssets, so 95% slippage always passes
        uint256 assetsReceived =
            harness.exposed_redeemBTC(address(vault), address(btcVault), sharesToRedeem, recipient, STANDARD_SLIPPAGE);

        assertGt(assetsReceived, 0, "assets received must be positive");
    }

    /**
     * @notice When the vault returns fewer assets than the slippage minimum (computed from
     *         `convertToAssets`), `redeemBTC` must revert with
     *         `SlippageExceededWhileConvertingToAssets`.
     * @dev Tests the comparison operator direction and operand order in the slippage check.
     *      Uses MockBTCVault.setMockRedeemReturn() to simulate shortfall.
     * @param sharesSeed Seed for bounded shares to redeem
     * @param shortfallSeed Seed for bounded shortfall (return < minimum)
     * @custom:audit-property Slippage check rejects below-minimum returns
     * @custom:audit-category Financial Safety
     * @custom:audit-severity Critical
     */
    function testFuzz_redeemBTC_RevertsWhenBelowMinimum(uint256 sharesSeed, uint256 shortfallSeed) public {
        uint256 sharesReceived = _depositToVault(DEFAULT_DEPOSIT);

        uint256 sharesToRedeem = bound(sharesSeed, 1, sharesReceived);

        uint256 estimated = btcVault.convertToAssets(sharesToRedeem);
        uint256 minimum = (estimated * STANDARD_SLIPPAGE) / BPS_DENOMINATOR;

        // Need minimum > 0 to trigger meaningful slippage check
        vm.assume(minimum > 0);

        uint256 mockReturn = bound(shortfallSeed, 0, minimum - 1);

        btcVault.setMockRedeemReturn(mockReturn);

        vm.expectRevert(Errors.SlippageExceededWhileConvertingToAssets.selector);
        harness.exposed_redeemBTC(address(vault), address(btcVault), sharesToRedeem, recipient, STANDARD_SLIPPAGE);
    }

    /**
     * @notice When slippage tolerance is set to 0 BPS, the minimum receivable is 0, which
     *         means any return — including zero — passes the slippage check.
     * @dev Documents a missing input validation: zero slippage provides no protection at all.
     *      The formula `minimumReceivable = estimated * 0 / 10000 = 0`, so any `assetsReceived >= 0`
     *      is always true.
     * @param sharesSeed Seed for bounded shares to redeem
     * @param returnSeed Seed for bounded mock return value
     * @custom:audit-property Zero slippage accepts any return
     * @custom:audit-category Edge Cases
     * @custom:audit-severity Medium
     */
    function testFuzz_redeemBTC_ZeroSlippageAcceptsAnyReturn(uint256 sharesSeed, uint256 returnSeed) public {
        uint256 sharesReceived = _depositToVault(DEFAULT_DEPOSIT);

        uint256 sharesToRedeem = bound(sharesSeed, 1, sharesReceived);
        uint256 mockReturn = bound(returnSeed, 0, DEFAULT_DEPOSIT);

        btcVault.setMockRedeemReturn(mockReturn);

        // Slippage = 0 means minimumReceivable = 0, so any return passes
        uint256 assetsReceived =
            harness.exposed_redeemBTC(address(vault), address(btcVault), sharesToRedeem, recipient, 0);

        assertEq(assetsReceived, mockReturn, "should return whatever the vault gives with zero slippage");
    }

    /**
     * @notice When slippage is set above 10000 BPS (> 100%), the computed minimum exceeds
     *         the estimated output, so redemption always reverts even when the vault returns
     *         the correct amount.
     * @dev Documents this edge case behavior: `minimumReceivable = estimated * (>10000) / 10000 > estimated`,
     *      and actual redeem can only return <= estimated for a clean vault.
     * @param sharesSeed Seed for bounded shares to redeem
     * @param slippageSeed Seed for bounded slippage above 100%
     * @custom:audit-property Slippage above 100% always reverts
     * @custom:audit-category Edge Cases
     * @custom:audit-severity Medium
     */
    function testFuzz_redeemBTC_RevertsWhenSlippageExceedsBPS(uint256 sharesSeed, uint256 slippageSeed) public {
        uint256 sharesReceived = _depositToVault(DEFAULT_DEPOSIT);

        // Bound sharesToRedeem >= BPS_DENOMINATOR so that floor(estimated * slippage / 10000) > estimated
        // for any slippage > 10000. With small shares, integer truncation can make minimum == estimated.
        uint256 sharesToRedeem = bound(sharesSeed, BPS_DENOMINATOR, sharesReceived);
        uint256 slippage = bound(slippageSeed, BPS_DENOMINATOR + 1, 2 * BPS_DENOMINATOR);

        // With clean vault, actual redeem <= estimated. But minimum > estimated, so always reverts.
        vm.expectRevert(Errors.SlippageExceededWhileConvertingToAssets.selector);
        harness.exposed_redeemBTC(address(vault), address(btcVault), sharesToRedeem, recipient, slippage);
    }

    /**
     * @notice After redemption, the recipient's cbBTC gain must equal the vault's cbBTC loss,
     *         which must equal the function's return value. The LSA must hold zero cbBTC
     *         afterward — nothing stuck anywhere in the flow.
     * @dev Catches fund locking where tokens remain stuck in the LSA after the redeem completes.
     *      cbBTC flows: btcVault -> recipient (direct transfer in ERC4626.redeem).
     * @param depositSeed Seed for bounded deposit amount
     * @param sharesSeed Seed for bounded shares to redeem
     * @custom:audit-property Token flow conservation on redeem
     * @custom:audit-category Token Accounting
     * @custom:audit-severity Critical
     */
    function testFuzz_redeemBTC_TokenFlowConservation(uint256 depositSeed, uint256 sharesSeed) public {
        uint256 depositAmount = bound(depositSeed, 1e5, 100e8);

        uint256 sharesReceived = _depositToVault(depositAmount);
        uint256 sharesToRedeem = bound(sharesSeed, 1, sharesReceived);

        uint256 recipientBefore = cbBTC.balanceOf(recipient);
        uint256 vaultCbBTCBefore = cbBTC.balanceOf(address(btcVault));

        uint256 assetsReceived =
            harness.exposed_redeemBTC(address(vault), address(btcVault), sharesToRedeem, recipient, STANDARD_SLIPPAGE);

        uint256 recipientAfter = cbBTC.balanceOf(recipient);
        uint256 vaultCbBTCAfter = cbBTC.balanceOf(address(btcVault));

        // Recipient's gain equals return value
        assertEq(recipientAfter - recipientBefore, assetsReceived, "recipient gain must equal return value");

        // BTC vault's cbBTC loss equals return value
        assertEq(vaultCbBTCBefore - vaultCbBTCAfter, assetsReceived, "vault cbBTC loss must equal return value");

        // LSA must hold zero cbBTC (assets go directly from btcVault to recipient)
        assertEq(cbBTC.balanceOf(address(vault)), 0, "LSA must hold zero cbBTC after redeem");
    }

    /**
     * @notice Redeeming more shares must always yield at least as many assets as redeeming
     *         fewer shares. This is a fundamental economic property of ERC4626 vaults.
     * @dev Uses `vm.snapshotState` to compare two different redemption amounts on identical
     *      vault state. Tests Solady's mulDiv monotonicity at various share/asset ratios.
     * @param shares1Seed Seed for bounded smaller share amount
     * @param shares2Seed Seed for bounded larger share amount
     * @custom:audit-property Monotonic share-to-asset conversion
     * @custom:audit-category Financial Safety
     * @custom:audit-severity High
     */
    function testFuzz_redeemBTC_MonotonicShareRedemption(uint256 shares1Seed, uint256 shares2Seed) public {
        uint256 sharesReceived = _depositToVault(DEFAULT_DEPOSIT);

        // Ensure shares1 < shares2 and both valid
        uint256 shares1 = bound(shares1Seed, 1, sharesReceived - 1);
        uint256 shares2 = bound(shares2Seed, shares1 + 1, sharesReceived);

        // Snapshot before first redeem
        uint256 snapId = vm.snapshotState();

        // Redeem fewer shares
        uint256 assets1 =
            harness.exposed_redeemBTC(address(vault), address(btcVault), shares1, recipient, STANDARD_SLIPPAGE);

        // Revert and redeem more shares on identical state
        vm.revertToState(snapId);

        uint256 assets2 =
            harness.exposed_redeemBTC(address(vault), address(btcVault), shares2, recipient, STANDARD_SLIPPAGE);

        assertGe(assets2, assets1, "more shares redeemed must yield at least as many assets");
    }

    // ============ Tests — withdrawCollateral ============

    /**
     * @notice The amount withdrawn from the lending pool must exactly equal what was
     *         originally deposited, and the recipient must receive all of it. The LSA must
     *         hold zero collateral afterward — nothing left behind.
     * @dev Tests the pool.withdraw(MAX_U256) path. Deposits bvBTC into the mock lending pool
     *      on behalf of the LSA, then withdraws through the harness. Verifies token flow:
     *      pool -> recipient with nothing stuck in the LSA.
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property Withdrawal token flow conservation
     * @custom:audit-category Token Accounting
     * @custom:audit-severity Critical
     */
    function testFuzz_withdrawCollateral_TokenFlowConservation(uint256 depositSeed) public {
        uint256 depositAmount = bound(depositSeed, 1e5, 100e8);

        // Step 1: Get bvBTC shares into the test contract (not the vault)
        cbBTC.mint(address(this), depositAmount);
        cbBTC.approve(address(btcVault), depositAmount);
        uint256 bvBTCShares = btcVault.deposit(depositAmount, address(this));

        // Step 2: Deposit bvBTC into lending pool on behalf of the vault (LSA)
        // pool.deposit transfers bvBTC from msg.sender (this) to aToken address,
        // and mints aTokens to onBehalfOf (vault)
        btcVault.approve(address(mockPool), bvBTCShares);
        mockPool.deposit(address(btcVault), bvBTCShares, address(vault), 0);

        // Verify: vault now has aTokens, aToken address holds bvBTC
        uint256 aTokenBalance = aTokenBvBTC.balanceOf(address(vault));
        assertEq(aTokenBalance, bvBTCShares, "vault must hold aTokens after deposit");

        uint256 recipientBefore = btcVault.balanceOf(recipient);

        // Step 3: Withdraw all collateral through harness
        uint256 amountWithdrawn =
            harness.exposed_withdrawCollateral(address(vault), address(mockPool), address(btcVault), recipient);

        // Verify: withdrawn amount equals deposited amount
        assertEq(amountWithdrawn, bvBTCShares, "withdrawn amount must equal deposited amount");

        // Verify: recipient received all bvBTC
        uint256 recipientAfter = btcVault.balanceOf(recipient);
        assertEq(recipientAfter - recipientBefore, bvBTCShares, "recipient must receive all withdrawn bvBTC");

        // Verify: LSA holds zero aTokens
        assertEq(aTokenBvBTC.balanceOf(address(vault)), 0, "LSA must hold zero aTokens after withdrawal");

        // Verify: LSA holds zero bvBTC (it went directly to recipient, not through LSA)
        assertEq(btcVault.balanceOf(address(vault)), 0, "LSA must hold zero bvBTC after withdrawal");
    }
}
