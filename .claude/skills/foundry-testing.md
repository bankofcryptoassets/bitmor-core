---
name: foundry-testing
description: Foundry test review and patterns for Bitmor Protocol
allowed-tools:
  - Read
  - Grep
  - Bash
---

When reviewing Foundry tests, check:

## Fork Testing Configuration

### Required Setup
- Tests must use Base Sepolia fork
- Fork URL: `base_sepolia` or `BASE_SEPOLIA_RPC_URL`
- Verify `--fork-block-number` for reproducibility

### Test Command
```bash
forge test --fork-url base_sepolia --fork-block-number <block>
```

## Test Structure

### Base Test Contracts
- Inherit from `BaseLoan.t.sol` for loan tests
- Inherit from `BaseTestForBTCVault.t.sol` for vault tests
- Use shared setup and helper functions

### Test Helpers (from BaseLoan.t.sol)
- `_createStandardLoan()` - Creates 1 BTC / 12 month loan
- `_captureTestSnapshot(lsa)` - Capture loan state before/after
- `_setupForMicroLiquidation(lsa)` - Setup overdue loan
- `_setupForFullLiquidation(lsa)` - Setup price-drop scenario

### Naming Convention
- `test_<functionName>_<scenario>` for passing tests
- `testFuzz_<functionName>` for fuzz tests
- `testFail_<functionName>` for expected failures
- `test_RevertWhen_<condition>` for revert tests

## Test Coverage

### Loan Lifecycle Tests
1. **Initialization**: `test_initializeLoan_*`
2. **Repayment**: `test_repayLoan_*`
3. **Closure**: `test_closeLoan_*`
4. **Liquidation**: `test_microLiquidation_*`, `test_fullLiquidation_*`

### Edge Cases to Verify
- Zero amount handling
- Maximum value boundaries
- Unauthorized caller scenarios
- Paused contract behavior
- Oracle price edge cases

### State Verification
- Use `assertEq` for exact matches
- Use `assertApproxEqAbs` for amounts with tolerance
- Verify events with `vm.expectEmit`
- Check storage changes explicitly

## Common Issues to Flag

### Missing Tests
- No fuzz testing for numerical inputs
- Missing revert condition tests
- No multi-user scenario tests
- Missing integration tests

### Test Quality
- Hardcoded magic numbers without explanation
- Tests that don't verify state changes
- Missing assertions on return values
- No cleanup in tearDown

### Fork Testing Issues
- Missing `--fork-url` in test commands
- Stale fork block numbers
- Tests dependent on specific chain state
