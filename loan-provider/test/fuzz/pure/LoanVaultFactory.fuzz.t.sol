// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {LoanVault} from "@bitmor/protocol/LoanVault.sol";
import {LoanVaultFactory} from "@bitmor/protocol/LoanVaultFactory.sol";
import {ILoanVault} from "@bitmor/interfaces/ILoanVault.sol";
import {MockERC20} from "../../mock/MockERC20.sol";
import {MockReturnTarget} from "../../mock/LoanVaultMocks.sol";

/**
 * @title LoanVaultFactoryFuzzTest
 * @author Bitmor Protocol
 * @notice Stateless fuzz tests for `LoanVaultFactory.sol`
 * @dev Tests 3 properties covering CREATE2 address prediction, clone storage isolation,
 *      and full operational readiness of factory-created vaults.
 *
 * @custom:audit-category CREATE2 Correctness, Storage Isolation, Clone Lifecycle
 */
contract LoanVaultFactoryFuzzTest is Test {
    // ============ Infrastructure ============

    LoanVaultFactory public factory;
    LoanVault public implementation;
    MockERC20 public token;

    // ============ Setup ============

    function setUp() public {
        implementation = new LoanVault();
        factory = new LoanVaultFactory(address(implementation), address(this));
        token = new MockERC20("Test Token", "TKN", 18);
    }

    // ============ Tests ============

    /**
     * @notice The address predicted by `computeAddress(borrower, timestamp)` must always
     *         match the address of the actually deployed vault, across the full
     *         borrower x timestamp input space.
     * @dev Catches CREATE2 prediction mismatch from salt generation or clone init code
     *      hash changes. If this breaks, the Loan contract can't locate deployed vaults.
     * @param borrower Fuzzed borrower address
     * @param timestamp Fuzzed creation timestamp
     * @custom:audit-property CREATE2 address prediction correctness
     * @custom:audit-category CREATE2 Correctness
     * @custom:audit-severity Critical
     */
    function testFuzz_computeAddress_AlwaysMatchesDeployed(address borrower, uint256 timestamp) public {
        vm.assume(borrower != address(0));

        address predicted = factory.computeAddress(borrower, timestamp);
        address actual = factory.createLoanVault(borrower, timestamp);

        assertEq(predicted, actual, "computed address must match deployed address");
    }

    /**
     * @notice Operations on vault A (minting tokens, transferring them out) must not
     *         affect vault B in any way — not its token balances, not its borrower
     *         assignment. Minimal proxy clones must have fully independent storage.
     * @dev Catches shared state between minimal proxy clones where one clone's writes
     *      bleed into another.
     * @param borrower1 Fuzzed first borrower address
     * @param borrower2 Fuzzed second borrower address
     * @param ts1 Fuzzed first creation timestamp
     * @param ts2 Fuzzed second creation timestamp
     * @param mintAmount Amount of tokens to mint to vault A
     * @custom:audit-property Clone storage isolation
     * @custom:audit-category Storage Isolation
     * @custom:audit-severity Critical
     */
    function testFuzz_createLoanVault_VaultsAreIsolated(
        address borrower1,
        address borrower2,
        uint256 ts1,
        uint256 ts2,
        uint256 mintAmount
    ) public {
        vm.assume(borrower1 != address(0));
        vm.assume(borrower2 != address(0));
        // Ensure different salts so we get two distinct vaults
        vm.assume(keccak256(abi.encodePacked(borrower1, ts1)) != keccak256(abi.encodePacked(borrower2, ts2)));
        mintAmount = bound(mintAmount, 1, type(uint128).max);

        address vaultA = factory.createLoanVault(borrower1, ts1);
        address vaultB = factory.createLoanVault(borrower2, ts2);

        // Fund vault A with tokens
        token.mint(vaultA, mintAmount);

        // Transfer half from vault A to a sink
        uint256 halfAmount = mintAmount / 2;
        if (halfAmount > 0) {
            ILoanVault(vaultA).transferToken(address(token), makeAddr("sink"), halfAmount);
        }

        // Vault B must be completely unaffected
        assertEq(token.balanceOf(vaultB), 0, "vault B token balance must be zero");
        assertEq(ILoanVault(vaultB).borrower(), borrower2, "vault B borrower must be unchanged");
        assertEq(ILoanVault(vaultA).borrower(), borrower1, "vault A borrower must be unchanged");

        // Vault states must be independently initialized
        assertTrue(ILoanVault(vaultA).isInitialized(), "vault A must be initialized");
        assertTrue(ILoanVault(vaultB).isInitialized(), "vault B must be initialized");
        assertEq(ILoanVault(vaultA).owner(), address(this), "vault A owner must be factory's loan contract");
        assertEq(ILoanVault(vaultB).owner(), address(this), "vault B owner must be factory's loan contract");
    }

    /**
     * @notice A factory-created vault must be immediately operational: `approveToken`,
     *         `transferToken`, and `execute` must all work correctly right after deployment.
     *         Tests the complete clone lifecycle end-to-end.
     * @dev Catches broken clone delegation where the minimal proxy pattern fails for
     *      certain function selectors.
     * @param borrower Fuzzed borrower address
     * @param timestamp Fuzzed creation timestamp
     * @param amount Fuzzed token amount for operations
     * @custom:audit-property Clone fully operational from block zero
     * @custom:audit-category Clone Lifecycle
     * @custom:audit-severity High
     */
    function testFuzz_createLoanVault_FullyOperationalFromBlockZero(address borrower, uint256 timestamp, uint256 amount)
        public
    {
        vm.assume(borrower != address(0));
        amount = bound(amount, 1, type(uint128).max);

        address vault = factory.createLoanVault(borrower, timestamp);

        // Verify initialization
        assertTrue(ILoanVault(vault).isInitialized(), "vault must be initialized");
        assertEq(ILoanVault(vault).owner(), address(this), "vault owner must be loan contract (this)");
        assertEq(ILoanVault(vault).borrower(), borrower, "vault borrower must match");

        // Test approveToken works
        token.mint(vault, amount);
        address spender = makeAddr("spender");
        ILoanVault(vault).approveToken(address(token), spender, amount);
        assertEq(token.allowance(vault, spender), amount, "approveToken must set correct allowance");

        // Test transferToken works
        address sink = makeAddr("sink");
        ILoanVault(vault).transferToken(address(token), sink, amount);
        assertEq(token.balanceOf(sink), amount, "transferToken must work immediately after creation");
        assertEq(token.balanceOf(vault), 0, "vault must have zero balance after full transfer");

        // Test execute works (call a simple external function)
        MockReturnTarget target = new MockReturnTarget();
        bytes memory callData = abi.encodeWithSelector(MockReturnTarget.setAndReturnValue.selector, 42);
        bytes memory result = ILoanVault(vault).execute(address(target), callData);
        uint256 returnedValue = abi.decode(result, (uint256));
        assertEq(returnedValue, 84, "execute must relay return data correctly");
    }
}
