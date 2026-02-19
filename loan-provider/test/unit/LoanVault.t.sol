// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {LoanVault} from "@bitmor/protocol/LoanVault.sol";
import {LoanVaultFactory} from "@bitmor/protocol/LoanVaultFactory.sol";
import {ILoanVault} from "@bitmor/interfaces/ILoanVault.sol";
import {ILoanVaultFactory} from "@bitmor/interfaces/ILoanVaultFactory.sol";
import {MintableERC20} from "../../test/mock/MintableERC20.sol";
import {Errors} from "@bitmor/libraries/helpers/Errors.sol";
import {TestConstants as TC} from "../helpers/TestConstants.sol";

// Mocks
import {MockRevertingTarget, MockReturnTarget} from "../mock/LoanVaultMocks.sol";
import {MockBitmorLendingPool} from "../mock/MockBitmorLendingPool.sol";
import {MockBTCVault} from "../mock/MockBTCVault.sol";
import {MockAddressesProvider} from "../mock/MockAddressesProvider.sol";
import {MockERC20} from "../mock/MockERC20.sol";
import {MockVariableDebtToken} from "../mock/MockVariableDebtToken.sol";
import {MockPriceOracle} from "../mock/MockPriceOracle.sol";

// Harness
import {LSALogicHarness} from "../harness/LSALogicHarness.sol";

