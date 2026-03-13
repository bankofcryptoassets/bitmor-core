// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LoanVault} from "@bitmor/protocol/LoanVault.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {MockERC20} from "../../mock/MockERC20.sol";
import {MockReturnTarget} from "../../mock/LoanVaultMocks.sol";

/**
 * @title LoanVaultFuzzTest
 * @author Bitmor Protocol
 * @notice Stateless fuzz tests for `LoanVault.sol`
 * @dev Tests 3 properties covering token transfer conservation, re-initialization
 *      prevention via self-call, and state invariant preservation after execute().
 *
 * @custom:audit-category Token Accounting, Access Control, Storage Integrity
 */
contract LoanVaultFuzzTest is Test {
    // ============ Infrastructure ============

    LoanVault public vault;
    MockERC20 public token;
    MockReturnTarget public target;

    address public recipient;

    // ============ Setup ============

    function setUp() public {
        recipient = makeAddr("recipient");

        LoanVault impl = new LoanVault();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl), abi.encodeCall(LoanVault.initialize, (address(this), makeAddr("borrower")))
        );
        vault = LoanVault(payable(address(proxy)));

        token = new MockERC20("Test Token", "TKN", 18);
        target = new MockReturnTarget();
    }

    // ============ Tests ============

    /**
     * @notice When transferring tokens out of a vault, the vault's balance decrease must
     *         exactly equal the recipient's balance increase. The total token count across
     *         both addresses must be conserved — no tokens created or destroyed.
     * @dev Catches token leak or creation from thin air in the safeTransfer wrapper.
     * @param mintAmount Amount of tokens to mint to the vault
     * @param transferAmount Amount of tokens to transfer out (bounded to mintAmount)
     * @custom:audit-property Token transfer value conservation
     * @custom:audit-category Token Accounting
     * @custom:audit-severity Critical
     */
    function testFuzz_transferToken_ConservesValue(uint256 mintAmount, uint256 transferAmount) public {
        mintAmount = bound(mintAmount, 1, type(uint128).max);
        transferAmount = bound(transferAmount, 1, mintAmount);

        token.mint(address(vault), mintAmount);

        uint256 vaultBefore = token.balanceOf(address(vault));
        uint256 recipientBefore = token.balanceOf(recipient);
        uint256 totalBefore = vaultBefore + recipientBefore;

        vault.transferToken(address(token), recipient, transferAmount);

        uint256 vaultAfter = token.balanceOf(address(vault));
        uint256 recipientAfter = token.balanceOf(recipient);
        uint256 totalAfter = vaultAfter + recipientAfter;

        assertEq(vaultBefore - vaultAfter, transferAmount, "vault balance decrease must equal transfer amount");
        assertEq(
            recipientAfter - recipientBefore, transferAmount, "recipient balance increase must equal transfer amount"
        );
        assertEq(totalAfter, totalBefore, "total token supply across vault and recipient must be conserved");
    }

    /**
     * @notice An owner calling `execute(vault, initialize(newOwner, newBorrower))` as a
     *         self-call must always revert, and the vault's owner and borrower must remain
     *         unchanged afterward. Tests that the initialization guard cannot be bypassed
     *         via the execute function.
     * @dev The inner initialize call reverts with "already initialized", which causes
     *      execute to revert with "execution failed".
     * @param newOwner Fuzzed new owner address to attempt re-initialization with
     * @param newBorrower Fuzzed new borrower address to attempt re-initialization with
     * @custom:audit-property Re-initialization prevention via self-call
     * @custom:audit-category Access Control
     * @custom:audit-severity Critical
     */
    function testFuzz_execute_CannotReinitializeViaSelfCall(address newOwner, address newBorrower) public {
        vm.assume(newOwner != address(0));
        vm.assume(newBorrower != address(0));

        address originalOwner = vault.owner();
        address originalBorrower = vault.borrower();

        bytes memory initData = abi.encodeWithSelector(LoanVault.initialize.selector, newOwner, newBorrower);

        // Inner call fails (already initialized), outer execute reverts (execution failed)
        vm.expectRevert(Errors.LoanVault__ExecutionFailed.selector);
        vault.execute(address(vault), initData);

        assertEq(vault.owner(), originalOwner, "owner must not change after failed re-initialization");
        assertEq(vault.borrower(), originalBorrower, "borrower must not change after failed re-initialization");
        assertTrue(vault.isInitialized(), "initialized flag must remain true");
    }

    /**
     * @notice After any successful `execute()` call to an external target, the vault's own
     *         state — owner, borrower, initialized flag, and any unrelated token balances —
     *         must be completely unchanged. The vault should be a pure proxy that doesn't
     *         modify its own storage.
     * @dev Catches `execute()` corrupting proxy storage slots via unintended side effects
     *      from the target call. Uses MockReturnTarget which writes to its own storage.
     * @param value Fuzzed value passed to the external target
     * @custom:audit-property Vault state preservation after execute
     * @custom:audit-category Storage Integrity
     * @custom:audit-severity High
     */
    function testFuzz_execute_PreservesVaultStateInvariants(uint256 value) public {
        value = bound(value, 1, type(uint128).max);

        uint256 tokenFunding = 100e18;
        token.mint(address(vault), tokenFunding);

        address originalOwner = vault.owner();
        address originalBorrower = vault.borrower();
        bool originalInitialized = vault.isInitialized();
        uint256 tokenBalanceBefore = token.balanceOf(address(vault));

        bytes memory callData = abi.encodeWithSelector(MockReturnTarget.setAndReturnValue.selector, value);
        bytes memory result = vault.execute(address(target), callData);

        // Verify return data is correct (target returns value * 2)
        uint256 returnedValue = abi.decode(result, (uint256));
        assertEq(returnedValue, value * 2, "execute must relay return data correctly");

        // Verify vault state is completely unchanged
        assertEq(vault.owner(), originalOwner, "owner must not change after execute");
        assertEq(vault.borrower(), originalBorrower, "borrower must not change after execute");
        assertEq(vault.isInitialized(), originalInitialized, "initialized flag must not change after execute");
        assertEq(
            token.balanceOf(address(vault)),
            tokenBalanceBefore,
            "token balance must not change after execute to unrelated target"
        );
    }
}
