---
description: Bitmor protocol testing patterns, base classes, and mock infrastructure for loan-provider tests. Apply when writing tests in loan-provider/test/.
---

## 1. Directory Structure

```
loan-provider/test/
├── base/              # 5 base classes (inherit from these)
│   ├── BitmorTestBase.sol      # Tier 0: AccessManager, roles, actors
│   ├── UnitTestBase.sol        # Tier 1: Mock externals (Aave, tokens)
│   ├── LoanUnitTestBase.sol    # Tier 2: Full Loan infrastructure
│   ├── ForkTestBase.sol        # Fork: Real Aave V3 on fork
│   └── IntegrationTestBase.sol # Integration: Pre-deployed contracts
├── unit/              # Unit test files
│   ├── Loan/          # Loan contract tests
│   ├── Vault/         # BTC/USDC vault tests
│   └── Sample/        # Template for new tests
├── fork/              # Fork tests (require RPC)
├── fuzz/              # Fuzz tests
├── invariant/         # Invariant tests
├── harness/           # Harness contracts for internal functions
├── mock/              # 20 mock contracts
└── helpers/           # TestConstants.sol
```

## 2. Base Class Inheritance (Tier System)

```
BitmorTestBase (Tier 0)
│   └─ AccessManager, 16 role actors, _scheduleAndExecute()
│
├── UnitTestBase (Tier 1)
│   │   └─ MockAaveV3Pool, MockERC20, _fundUSDC(), _fundCbBTC()
│   │
│   └── LoanUnitTestBase (Tier 2)
│           └─ Loan contract, 20 mocks, all loan helpers
│
├── ForkTestBase (Fork Tier)
│       └─ Real Aave V3 on fork, FFI deployment
│
└── IntegrationTestBase (Integration Tier)
        └─ Loads from deployments.json
```

### Choose the Right Base Class

| Test Type                 | Base Class                         | When to Use                                    |
| ------------------------- | ---------------------------------- | ---------------------------------------------- |
| Loan unit tests           | `LoanUnitTestBase`                 | Testing Loan.sol with mocks                    |
| Loan tests with snapshots | `BaseLoanTest`                     | Extends LoanUnitTestBase with snapshot structs |
| Vault unit tests          | `UnitTestBase`                     | Testing BTCVault, USDCVault                    |
| Fork tests                | `ForkTestBase`                     | Testing against real forked Aave               |
| Pre-deployed contracts    | `IntegrationTestBase`              | After `make deploy-local`                      |
| New test template         | Copy `Sample/SampleUnitTest.t.sol` | Starting point                                 |

## 3. Test Constants (TestConstants.sol)

**Always import as `TC`:**

```solidity
import {TestConstants as TC} from "../helpers/TestConstants.sol";
```

### Test Funding

```solidity
TC.USER_USDC_BALANCE          // 1_000_000e6 (1M USDC)
TC.USER_CBBTC_BALANCE         // 10e8 (10 BTC)
TC.LENDING_POOL_USDC_BALANCE  // Pool liquidity
TC.LENDING_POOL_CBBTC_BALANCE // Pool liquidity
TC.SWAP_ADAPTER_CBBTC_BALANCE // Swap adapter funding
TC.SWAP_ADAPTER_USDC_BALANCE  // Swap adapter funding
```

### Standard Scenarios

```solidity
TC.STANDARD_COLLATERAL  // 1e8 (1 BTC)
TC.MIN_COLLATERAL       // 0.01e8
TC.MAX_COLLATERAL       // 10e8
TC.STANDARD_DURATION    // 12 months
TC.PREMIUM_AMOUNT       // Standard premium
TC.MIN_DEPOSIT          // Minimum deposit BPS
```

### Liquidation

```solidity
TC.LIQUIDATION_TYPE_NONE   // 0
TC.LIQUIDATION_TYPE_FULL   // 1
TC.LIQUIDATION_TYPE_MICRO  // 2
TC.PRICE_DROP_MICRO        // 15%
TC.PRICE_DROP_FULL         // 50%
```

