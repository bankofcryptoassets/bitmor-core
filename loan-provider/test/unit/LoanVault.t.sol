// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {LoanVault} from "@bitmor/protocol/LoanVault.sol";
import {LoanVaultFactory} from "@bitmor/protocol/LoanVaultFactory.sol";
import {ILoanVault} from "@bitmor/interfaces/ILoanVault.sol";
import {MintableERC20} from "@bitmor/mocks/MintableERC20.sol";
import {MockRevertingTarget, MockReturnTarget} from "../mock/LoanVaultMocks.sol";

/// @title LoanVaultTest
/// @notice Comprehensive unit tests for LoanVault.sol
/// @dev All direct LoanVault tests consolidated here
contract LoanVaultTest is Test {
    // ============ State Variables ============

    LoanVault internal vault;
    MintableERC20 internal mockToken;
    MockRevertingTarget internal revertingTarget;
    MockReturnTarget internal returnTarget;

    // ============ Test Actors ============

    address internal owner;
    address internal borrower;
    address internal attacker;
    address internal spender;
    address internal recipient;

    // ============ Setup ============

    function setUp() public {
        // Create labeled test actors
        owner = makeAddr("owner");
        borrower = makeAddr("borrower");
        attacker = makeAddr("attacker");
        spender = makeAddr("spender");
        recipient = makeAddr("recipient");

        // Deploy contracts
        vault = new LoanVault();
        mockToken = new MintableERC20("Mock Token", "MOCK", 18);
        revertingTarget = new MockRevertingTarget();
        returnTarget = new MockReturnTarget();
    }

    // ============ Tests: Initialization ============

    /// @notice initialize sets owner/borrower, guards zero addresses, and prevents double initialization
    function test_loanVault_initialize_setsOwnerBorrower_andDoubleInitReverts() public {
        // Pre-init state
        assertFalse(vault.isInitialized());
        assertEq(vault.owner(), address(0));
        assertEq(vault.borrower(), address(0));

        // Zero owner reverts
        vm.expectRevert("LoanVault: invalid owner");
        vault.initialize(address(0), borrower);

        // Zero borrower reverts
        vm.expectRevert("LoanVault: invalid borrower");
        vault.initialize(owner, address(0));

        // Successful initialization
        vault.initialize(owner, borrower);

        assertTrue(vault.isInitialized());
        assertEq(vault.owner(), owner);
        assertEq(vault.borrower(), borrower);

        // Double-init reverts
        vm.expectRevert("LoanVault: already initialized");
        vault.initialize(attacker, attacker);
    }

    // ============ Tests: Access Control ============

    /// @notice Test that attacker cannot call approveToken, transferToken, or execute after init
    function test_loanVault_onlyOwner_blocksPrivilegedCalls() public {
        vault.initialize(owner, borrower);
        mockToken.mint(address(vault), 1000e18);

        vm.startPrank(attacker);

        vm.expectRevert("LoanVault: caller is not owner");
        vault.approveToken(address(mockToken), spender, 100e18);

        vm.expectRevert("LoanVault: caller is not owner");
        vault.transferToken(address(mockToken), attacker, 100e18);

        vm.expectRevert("LoanVault: caller is not owner");
        vault.execute(address(returnTarget), abi.encodeWithSignature("setAndReturnValue(uint256)", 42));

        vm.stopPrank();
    }

    // ============ Tests: Token Management ============

    /// @notice Test approveToken: reverts on zero token/spender, sets allowance, re-approve updates
    function test_loanVault_approveToken_guards_and_setsAllowance() public {
        vault.initialize(owner, borrower);
        mockToken.mint(address(vault), 1000e18);

        vm.startPrank(owner);

        // Zero token reverts
        vm.expectRevert("LoanVault: invalid token");
        vault.approveToken(address(0), spender, 100e18);

        // Zero spender reverts
        vm.expectRevert("LoanVault: invalid spender");
        vault.approveToken(address(mockToken), address(0), 100e18);

        // Sets allowance
        vault.approveToken(address(mockToken), spender, 100e18);
        assertEq(mockToken.allowance(address(vault), spender), 100e18);

        // Re-approve updates allowance
        vault.approveToken(address(mockToken), spender, 200e18);
        assertEq(mockToken.allowance(address(vault), spender), 200e18);

        vm.stopPrank();
    }

    /// @notice Test transferToken: reverts on zero token/to, successful transfer moves balances
    function test_loanVault_transferToken_guards_and_movesBalance() public {
        vault.initialize(owner, borrower);
        mockToken.mint(address(vault), 1000e18);

        vm.startPrank(owner);

        // Zero token reverts
        vm.expectRevert("LoanVault: invalid token");
        vault.transferToken(address(0), recipient, 100e18);

        // Zero to reverts
        vm.expectRevert("LoanVault: invalid to address");
        vault.transferToken(address(mockToken), address(0), 100e18);

        // Successful transfer moves balances
        uint256 vaultBefore = mockToken.balanceOf(address(vault));
        uint256 recipientBefore = mockToken.balanceOf(recipient);

        vault.transferToken(address(mockToken), recipient, 400e18);

        assertEq(mockToken.balanceOf(address(vault)), vaultBefore - 400e18);
        assertEq(mockToken.balanceOf(recipient), recipientBefore + 400e18);

        vm.stopPrank();
    }

    // ============ Tests: Execute Functionality ============

    /// @notice Test execute: reverts on zero target, owner can execute successfully
    function test_loanVault_execute_invalidTarget_and_happyPath() public {
        vault.initialize(owner, borrower);

        vm.startPrank(owner);

        // Zero target reverts
        vm.expectRevert("LoanVault: invalid target");
        vault.execute(address(0), abi.encodeWithSignature("setAndReturnValue(uint256)", 42));

        // Happy path: owner executes successfully
        bytes memory result =
            vault.execute(address(returnTarget), abi.encodeWithSignature("setAndReturnValue(uint256)", 42));

        uint256 returnedValue = abi.decode(result, (uint256));
        assertEq(returnedValue, 84);
        assertEq(returnTarget.storedValue(), 42);

        vm.stopPrank();
    }

    /// @notice Test execute: target revert causes "execution failed"
    function test_loanVault_execute_targetReverts_revertsExecutionFailed() public {
        vault.initialize(owner, borrower);

        vm.prank(owner);
        vm.expectRevert("LoanVault: execution failed");
        vault.execute(address(revertingTarget), abi.encodeWithSignature("alwaysReverts()"));
    }

    // ============ Tests: View Functions ============

    /// @notice Test getTokenBalance matches IERC20.balanceOf(vault)
    function test_loanVault_getTokenBalance_matchesIERC20BalanceOf() public {
        vault.initialize(owner, borrower);

        assertEq(vault.getTokenBalance(address(mockToken)), 0);
        assertEq(vault.getTokenBalance(address(mockToken)), mockToken.balanceOf(address(vault)));

        mockToken.mint(address(vault), 12345e18);

        assertEq(vault.getTokenBalance(address(mockToken)), 12345e18);
        assertEq(vault.getTokenBalance(address(mockToken)), mockToken.balanceOf(address(vault)));
    }

    // ============ Tests: ETH Handling ============

    /// @notice Test vault can receive ETH before and after initialization
    function test_loanVault_receiveETH_accepts_pre_and_post_init() public {
        address sender = makeAddr("ethSender");
        vm.deal(sender, 2 ether);

        // Before init
        assertFalse(vault.isInitialized());

        vm.prank(sender);
        (bool success1,) = address(vault).call{value: 0.5 ether}("");
        assertTrue(success1);
        assertEq(address(vault).balance, 0.5 ether);

        // After init
        vault.initialize(owner, borrower);
        assertTrue(vault.isInitialized());

        vm.prank(sender);
        (bool success2,) = address(vault).call{value: 1 ether}("");
        assertTrue(success2);
        assertEq(address(vault).balance, 1.5 ether);
    }

    // ============ Tests: LoanVaultFactory Integration ============

    /// @notice Test computeAddress returns the exact address where createLoanVault deploys
    /// @dev Validates CREATE2 determinism: predicted address == actual deployed address
    function test_loanVaultFactory_computeAddress_matchesDeployedVault() public {
        // Deploy implementation and factory
        address implementation = address(new LoanVault());
        address loanContract = makeAddr("loanContract");
        LoanVaultFactory factory = new LoanVaultFactory(implementation, loanContract);

        address testBorrower = makeAddr("testBorrower");
        uint256 timestamp = block.timestamp;

        // Predict address before deployment
        address predicted = factory.computeAddress(testBorrower, timestamp);

        // Deploy vault
        vm.prank(loanContract);
        address actual = factory.createLoanVault(testBorrower, timestamp);

        // Verify determinism: predicted == actual
        assertEq(predicted, actual, "computeAddress must match deployed vault address");

        // Verify vault is properly initialized
        assertEq(ILoanVault(actual).owner(), loanContract, "Vault owner mismatch");
        assertEq(ILoanVault(actual).borrower(), testBorrower, "Vault borrower mismatch");
        assertTrue(ILoanVault(actual).isInitialized(), "Vault not initialized");
    }
}
