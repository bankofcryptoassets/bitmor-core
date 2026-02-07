// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {USDCStrategyFuzzTestBase} from "../base/USDCStrategyFuzzTestBase.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";
import {USDCVault} from "@bitmor/vaults/usdc-vault/USDCVault.sol";
import {USDCStrategy} from "@bitmor/vaults/usdc-vault/USDCStrategy.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";

/**
 * @title USDCVaultEdgeCasesFuzzTest
 * @author Bitmor Protocol
 * @notice Edge-case fuzz tests for USDCVault and USDCStrategy (USDC-29 through USDC-40)
 * @dev Covers zero-amount reverts, pause guards, access control boundaries,
 *      strategy caller restrictions, and share-inflation resistance.
 *      Inherits `USDCStrategyFuzzTestBase` which deploys real `USDCVault` + `USDCStrategy`
 *      backed by mock Aave and Bitmor pools.
 */
contract USDCVaultEdgeCasesFuzzTest is USDCStrategyFuzzTestBase {
    // ============ Constants ============

    /// @dev Generous funding amount for approve-only scenarios
    uint256 internal constant GENEROUS_FUNDING = 100_000e6;

    /// @dev Minimum shares amount for mint fuzz bound
    uint256 internal constant MIN_SHARES = 1;

    /// @dev Maximum shares amount for mint fuzz bound
    uint256 internal constant MAX_SHARES = 1_000e6;

    // ============ USDC-29: Deposit reverts on zero amount ============

    /**
     * @notice Depositing zero assets must revert with `Errors.ZeroAmount()`
     * @dev The vault's `deposit` override explicitly checks for `assets == 0`
     * @custom:audit-property USDC-29: Deposit reverts when zero amount is provided
     * @custom:audit-category Input Validation
     * @custom:audit-severity High
     */
    function testFuzz_Deposit_RevertsWhenZeroAmount() public {
        // Arrange - fund depositor with some USDC and approve vault
        _fundUSDCAndApprove(depositor, address(vault), GENEROUS_FUNDING);

        // Assert + Act
        vm.expectRevert(Errors.ZeroAmount.selector);
        vm.prank(depositor);
        vault.deposit(0, depositor);
    }

    // ============ USDC-30: Deposit reverts when paused ============

    /**
     * @notice Depositing while the vault is paused must revert with `EnforcedPause()`
     * @dev All ERC-4626 entry points carry the `whenNotPaused` modifier
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property USDC-30: Deposit reverts when vault is paused
     * @custom:audit-category Pause Guard
     * @custom:audit-severity Critical
     */
    function testFuzz_Deposit_RevertsWhenPaused(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        // Arrange - pause vault before funding
        _pauseVault();

        // Fund and approve after pause
        _fundUSDCAndApprove(depositor, address(vault), depositAmount);

        // Assert + Act
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(depositor);
        vault.deposit(depositAmount, depositor);
    }

    // ============ USDC-31: Withdraw reverts when paused ============

    /**
     * @notice Withdrawing while the vault is paused must revert with `EnforcedPause()`
     * @dev Deposit occurs before pause so the user holds shares to attempt withdrawal
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property USDC-31: Withdraw reverts when vault is paused
     * @custom:audit-category Pause Guard
     * @custom:audit-severity Critical
     */
    function testFuzz_Withdraw_RevertsWhenPaused(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        // Arrange - deposit while unpaused
        _depositToVault(depositor, depositAmount);

        // Pause the vault
        _pauseVault();

        // Assert + Act
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(depositor);
        vault.withdraw(depositAmount, depositor, depositor);
    }

    // ============ USDC-32: Mint reverts when paused ============

    /**
     * @notice Minting shares while the vault is paused must revert with `EnforcedPause()`
     * @param sharesSeed Seed for bounded shares amount
     * @custom:audit-property USDC-32: Mint reverts when vault is paused
     * @custom:audit-category Pause Guard
     * @custom:audit-severity Critical
     */
    function testFuzz_Mint_RevertsWhenPaused(uint256 sharesSeed) public {
        uint256 sharesToMint = bound(sharesSeed, MIN_SHARES, MAX_SHARES);

        // Arrange - pause vault
        _pauseVault();

        // Fund depositor with generous amount and approve
        _fundUSDCAndApprove(depositor, address(vault), GENEROUS_FUNDING);

        // Assert + Act
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(depositor);
        vault.mint(sharesToMint, depositor);
    }

    // ============ USDC-33: Redeem reverts when paused ============

    /**
     * @notice Redeeming shares while the vault is paused must revert with `EnforcedPause()`
     * @dev Deposit occurs before pause so the user holds shares to attempt redemption
     * @param depositSeed Seed for bounded deposit amount
     * @custom:audit-property USDC-33: Redeem reverts when vault is paused
     * @custom:audit-category Pause Guard
     * @custom:audit-severity Critical
     */
    function testFuzz_Redeem_RevertsWhenPaused(uint256 depositSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);

        // Arrange - deposit while unpaused to obtain shares
        uint256 shares = _depositToVault(depositor, depositAmount);

        // Pause the vault
        _pauseVault();

        // Assert + Act
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(depositor);
        vault.redeem(shares, depositor, depositor);
    }

    // ============ USDC-34: Withdraw reverts when exceeding balance ============

    /**
     * @notice Withdrawing more than the deposited amount must revert
     * @param depositSeed Seed for bounded deposit amount
     * @param excessSeed Seed for bounded excess amount added on top
     * @custom:audit-property USDC-34: Withdraw reverts when amount exceeds balance
     * @custom:audit-category Input Validation
     * @custom:audit-severity High
     */
    function testFuzz_Withdraw_RevertsWhenExceedsBalance(uint256 depositSeed, uint256 excessSeed) public {
        uint256 depositAmount = _boundUsdcAmount(depositSeed);
        uint256 excess = bound(excessSeed, 1, FC.MAX_USDC_AMOUNT);

        // Arrange - deposit a known amount
        _depositToVault(depositor, depositAmount);

        uint256 withdrawAmount = depositAmount + excess;

        // Assert + Act
        vm.expectRevert();
        vm.prank(depositor);
        vault.withdraw(withdrawAmount, depositor, depositor);
    }

    // ============ USDC-35: Strategy supply reverts when caller is not vault ============

    /**
     * @notice Calling `strategy.supply()` from a non-vault address must revert
     * @dev The `onlyVault` modifier restricts supply to the vault contract
     * @param amountSeed Seed for bounded supply amount
     * @custom:audit-property USDC-35: Strategy supply reverts when caller is not the vault
     * @custom:audit-category Access Control
     * @custom:audit-severity Critical
     */
    function testFuzz_Strategy_Supply_RevertsWhenNotVault(uint256 amountSeed) public {
        uint256 amount = _boundUsdcAmount(amountSeed);
        address randomCaller = makeAddr("randomCaller");

        // Assert + Act
        vm.expectRevert(USDCStrategy.USDCStrategy__NotVault.selector);
        vm.prank(randomCaller);
        strategy.supply(amount);
    }

    // ============ USDC-36: Strategy withdraw reverts when caller is not vault ============

    /**
     * @notice Calling `strategy.withdraw()` from a non-vault address must revert
     * @dev The `onlyVault` modifier restricts withdraw to the vault contract
     * @param amountSeed Seed for bounded withdraw amount
     * @custom:audit-property USDC-36: Strategy withdraw reverts when caller is not the vault
     * @custom:audit-category Access Control
     * @custom:audit-severity Critical
     */
    function testFuzz_Strategy_Withdraw_RevertsWhenNotVault(uint256 amountSeed) public {
        uint256 amount = _boundUsdcAmount(amountSeed);
        address randomCaller = makeAddr("randomCaller");

        // Assert + Act
        vm.expectRevert(USDCStrategy.USDCStrategy__NotVault.selector);
        vm.prank(randomCaller);
        strategy.withdraw(amount);
    }

    // ============ USDC-37: Strategy supply works at any allocation ============

    /**
     * @notice Strategy supply must succeed regardless of the current Aave allocation setting
     * @dev Verifies that `totalAssets` is positive after supplying at any valid allocation
     * @param amountSeed Seed for bounded supply amount
     * @param allocationSeed Seed for bounded allocation in basis points
     * @custom:audit-property USDC-37: Strategy supply works at any allocation setting
     * @custom:audit-category Allocation Robustness
     * @custom:audit-severity High
     */
    function testFuzz_Supply_WorksAtAnyAllocation(uint256 amountSeed, uint256 allocationSeed) public {
        uint256 amount = _boundUsdcAmount(amountSeed);
        uint256 allocationBps = _boundAllocationBps(allocationSeed);

        // Arrange - set allocation and fund vault with USDC
        _setAllocation(allocationBps);
        mockUSDC.mint(address(vault), amount);

        // Act - supply through vault
        vm.prank(address(vault));
        strategy.supply(amount);

        // Assert - strategy should report positive total assets
        uint256 totalBalance = strategy.totalAssets();
        assertGt(totalBalance, 0, "strategy totalAssets should be positive after supply");
    }

    // ============ USDC-38: Shares never exceed deposit (inflation resistance) ============

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

        // Act - deposit and capture shares
        uint256 shares = _depositToVault(depositor, depositAmount);

        // Assert - converting shares back to assets must not exceed deposit
        uint256 assetsFromShares = vault.convertToAssets(shares);
        assertLe(assetsFromShares, depositAmount, "convertToAssets(shares) should never exceed original deposit amount");
    }

    // ============ USDC-39: reallocateAssets(uint256) reverts when caller is not BLP ============

    /**
     * @notice `reallocateAssets(uint256)` must revert with `UnauthorizedCaller` when called by
     *         an address that holds the UVA role but is not the Bitmor Lending Pool
     * @dev The function has both a `restricted` modifier (AccessManager role check) and an
     *      explicit `msg.sender != i_blp` guard. A caller with UVA role but without BLP identity
     *      passes the role check but fails the internal guard.
     * @param amountSeed Seed for bounded reallocation amount
     * @custom:audit-property USDC-39: reallocateAssets(uint256) reverts when caller is not BLP
     * @custom:audit-category Access Control
     * @custom:audit-severity Critical
     */
    function testFuzz_ReallocateWithAmount_RevertsWhenNotBLP(uint256 amountSeed) public {
        uint256 depositAmount = _boundUsdcAmount(amountSeed);

        // Arrange - deposit so there are assets to reallocate
        _depositToVault(depositor, depositAmount);

        uint256 amount = bound(amountSeed, 1, depositAmount);
        address randomCaller = makeAddr("notBLP");

        // Grant UVA role to the random caller with no delay
        manager.grantRole(UVA_ID(), randomCaller, 0);

        // Assert + Act - caller has UVA role but is not BLP, so internal check fails
        vm.expectRevert(abi.encodeWithSelector(Errors.UnauthorizedCaller.selector));
        vm.prank(randomCaller);
        vault.reallocateAssets(amount);
    }

    // ============ USDC-40: setStrategy reverts on zero address ============

    /**
     * @notice `setStrategy(address(0))` must revert with `Errors.ZeroAddress()`
     * @dev The function guards against setting a zero-address strategy
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
}