### Precision & Time

```solidity
TC.RAY              // 1e27
TC.BPS_DENOMINATOR  // 10000
TC.ONE_DAY          // 1 days
TC.ONE_MONTH        // 30 days
```

## 4. Mock Infrastructure (20 Mocks)

### Core Mocks (LoanUnitTestBase)

| Mock                  | Variable                | Key Methods                                                                    |
| --------------------- | ----------------------- | ------------------------------------------------------------------------------ |
| MockBitmorLendingPool | `mockBitmorPool`        | `supply()`, `borrow()`, `repay()`, `setLiquidationType()`, `setHealthFactor()` |
| MockAaveV3Pool        | `mockAavePool`          | `flashLoanSimple()`                                                            |
| MockAddressesProvider | `mockAddressesProvider` | `getLendingPool()`, `setBitmorLoan()`                                          |
| MockPriceOracle       | `mockOracle`            | `getAssetPrice()`, `setAssetPrice()`, `dropPrice()`                            |

### Token Mocks

| Mock                  | Variable            | Purpose                         |
| --------------------- | ------------------- | ------------------------------- |
| MockERC20             | `mockUSDC`          | Debt asset (6 decimals)         |
| MockERC20             | `mockCbBTC`         | Underlying BTC (8 decimals)     |
| MockBTCVault          | `mockBTCVault`      | Collateral vault (bvBTC shares) |
| MockUSDCVault         | `mockUSDCVault`     | USDC vault                      |
| MockAToken            | `mockATokenBvBTC`   | Collateral aToken               |
| MockVariableDebtToken | `mockDebtTokenUSDC` | Debt tracking                   |

### Test Control Methods (MockBitmorLendingPool)

```solidity
mockBitmorPool.setLiquidationType(lsa, type)      // 0=none, 1=full, 2=micro
mockBitmorPool.setUserOverdue(lsa, true)          // Mark as overdue
mockBitmorPool.setHealthFactor(lsa, 0.5e18)       // Set health factor
mockBitmorPool.setVariableBorrowRate(asset, rate) // Interest rate (RAY)
mockBitmorPool.setInsuranceId(lsa, id)            // Insurance ID
```

## 5. Test Helpers Reference

### Loan Creation (LoanUnitTestBase)

```solidity
_createStandardLoan()                      // 1 BTC, 12 months → returns lsa
_createLoan(collateral, duration, premium) // Custom params → returns lsa
_createLoanWithData(collateral, duration, premium)  // → (lsa, loanData)
```

### Funding (UnitTestBase)

```solidity
_fundUSDC(address, amount)   // Mint USDC
_fundCbBTC(address, amount)  // Mint cbBTC
```

### Oracle Manipulation (LoanUnitTestBase)

```solidity
_dropOraclePrice(percent)    // Drop BTC price by %
_setBtcPrice(price)          // Set exact BTC price
```

### Liquidation (LoanUnitTestBase)

```solidity
_setLiquidationType(lsa, type)  // Direct control
_getLiquidationType(lsa)        // Check current type
```

### Time (LoanUnitTestBase)

```solidity
_advanceDays(days)  // Warp forward N days
_makeOverdue()      // Warp past grace period
```

### State Isolation (UnitTestBase)

```solidity
_resetState()  // Revert to snapshot for fresh state
```

### Role Operations (BitmorTestBase)

```solidity
_scheduleAndExecute(target, actor, roleId, data)  // Handle delayed ops
_configureLoanParameters(loan, max, min, slippage, deposit)
```

## 6. Access Control Patterns

### Role ID Caching (Important!)

Cache role IDs **before** `vm.prank()` to avoid consuming the prank:

