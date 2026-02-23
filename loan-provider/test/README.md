# Bitmor Protocol Tests

## Directory Structure

```
test/
├── base/                    # Shared test base contracts
│   ├── BitmorTestBase.sol   # Core: AccessManager, roles, actors
│   ├── UnitTestBase.sol     # Unit tests: mocks, no external deps
│   ├── ForkTestBase.sol     # Fork tests: real Aave V3 from fork
│   └── IntegrationTestBase.sol  # Integration: pre-deployed contracts
├── unit/                    # Unit tests (mocks, fast)
│   ├── Loan/                # Loan contract tests
│   ├── Vault/               # Vault contract tests
│   └── Sample/              # Example tests
├── fork/                    # Fork tests (real protocols)
├── integration/             # Integration tests (requires deploy-local)
├── fuzz/                    # Fuzz tests (randomized inputs)
├── invariant/               # Invariant tests (state properties)
└── mock/                    # Mock contracts
    ├── MockAaveV3Pool.sol   # Flash loan mock
    └── MockERC20.sol        # Configurable ERC20 mock
```

## Test Modes

| Mode        | Command                   | Aave V3       | lending-pool   | loan-provider |
| ----------- | ------------------------- | ------------- | -------------- | ------------- |
| Unit        | `make test:unit`          | Mock          | Mock           | Fresh         |
| Fork        | `make test:fork`          | Real (forked) | Mock           | Fresh         |
| Integration | `make test:integration`   | Pre-deployed  | Pre-deployed   | Pre-deployed  |
| Fuzz        | `make test:fuzz`          | Mock          | Mock           | Fresh         |
| Invariant   | `make test:invariant`     | Mock          | Mock           | Fresh         |

## Running Tests

### Unit Tests (Default)

```bash
make test:unit   # All unit tests
make test:loan:unit           # Loan tests only
make test:vault:unit          # Vault tests only
make test:single TEST=test_functionName  # Single test
```

#### Flow

Either deploy or use the pre-deployed ones if no change in the contracts.

##### Testing Loan
- Deploy Access Manager
- Deploy Vault: BTC Vault
- Deploy mock oracles
- Deploy Lending Pool with USDC and bvBTC (BTC Vault shares) as reserve.
- Deploy Vault: USDC vault with lending pool.
- Deploy Loan with the above deployments.

#### Testing Vault
- Deploy Access Manager
- Deploy Vault: BTC Vault
- Deploy mock oracles
- Deploy Lending Pool
- Deploy Vault: USDC vault with lending pool.

#### Testing Lending Pool
- Deploy Vault: BTC
- Deploy Lending Pool with USDC and bvBTC as reserve
- Deploy Vault: USDC


### Fork Tests

Requires `BASE_SEPOLIA_RPC_URL` in `.env`:
```bash
make test:fork
```

### Integration Tests

Requires `make deploy-local` first:
```bash
# Terminal 1
make anvil              # from repo root

# Terminal 2
make deploy-local       # from repo root

# Terminal 3 (from loan-provider/)
make test:integration
```

## Base Class Hierarchy (DRY through Inheritance)

```
Test (forge-std)
└── BitmorTestBase           # AccessManager, roles, actors, _scheduleAndExecute()
    ├── UnitTestBase         # Mocks, token helpers (_fundUSDC, _fundCbBTC)
    │   └── LoanUnitTestBase # Full Loan infrastructure, _createStandardLoan()
    ├── ForkTestBase         # Real Aave from fork, _dealToken()
    └── IntegrationTestBase  # Pre-deployed contracts from JSON
```

**Key:** Each child inherits ALL parent functionality. No duplication needed.

| What you get from...  | Functionality                                                    |
| --------------------- | ---------------------------------------------------------------- |
| `BitmorTestBase`      | `manager`, `rolesData`, all role actors, `_scheduleAndExecute()` |
| `UnitTestBase`        | Above + `mockAavePool`, `mockCbBTC`, `mockUSDC`, `_fundUSDC()`   |
| `LoanUnitTestBase`    | Above + `loan`, all mocks, `_createStandardLoan()`, `_dropOraclePrice()` |
| `ForkTestBase`        | BitmorTestBase + real tokens, `_dealToken()`, FFI                |
| `IntegrationTestBase` | BitmorTestBase + `loanContract`, `bitmorPool` from JSON          |

## Writing Tests

### Unit Test Example

```solidity
import {UnitTestBase} from "../../base/UnitTestBase.sol";

contract MyTest is UnitTestBase {
    function test_example() public {
        _fundUSDC(testUser, 1000e6);
        // ... test logic
    }
}
```

### Fork Test Example

```solidity
import {ForkTestBase} from "../../base/ForkTestBase.sol";

contract MyForkTest is ForkTestBase {
    function test_withRealAave() public {
        _dealToken(address(usdc), testUser, 1000e6);
        // ... test against real Aave
    }
}
```

### Integration Test Example

```solidity
import {IntegrationTestBase} from "../../base/IntegrationTestBase.sol";

contract MyIntegrationTest is IntegrationTestBase {
    function test_withPreDeployed() public {
        // loanContract, bitmorPool already available
        // ... test against deployed system
    }
}
```

## Role Testing

BitmorTestBase provides dynamic role accessors from RolesData:

```solidity
// Role IDs - call as functions
uint64 executorId = EXECUTOR_ID();
uint64 lpcmId = LPCM_ID();
uint64 bvmSlowId = BVM_SLOW_ID();

// Role actors - available as state variables
address executor;   // EXECUTOR role
address lpcm;       // LPCM role
address bvm_slow;   // BVM_SLOW role
// ... etc

// Execute with role delay
_scheduleAndExecute(
    target,
    bvm_slow,
    BVM_SLOW_ID(),
    abi.encodeCall(Contract.function, (args))
);
```
