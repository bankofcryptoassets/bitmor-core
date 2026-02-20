// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {FuzzTestBase} from "./FuzzTestBase.sol";
import {FuzzConstants as FC} from "../helpers/FuzzConstants.sol";

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

/// @title LSAFuzzTestBase
/// @author Bitmor Protocol
/// @notice Shared base for LSALogic fuzz tests using a harness + mock BTC vault infrastructure
/// @dev Deploys LSALogicHarness, MockBTCVault, LoanVault (LSA), and mock lending pool
///      infrastructure for withdrawCollateral tests. Does NOT call super.setUp() since
///      LSALogic tests do not need AccessManager or the full unit test infrastructure.
abstract contract LSAFuzzTestBase is FuzzTestBase {
    // ============ Constants ============

    /// @dev Standard slippage for clean-vault tests: 95% (9500 BPS)
    uint256 internal constant STANDARD_SLIPPAGE = 95_00;

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

    /// @notice Deploys LSALogic harness, mock BTC vault, LoanVault, and lending pool infrastructure
    /// @dev Does NOT call super.setUp() — LSALogic tests don't need AccessManager or role actors
    function setUp() public virtual override {
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

        // Deploy lending pool infrastructure for withdrawCollateral tests
        _deployWithdrawalInfrastructure();
    }

    // ============ Internal Setup ============

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
}