```solidity
// WRONG - prank consumed by external call in EXECUTOR_ID()
vm.prank(admin);
manager.grantRole(EXECUTOR_ID(), borrower, NO_DELAY);

// CORRECT - cache before prank
uint64 executorRoleId = EXECUTOR_ID();
vm.prank(admin);
manager.grantRole(executorRoleId, borrower, NO_DELAY);
```

### Delayed Operations

Use `_scheduleAndExecute()` for time-delayed role operations:

```solidity
// Unpause requires LPM_SLOW role with 1-day delay
bytes memory data = abi.encodeCall(loan.unpause, ());
_scheduleAndExecute(address(loan), lpm_slow, LPM_SLOW_ID(), data);
```

## 7. Common Test Patterns

### Standard Loan Test

```solidity
function test_RepayLoan_DecreasesDebt() public {
    // Arrange
    address lsa = _createStandardLoan();
    uint256 debtBefore = _getDebtBalance(lsa);
    DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);

    // Act
    vm.prank(user);
    loan.repay(lsa, loanData.estimatedMonthlyPayment);

    // Assert
    uint256 debtAfter = _getDebtBalance(lsa);
    assertLt(debtAfter, debtBefore, "debt should decrease after repayment");
}
```

### Liquidation Test

```solidity
function test_FullLiquidation_WhenPriceDrops() public {
    // Arrange
    address lsa = _createStandardLoan();
    _dropOraclePrice(TC.PRICE_DROP_FULL);
    mockBitmorPool.setHealthFactor(lsa, 0.5e18);
    _setLiquidationType(lsa, TC.LIQUIDATION_TYPE_FULL);
    _fundLiquidator();

    // Act
    vm.prank(liquidator);
    mockBitmorPool.liquidationCall(
        address(mockBTCVault),
        address(mockUSDC),
        lsa,
        type(uint256).max,
        false
    );

    // Assert
    DataTypes.LoanData memory loanData = loan.getLoanByLSA(lsa);
    assertEq(
        uint256(loanData.status),
        uint256(DataTypes.LoanStatus.Liquidated),
        "loan should be liquidated"
    );
}
```

### Revert Test

```solidity
function test_RevertWhen_InsufficientDeposit() public {
    // Arrange
    (,, uint256 minDeposit) = loan.getLoanDetails(TC.STANDARD_COLLATERAL, TC.STANDARD_DURATION);
    uint256 tooSmallDeposit = minDeposit - 1;

    // Assert + Act
    vm.expectRevert(Errors.Loan__InsufficientDeposit.selector);
    vm.prank(user);
    loan.initializeLoan(
        tooSmallDeposit,
        TC.PREMIUM_AMOUNT,
        TC.STANDARD_COLLATERAL,
        TC.STANDARD_DURATION,
        ""
    );
}
```

## 8. File Organization

### Loan Tests (test/unit/Loan/)

| File                       | Purpose                                                |
| -------------------------- | ------------------------------------------------------ |
| `BaseLoan.t.sol`           | Shared base with snapshot structs (inherit, don't run) |
| `InitializeLoan.t.sol`     | Loan creation tests                                    |
| `RepayLoan.t.sol`          | Monthly repayment tests                                |
| `CloseLoan.t.sol`          | Loan closure tests                                     |
| `LoanContract.t.sol`       | Core functionality                                     |
| `AdminSetters.t.sol`       | Parameter configuration                                |
| `LiquidationUpdates.t.sol` | Liquidation state updates                              |
| `PauseUnpause.t.sol`       | Pause/unpause controls                                 |
| `ViewFunctions.t.sol`      | Read-only functions                                    |

### Creating New Tests

1. Copy `test/unit/Sample/SampleUnitTest.t.sol` as template
2. Choose appropriate base class
3. Follow naming: `test_FunctionName_Scenario()`
4. Follow naming for revert: `test_FunctionName_Revert[When][If]_Condition()`
5. Use TC constants, never magic values
6. Include descriptive assertion messages