/// @title LoanVaultTest
/// @author Bitmor Protocol
/// @notice Comprehensive unit tests for `LoanVault.sol`, `LoanVaultFactory.sol`, and `LSALogic.sol`
/// @dev All LSA-related unit tests consolidated here for isolated mock-based testing.
///      For system-level security/exploit tests with full loan integration context,
///      see `test/unit/LSAExploit.t.sol` which tests attack vectors against the real loan flow.
contract LoanVaultTest is Test {
    // ============================================================================
    // State Variables
    // ============================================================================

    LoanVault internal vault;
    MintableERC20 internal mockToken;
    MockRevertingTarget internal revertingTarget;
    MockReturnTarget internal returnTarget;

    // LSALogic testing infrastructure
    LSALogicHarness internal lsaHarness;
    MockBitmorLendingPool internal mockBitmorPool;
    MockBTCVault internal mockBTCVault;
    MockAddressesProvider internal mockAddressesProvider;
    MockERC20 internal mockCbBTC;
    MockERC20 internal mockUSDC;
    MockVariableDebtToken internal mockDebtToken;
    MockPriceOracle internal mockOracle;
    LoanVault internal lsa;

    // ============================================================================
    // Test Actors
    // ============================================================================

    address internal owner;
    address internal borrower;
    address internal attacker;
    address internal spender;
    address internal recipient;

    /// @dev Recognizable test value for execute() return validation
    uint256 internal constant TEST_INPUT_VALUE = 42;

    // ============================================================================
    // Setup
    // ============================================================================

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

    // ============================================================================
    // SECTION 1: LoanVault Tests
    // ============================================================================

    // --- Initialization Tests ---

    /// @notice Vault is not initialized before initialize() is called
    function test_initialize_PreInitState() public view {
        assertFalse(vault.isInitialized(), "vault should not be initialized");
        assertEq(vault.owner(), address(0), "owner should be zero before init");
        assertEq(vault.borrower(), address(0), "borrower should be zero before init");
    }

    /// @notice initialize reverts when owner is zero address
    function test_initialize_RevertWhen_OwnerIsZeroAddress() public {
        vm.expectRevert("LoanVault: invalid owner");
        vault.initialize(address(0), borrower);
    }

    /// @notice initialize reverts when borrower is zero address
    function test_initialize_RevertWhen_BorrowerIsZeroAddress() public {
        vm.expectRevert("LoanVault: invalid borrower");
        vault.initialize(owner, address(0));
    }

    /// @notice initialize sets owner and borrower correctly
    function test_initialize_SetsOwnerAndBorrower() public {
        vault.initialize(owner, borrower);

        assertTrue(vault.isInitialized(), "vault should be initialized");
        assertEq(vault.owner(), owner, "owner should be set");
        assertEq(vault.borrower(), borrower, "borrower should be set");
    }

    /// @notice initialize reverts when called twice
    function test_initialize_RevertWhen_AlreadyInitialized() public {
        vault.initialize(owner, borrower);

        vm.expectRevert("LoanVault: already initialized");
        vault.initialize(attacker, attacker);
    }

    /// @notice initialize emits VaultInitialized event
    function test_initialize_EmitsVaultInitializedEvent() public {
        // Arrange
        LoanVault newVault = new LoanVault();

        // Assert - expect event
        vm.expectEmit(true, true, true, true);
        emit ILoanVault.LoanVault__VaultInitialized(owner, borrower);

        // Act
        newVault.initialize(owner, borrower);
    }

    // --- approveToken Isolated Tests ---

    /// @notice approveToken reverts when token is zero address
    function test_approveToken_RevertWhen_TokenIsZeroAddress() public {
        // Arrange
        vault.initialize(owner, borrower);

        // Act + Assert
        vm.prank(owner);
        vm.expectRevert("LoanVault: invalid token");
        vault.approveToken(address(0), spender, TC.USER_USDC_BALANCE);
    }

    /// @notice approveToken reverts when spender is zero address
    function test_approveToken_RevertWhen_SpenderIsZeroAddress() public {
        // Arrange
        vault.initialize(owner, borrower);

        // Act + Assert
        vm.prank(owner);
        vm.expectRevert("LoanVault: invalid spender");
        vault.approveToken(address(mockToken), address(0), TC.USER_USDC_BALANCE);
    }

    /// @notice approveToken succeeds with valid parameters
    function test_approveToken_SucceedsWithValidParams() public {
        // Arrange
        vault.initialize(owner, borrower);

        // Act
        vm.prank(owner);
        vault.approveToken(address(mockToken), spender, TC.USER_USDC_BALANCE);

        // Assert
        assertEq(mockToken.allowance(address(vault), spender), TC.USER_USDC_BALANCE, "allowance should be set");
    }

    /// @notice approveToken reverts when caller is not owner
    function test_approveToken_RevertWhen_CallerNotOwner() public {
        // Arrange
        vault.initialize(owner, borrower);

        // Act + Assert
        vm.prank(attacker);
        vm.expectRevert("LoanVault: caller is not owner");
        vault.approveToken(address(mockToken), spender, TC.USER_USDC_BALANCE);
    }

    /// @notice approveToken can update existing allowance
    function test_approveToken_UpdatesExistingAllowance() public {
        // Arrange
        vault.initialize(owner, borrower);
        vm.prank(owner);
        vault.approveToken(address(mockToken), spender, TC.USER_USDC_BALANCE);

        // Act
        uint256 newAllowance = TC.USER_USDC_BALANCE * 2;
        vm.prank(owner);
        vault.approveToken(address(mockToken), spender, newAllowance);

        // Assert
        assertEq(mockToken.allowance(address(vault), spender), newAllowance, "allowance should be updated");
    }

    /// @notice approveToken emits TokenApproved event
    function test_approveToken_EmitsTokenApprovedEvent() public {
        // Arrange
        vault.initialize(owner, borrower);
        uint256 amount = TC.USER_USDC_BALANCE;

        // Assert - expect event
        vm.expectEmit(true, true, true, true);
        emit ILoanVault.LoanVault__TokenApproved(address(mockToken), spender, amount);

        // Act
        vm.prank(owner);
        vault.approveToken(address(mockToken), spender, amount);
    }

    // --- transferToken Isolated Tests ---

    /// @notice transferToken reverts when token is zero address
    function test_transferToken_RevertWhen_TokenIsZeroAddress() public {
        // Arrange
        vault.initialize(owner, borrower);

        // Act + Assert
        vm.prank(owner);
        vm.expectRevert("LoanVault: invalid token");
        vault.transferToken(address(0), recipient, TC.PREMIUM_AMOUNT);
    }

    /// @notice transferToken reverts when to is zero address
    function test_transferToken_RevertWhen_ToIsZeroAddress() public {
        // Arrange
        vault.initialize(owner, borrower);
        mockToken.mint(address(vault), TC.USER_USDC_BALANCE);

        // Act + Assert
        vm.prank(owner);
        vm.expectRevert("LoanVault: invalid to address");
        vault.transferToken(address(mockToken), address(0), TC.PREMIUM_AMOUNT);
    }

    /// @notice transferToken succeeds with valid parameters
    function test_transferToken_SucceedsWithValidParams() public {
        // Arrange
        vault.initialize(owner, borrower);
        mockToken.mint(address(vault), TC.USER_USDC_BALANCE);
        uint256 vaultBefore = mockToken.balanceOf(address(vault));
        uint256 recipientBefore = mockToken.balanceOf(recipient);

        // Act
        vm.prank(owner);
        vault.transferToken(address(mockToken), recipient, TC.PREMIUM_AMOUNT);

        // Assert
        assertEq(mockToken.balanceOf(recipient), recipientBefore + TC.PREMIUM_AMOUNT, "recipient received tokens");
        assertEq(mockToken.balanceOf(address(vault)), vaultBefore - TC.PREMIUM_AMOUNT, "vault balance decreased");
    }

    /// @notice transferToken reverts when caller is not owner
    function test_transferToken_RevertWhen_CallerNotOwner() public {
        // Arrange
        vault.initialize(owner, borrower);
        mockToken.mint(address(vault), TC.USER_USDC_BALANCE);

        // Act + Assert
        vm.prank(attacker);
        vm.expectRevert("LoanVault: caller is not owner");
        vault.transferToken(address(mockToken), recipient, TC.PREMIUM_AMOUNT);
    }

    /// @notice transferToken emits TokenTransferred event
    function test_transferToken_EmitsTokenTransferredEvent() public {
        // Arrange
        vault.initialize(owner, borrower);
        uint256 amount = TC.PREMIUM_AMOUNT;
        mockToken.mint(address(vault), amount);

        // Assert - expect event
        vm.expectEmit(true, true, true, true);
        emit ILoanVault.LoanVault__TokenTransferred(address(mockToken), recipient, amount);

        // Act
        vm.prank(owner);
        vault.transferToken(address(mockToken), recipient, amount);
    }

    /// @notice transferToken reverts when vault has insufficient balance
    function test_transferToken_RevertWhen_InsufficientBalance() public {
        // Arrange
        vault.initialize(owner, borrower);
        // Note: vault has 0 tokens

        // Act + Assert
        vm.prank(owner);
        vm.expectRevert(); // ERC20 transfer will fail
        vault.transferToken(address(mockToken), recipient, TC.PREMIUM_AMOUNT);
    }

    /// @notice transferToken succeeds with zero amount
    function test_transferToken_SucceedsWithZeroAmount() public {
        // Arrange
        vault.initialize(owner, borrower);
        uint256 recipientBalanceBefore = mockToken.balanceOf(recipient);

        // Act
        vm.prank(owner);
        vault.transferToken(address(mockToken), recipient, 0);

        // Assert
        assertEq(mockToken.balanceOf(recipient), recipientBalanceBefore, "zero transfer should not change balance");
    }

    // --- execute Isolated Tests ---

    /// @notice execute reverts when target is zero address
    function test_execute_RevertWhen_TargetIsZeroAddress() public {
        // Arrange
        vault.initialize(owner, borrower);

        // Act + Assert
        vm.prank(owner);
        vm.expectRevert("LoanVault: invalid target");
        vault.execute(address(0), abi.encodeWithSignature("foo()"));
    }

    /// @notice execute reverts when call fails
    function test_execute_RevertWhen_CallFails() public {
        // Arrange
        vault.initialize(owner, borrower);

        // Act + Assert
        vm.prank(owner);
        vm.expectRevert("LoanVault: execution failed");
        vault.execute(address(revertingTarget), abi.encodeWithSignature("alwaysReverts()"));
    }

    /// @notice execute succeeds with valid call and returns data
    function test_execute_SucceedsWithValidCall() public {
        // Arrange
        vault.initialize(owner, borrower);

        // Test values: TEST_INPUT_VALUE is recognizable non-zero; mock returns input * 2
        uint256 expectedOutput = TEST_INPUT_VALUE * 2; // 84

        // Act
        vm.prank(owner);
        bytes memory result = vault.execute(
            address(returnTarget), abi.encodeWithSignature("setAndReturnValue(uint256)", TEST_INPUT_VALUE)
        );

        // Assert
        uint256 returnedValue = abi.decode(result, (uint256));
        assertEq(returnedValue, expectedOutput, "return value should be input * 2");
        assertEq(returnTarget.storedValue(), TEST_INPUT_VALUE, "stored value should match input");
    }

    /// @notice execute reverts when caller is not owner
    function test_execute_RevertWhen_CallerNotOwner() public {
        // Arrange
        vault.initialize(owner, borrower);

        // Act + Assert
        vm.prank(attacker);
        vm.expectRevert("LoanVault: caller is not owner");
        vault.execute(address(returnTarget), abi.encodeWithSignature("foo()"));
    }

    /// @notice execute emits Executed event
    function test_execute_EmitsExecutedEvent() public {
        // Arrange
        vault.initialize(owner, borrower);
        bytes memory callData = abi.encodeWithSignature("setAndReturnValue(uint256)", TEST_INPUT_VALUE);

        // Assert - expect event
        // Note: Last two params (false, false) because returnData is computed during
        // execution and cannot be predicted ahead of time
        vm.expectEmit(true, true, false, false);
        emit ILoanVault.LoanVault__Executed(address(returnTarget), callData, "");

        // Act
        vm.prank(owner);
        vault.execute(address(returnTarget), callData);
    }

    /// @notice execute succeeds with empty calldata (no-op call to EOA)
    function test_execute_SucceedsWithEmptyCalldata() public {
        // Arrange
        vault.initialize(owner, borrower);

        // Act - empty calldata to EOA should succeed
        vm.prank(owner);
        bytes memory result = vault.execute(recipient, "");

        // Assert
        assertEq(result.length, 0, "empty call should return empty data");
    }

    // --- View Functions Tests ---

    /// @notice getTokenBalance returns correct balance for token
    function test_getTokenBalance_ReturnsCorrectBalance() public {
        vault.initialize(owner, borrower);

        // Initial state - zero balance
        assertEq(vault.getTokenBalance(address(mockToken)), 0, "balance should be zero initially");

        // After minting
        uint256 mintAmount = TC.USER_USDC_BALANCE;
        mockToken.mint(address(vault), mintAmount);

        assertEq(vault.getTokenBalance(address(mockToken)), mintAmount, "balance should match minted amount");
    }

    // --- ETH Handling Tests ---

    /// @notice Vault can receive ETH before initialization
    function test_receive_AcceptsETH_BeforeInit() public {
        address sender = makeAddr("ethSender");
        vm.deal(sender, 1 ether);

        assertFalse(vault.isInitialized(), "vault should not be initialized");

        vm.prank(sender);
        (bool success,) = address(vault).call{value: 0.5 ether}("");

        assertTrue(success, "should accept ETH before init");
        assertEq(address(vault).balance, 0.5 ether, "balance should be 0.5 ether");
    }

    /// @notice Vault can receive ETH after initialization
    function test_receive_AcceptsETH_AfterInit() public {
        address sender = makeAddr("ethSender");
        vm.deal(sender, 1 ether);

        vault.initialize(owner, borrower);
        assertTrue(vault.isInitialized(), "vault should be initialized");

        vm.prank(sender);
        (bool success,) = address(vault).call{value: 1 ether}("");

        assertTrue(success, "should accept ETH after init");
        assertEq(address(vault).balance, 1 ether, "balance should be 1 ether");
    }

    // ============================================================================
    // SECTION 2: LoanVaultFactory Tests
    // ============================================================================

    // --- Constructor Tests ---

    /// @notice Constructor reverts when implementation is zero address
    function test_constructor_RevertWhen_ImplementationIsZeroAddress() public {
        // Arrange
        address loanContract = makeAddr("loanContract");

        // Act + Assert
        vm.expectRevert(Errors.ZeroAddress.selector);
        new LoanVaultFactory(address(0), loanContract);
    }

    /// @notice Constructor reverts when loan contract is zero address
    function test_constructor_RevertWhen_LoanContractIsZeroAddress() public {
        // Arrange
        address implementation = address(new LoanVault());

        // Act + Assert
        vm.expectRevert(Errors.ZeroAddress.selector);
        new LoanVaultFactory(implementation, address(0));
    }

    /// @notice Constructor sets immutable variables correctly
    function test_constructor_SetsImmutableVariables() public {
        // Arrange
        address implementation = address(new LoanVault());
        address loanContract = makeAddr("loanContract");

        // Act
        LoanVaultFactory factory = new LoanVaultFactory(implementation, loanContract);

        // Assert
        assertEq(factory.i_IMPLEMENTATION(), implementation, "implementation should be set");
        assertEq(factory.i_LOAN(), loanContract, "loan contract should be set");
    }

    // --- Access Control Tests ---

    /// @notice createLoanVault reverts when caller is not the loan contract
    function test_createLoanVault_RevertWhen_CallerIsNotLoanContract() public {
        // Arrange
        address implementation = address(new LoanVault());
        address loanContract = makeAddr("loanContract");
        LoanVaultFactory factory = new LoanVaultFactory(implementation, loanContract);

        // Act + Assert
        vm.prank(attacker);
        vm.expectRevert(Errors.UnauthorizedCaller.selector);
        factory.createLoanVault(makeAddr("borrower"), block.timestamp);
    }

    /// @notice createLoanVault succeeds when called by loan contract and initializes correctly
    function test_createLoanVault_SucceedsAndInitializesCorrectly() public {
        // Arrange
        address implementation = address(new LoanVault());
        address loanContract = makeAddr("loanContract");
        LoanVaultFactory factory = new LoanVaultFactory(implementation, loanContract);
        address testBorrower = makeAddr("testBorrower");

        // Act
        vm.prank(loanContract);
        address vaultAddr = factory.createLoanVault(testBorrower, block.timestamp);

        // Assert - deployment succeeded
        assertTrue(vaultAddr != address(0), "vault should be deployed");

        // Assert - initialization correct
        ILoanVault createdVault = ILoanVault(vaultAddr);
        assertEq(createdVault.owner(), loanContract, "owner should be loan contract");
        assertEq(createdVault.borrower(), testBorrower, "borrower should be set correctly");
        assertTrue(createdVault.isInitialized(), "vault should be initialized");
    }

    /// @notice createLoanVault emits VaultCreated event
    function test_createLoanVault_EmitsVaultCreatedEvent() public {
        // Arrange
        address implementation = address(new LoanVault());
        address loanContract = makeAddr("loanContract");
        LoanVaultFactory factory = new LoanVaultFactory(implementation, loanContract);
        address testBorrower = makeAddr("testBorrower");
        uint256 timestamp = block.timestamp;

        // Compute expected address and salt
        address expectedVault = factory.computeAddress(testBorrower, timestamp);
        bytes32 expectedSalt = keccak256(abi.encodePacked(testBorrower, timestamp));

        // Assert - expect event
        vm.expectEmit(true, true, true, true);
        emit ILoanVaultFactory.LoanVaultFactory__VaultCreated(expectedVault, testBorrower, expectedSalt);

        // Act
        vm.prank(loanContract);
        factory.createLoanVault(testBorrower, timestamp);
    }

    // --- Determinism Tests ---

    /// @notice computeAddress returns the exact address where createLoanVault deploys
    function test_computeAddress_MatchesDeployedVault() public {
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
        assertEq(ILoanVault(actual).owner(), loanContract, "vault owner should be loan contract");
        assertEq(ILoanVault(actual).borrower(), testBorrower, "vault borrower should match");
        assertTrue(ILoanVault(actual).isInitialized(), "vault should be initialized");
    }

    /// @notice Same borrower with different timestamps creates different vaults
    function test_createLoanVault_DifferentTimestamps_CreatesDifferentAddresses() public {
        // Arrange
        address implementation = address(new LoanVault());
        address loanContract = makeAddr("loanContract");
        LoanVaultFactory factory = new LoanVaultFactory(implementation, loanContract);
        address testBorrower = makeAddr("testBorrower");

        // Act
        vm.startPrank(loanContract);
        address vault1 = factory.createLoanVault(testBorrower, 1000);
        address vault2 = factory.createLoanVault(testBorrower, 2000);
        vm.stopPrank();

        // Assert
        assertTrue(vault1 != vault2, "different timestamps should create different vaults");
    }

    /// @notice Different borrowers with same timestamp creates different vaults
    function test_createLoanVault_DifferentBorrowers_CreatesDifferentAddresses() public {
        // Arrange
        address implementation = address(new LoanVault());
        address loanContract = makeAddr("loanContract");
        LoanVaultFactory factory = new LoanVaultFactory(implementation, loanContract);
        uint256 timestamp = block.timestamp;

        // Act
        vm.startPrank(loanContract);
        address vault1 = factory.createLoanVault(makeAddr("borrower1"), timestamp);
        address vault2 = factory.createLoanVault(makeAddr("borrower2"), timestamp);
        vm.stopPrank();

        // Assert
        assertTrue(vault1 != vault2, "different borrowers should create different vaults");
    }

    /// @notice Same salt on second deploy reverts (CREATE2 collision)
    function test_createLoanVault_RevertWhen_SameSaltUsedTwice() public {
        // Arrange
        address implementation = address(new LoanVault());
        address loanContract = makeAddr("loanContract");
        LoanVaultFactory factory = new LoanVaultFactory(implementation, loanContract);
        address testBorrower = makeAddr("testBorrower");
        uint256 timestamp = block.timestamp;

        // Act - first deploy succeeds
        vm.startPrank(loanContract);
        factory.createLoanVault(testBorrower, timestamp);

        // Assert - second deploy with same salt reverts (CREATE2 collision)
        vm.expectRevert();
        factory.createLoanVault(testBorrower, timestamp);
        vm.stopPrank();
    }

    // ============================================================================
    // SECTION 3: LSALogic Tests
    // ============================================================================

    // --- approveCreditDelegation Tests ---

    /// @notice approveCreditDelegation reverts when variableDebtToken is zero address
    function test_approveCreditDelegation_RevertWhen_DebtTokenIsZero() public {
        // Arrange
        _setupLSALogicInfrastructure();
        mockBitmorPool.setInvalidReserve(address(mockUSDC));

        // Act + Assert
        vm.expectRevert("LSALogic: invalid debt token");
        lsaHarness.exposed_approveCreditDelegation(
            address(lsa), address(mockBitmorPool), address(mockUSDC), TC.USER_USDC_BALANCE, address(this)
        );
    }

    /// @notice Verifies approveCreditDelegation correctly encodes and dispatches the delegation call
    /// @dev LIMITATION: Unit test verifies call encoding and dispatch via event emission.
    ///      The mock verifies the call was made correctly; integration tests validate full behavior.
    function test_approveCreditDelegation_ApprovesDelegate() public {
        // Arrange
        _setupLSALogicInfrastructure();
        uint256 delegationAmount = TC.USER_USDC_BALANCE;

        // Build expected calldata that LSALogic should encode
        bytes memory expectedCalldata =
            abi.encodeWithSignature("approveDelegation(address,uint256)", address(this), delegationAmount);

        // Assert - expect LSA.execute() to be called with correct target and data
        // Note: (true, true, false, false) - check indexed topics, skip data (returnData unpredictable)
        vm.expectEmit(true, true, false, false);
        emit ILoanVault.LoanVault__Executed(address(mockDebtToken), expectedCalldata, "");

        // Act
        lsaHarness.exposed_approveCreditDelegation(
            address(lsa), address(mockBitmorPool), address(mockUSDC), delegationAmount, address(this)
        );

        // Assert - also verify final state as secondary check
        uint256 allowance = mockDebtToken.borrowAllowance(address(lsa), address(this));
        assertEq(allowance, delegationAmount, "delegation should be approved");
    }

    // --- withdrawCollateral Tests ---

    /// @notice withdrawCollateral returns amount withdrawn when MAX_U256 is used
    function test_withdrawCollateral_WithMaxU256_WithdrawsEntireBalance() public {
        // Arrange
        _setupLSALogicInfrastructureWithDeposit();
        uint256 depositedAmount = TC.STANDARD_COLLATERAL;

        // Act
        uint256 withdrawn = lsaHarness.exposed_withdrawCollateral(
            address(lsa), address(mockBitmorPool), address(mockBTCVault), recipient
        );

        // Assert
        assertEq(withdrawn, depositedAmount, "should withdraw entire balance");
    }

    /// @notice withdrawCollateral returns zero when LSA has no deposits
    function test_withdrawCollateral_WithZeroBalance() public {
        // Arrange - basic infrastructure without deposits
        _setupLSALogicInfrastructure();

        // Deploy mock aToken for BTC vault (needed for withdraw)
        MockAToken mockAToken =
            new MockAToken("Bitmor aToken bvBTC", "abvBTC", 8, address(mockBTCVault), address(mockBitmorPool));
        mockBitmorPool.initReserve(address(mockBTCVault), address(mockAToken), address(0));

        // Act - withdraw with zero balance
        uint256 withdrawn = lsaHarness.exposed_withdrawCollateral(
            address(lsa), address(mockBitmorPool), address(mockBTCVault), recipient
        );

        // Assert
        assertEq(withdrawn, 0, "should withdraw zero from empty balance");
    }

    /// @notice approveCreditDelegation succeeds with zero amount
    function test_approveCreditDelegation_WithZeroAmount() public {
        // Arrange
        _setupLSALogicInfrastructure();

        // Build expected calldata for zero amount delegation
        bytes memory expectedCalldata =
            abi.encodeWithSignature("approveDelegation(address,uint256)", address(this), uint256(0));

        // Assert - expect LSA.execute() to be called with correct target and data
        // Note: (true, true, false, false) - check indexed topics, skip data (returnData unpredictable)
        vm.expectEmit(true, true, false, false);
        emit ILoanVault.LoanVault__Executed(address(mockDebtToken), expectedCalldata, "");

        // Act
        lsaHarness.exposed_approveCreditDelegation(
            address(lsa), address(mockBitmorPool), address(mockUSDC), 0, address(this)
        );

        // Assert - also verify final state as secondary check
        uint256 allowance = mockDebtToken.borrowAllowance(address(lsa), address(this));
        assertEq(allowance, 0, "zero delegation should be set");
    }

    /// @notice redeemBTC returns zero assets when shares amount is zero
    function test_redeemBTC_WithZeroSharesAmount() public {
        // Arrange
        _setupLSALogicInfrastructureWithSharesClean();

        // Act - redeem zero shares
        uint256 received =
            lsaHarness.exposed_redeemBTC(address(lsa), address(mockBTCVault), 0, recipient, TC.BPS_DENOMINATOR);

        // Assert - zero shares should return zero assets
        assertEq(received, 0, "zero shares should return zero assets");
    }

    // --- redeemBTC Tests ---

    /// @notice redeemBTC reverts when received assets are below minimum (slippage exceeded)
    function test_redeemBTC_RevertWhen_SlippageExceeded() public {
        // Arrange
        _setupLSALogicInfrastructureWithShares();
        uint256 sharesAmount = TC.STANDARD_COLLATERAL;

        // Configure mock to return much less than minimum (simulate 50% loss - exceeds slippage)
        mockBTCVault.setMockRedeemReturn(sharesAmount / 2);

        // Calculate slippage parameter: 99% = 9900 bps means minimum is 99% of expected
        uint256 slippageBps = TC.BPS_DENOMINATOR - TC.SLIPPAGE_SHARES_TO_ASSET; // 9900 bps = 99%

        // Act + Assert
        vm.expectRevert(Errors.SlippageExceededWhileConvertingToAssets.selector);
        lsaHarness.exposed_redeemBTC(address(lsa), address(mockBTCVault), sharesAmount, recipient, slippageBps);
    }

    /// @notice redeemBTC succeeds when received assets equal minimum exactly
    function test_redeemBTC_SucceedsWhenExactlyAtMinimum() public {
        // Arrange
        _setupLSALogicInfrastructureWithSharesClean();
        uint256 sharesAmount = TC.STANDARD_COLLATERAL;
        uint256 slippageBps = TC.BPS_DENOMINATOR - TC.SLIPPAGE_SHARES_TO_ASSET; // 9900 bps = 99%

        // For 1:1 vault (no extra underlying), shares == expected assets
        // Minimum = expectedAssets * slippageBps / 10000 = shares * 99%
        uint256 exactMinimum = (sharesAmount * slippageBps) / TC.BPS_DENOMINATOR;
        mockBTCVault.setMockRedeemReturn(exactMinimum);

        // Act
        uint256 received =
            lsaHarness.exposed_redeemBTC(address(lsa), address(mockBTCVault), sharesAmount, recipient, slippageBps);

        // Assert
        assertEq(received, exactMinimum, "should receive exact minimum");
    }

    /// @notice redeemBTC succeeds when received assets exceed minimum
    function test_redeemBTC_SucceedsWhenAboveMinimum() public {
        // Arrange
        _setupLSALogicInfrastructureWithSharesClean();
        uint256 sharesAmount = TC.STANDARD_COLLATERAL;
        uint256 slippageBps = TC.BPS_DENOMINATOR - TC.SLIPPAGE_SHARES_TO_ASSET; // 9900 bps = 99%

        // Calculate minimum: shares * 99% for a 1:1 vault
        uint256 minimum = (sharesAmount * slippageBps) / TC.BPS_DENOMINATOR;

        // Configure mock to return MORE than minimum (e.g., 100% of shares - above 99% minimum)
        uint256 aboveMinimum = sharesAmount; // Full amount, which is above the 99% minimum
        mockBTCVault.setMockRedeemReturn(aboveMinimum);

        // Act
        uint256 received =
            lsaHarness.exposed_redeemBTC(address(lsa), address(mockBTCVault), sharesAmount, recipient, slippageBps);

        // Assert - should succeed because received (100%) >= minimum (99%)
        assertEq(received, aboveMinimum, "should receive configured amount");
        assertGt(received, minimum, "received should exceed minimum threshold");
    }

    // ============================================================================
    // LSALogic Test Helpers
    // ============================================================================

    /// @notice Sets up basic LSALogic infrastructure for testing
    /// @dev Creates minimal mock infrastructure without deposits or funded accounts.
    ///      Use as base for tests that only need basic contract wiring.
    function _setupLSALogicInfrastructure() internal {
        // Deploy harness
        lsaHarness = new LSALogicHarness();

        // Deploy mock tokens
        mockCbBTC = new MockERC20("Coinbase BTC", "cbBTC", 8);
        mockUSDC = new MockERC20("USD Coin", "USDC", 6);

        // Deploy mock BTC vault first (needed for oracle constructor)
        mockBTCVault = new MockBTCVault(address(mockCbBTC), "BTC Vault", "bvBTC", 8);

        // Deploy mock oracle (needs btcVault and btc addresses)
        mockOracle = new MockPriceOracle(address(mockBTCVault), address(mockCbBTC));
        mockOracle.setAssetPrice(address(mockCbBTC), 100_000e8); // $100k BTC
        mockOracle.setAssetPrice(address(mockUSDC), 1e8); // $1 USDC
        mockOracle.setAssetPrice(address(mockBTCVault), 100_000e8); // $100k per share (1:1 vault)

        // Deploy mock addresses provider (with pool = address(0) for now)
        mockAddressesProvider = new MockAddressesProvider(address(0), address(mockOracle), address(this));

        // Deploy mock Bitmor pool
        mockBitmorPool = new MockBitmorLendingPool(address(mockAddressesProvider));
        mockAddressesProvider.setLendingPool(address(mockBitmorPool));

        // Deploy mock debt token (needs pool address)
        mockDebtToken = new MockVariableDebtToken(
            "Bitmor Variable Debt USDC", "variableDebtUSDC", 6, address(mockUSDC), address(mockBitmorPool)
        );

        // Initialize reserve with debt token
        mockBitmorPool.initReserve(address(mockUSDC), address(0), address(mockDebtToken));

        // Deploy LSA (LoanVault) and initialize with harness as owner
        lsa = new LoanVault();
        lsa.initialize(address(lsaHarness), borrower);

        // Fund infrastructure
        mockCbBTC.mint(address(mockBTCVault), TC.SWAP_ADAPTER_CBBTC_BALANCE);
    }

    /// @notice Sets up LSALogic infrastructure with a deposit to the lending pool
    /// @dev Extends base setup with aToken position in lending pool. Use for tests
    ///      requiring collateral state and lending pool interactions.
    function _setupLSALogicInfrastructureWithDeposit() internal {
        _setupLSALogicInfrastructure();

        // Deploy mock aToken for BTC vault
        MockAToken mockAToken =
            new MockAToken("Bitmor aToken bvBTC", "abvBTC", 8, address(mockBTCVault), address(mockBitmorPool));

        // Initialize reserve for BTC vault
        mockBitmorPool.initReserve(address(mockBTCVault), address(mockAToken), address(0));

        // Fund LSA with vault shares and deposit to pool
        mockBTCVault.mint(address(lsa), TC.STANDARD_COLLATERAL);

        // Approve and deposit via LSA execute
        bytes memory approveData =
            abi.encodeWithSignature("approve(address,uint256)", address(mockBitmorPool), TC.STANDARD_COLLATERAL);
        vm.prank(address(lsaHarness));
        lsa.execute(address(mockBTCVault), approveData);

        bytes memory depositData = abi.encodeWithSignature(
            "deposit(address,uint256,address,uint16)", address(mockBTCVault), TC.STANDARD_COLLATERAL, address(lsa), 0
        );
        vm.prank(address(lsaHarness));
        lsa.execute(address(mockBitmorPool), depositData);
    }

    /// @notice Sets up LSALogic infrastructure with shares in the LSA for redeem testing
    /// @dev WARNING: Creates intentional 2:1 asset-to-share ratio for slippage testing.
    ///      convertToAssets returns 2x share amount. Use _setupLSALogicInfrastructureWithSharesClean
    ///      when exact 1:1 calculations are required.
    function _setupLSALogicInfrastructureWithShares() internal {
        _setupLSALogicInfrastructure();

        // Mint vault shares directly to LSA
        mockBTCVault.mint(address(lsa), TC.STANDARD_COLLATERAL);

        // Fund vault with 2x underlying to intentionally create non-1:1 share ratio
        // This simulates scenario where convertToAssets returns more than shares amount
        mockCbBTC.mint(address(mockBTCVault), TC.STANDARD_COLLATERAL * 2);

        // Approve vault to spend shares from LSA (for redemption)
        bytes memory approveData =
            abi.encodeWithSignature("approve(address,uint256)", address(mockBTCVault), TC.STANDARD_COLLATERAL);
        vm.prank(address(lsaHarness));
        lsa.execute(address(mockBTCVault), approveData);
    }

    /// @notice Sets up LSALogic infrastructure with shares maintaining 1:1 share-to-asset ratio
    /// @dev Clean isolated setup (doesn't call base). Use for precise slippage calculations
    ///      where 1 share = 1 asset is required for predictable assertions.
    function _setupLSALogicInfrastructureWithSharesClean() internal {
        // Deploy harness
        lsaHarness = new LSALogicHarness();

        // Deploy mock tokens
        mockCbBTC = new MockERC20("Coinbase BTC", "cbBTC", 8);
        mockUSDC = new MockERC20("USD Coin", "USDC", 6);

        // Deploy mock BTC vault (empty - no underlying yet)
        mockBTCVault = new MockBTCVault(address(mockCbBTC), "BTC Vault", "bvBTC", 8);

        // Deploy mock oracle
        mockOracle = new MockPriceOracle(address(mockBTCVault), address(mockCbBTC));
        mockOracle.setAssetPrice(address(mockCbBTC), 100_000e8);
        mockOracle.setAssetPrice(address(mockBTCVault), 100_000e8);

        // Deploy mock addresses provider
        mockAddressesProvider = new MockAddressesProvider(address(0), address(mockOracle), address(this));

        // Deploy mock Bitmor pool
        mockBitmorPool = new MockBitmorLendingPool(address(mockAddressesProvider));
        mockAddressesProvider.setLendingPool(address(mockBitmorPool));

        // Deploy LSA (LoanVault) and initialize with harness as owner
        lsa = new LoanVault();
        lsa.initialize(address(lsaHarness), borrower);

        // Mint vault shares directly to LSA
        mockBTCVault.mint(address(lsa), TC.STANDARD_COLLATERAL);

        // Fund the vault with EXACTLY the amount needed for 1:1 ratio
        // Total shares = TC.STANDARD_COLLATERAL, total underlying = TC.STANDARD_COLLATERAL
        mockCbBTC.mint(address(mockBTCVault), TC.STANDARD_COLLATERAL);

        // Approve vault to spend shares from LSA (for redemption)
        bytes memory approveData =
            abi.encodeWithSignature("approve(address,uint256)", address(mockBTCVault), TC.STANDARD_COLLATERAL);
        vm.prank(address(lsaHarness));
        lsa.execute(address(mockBTCVault), approveData);
    }
}

// ============================================================================
// Helper Mock for LSALogic tests
// ============================================================================

import {MockAToken} from "../mock/MockAToken.sol";
