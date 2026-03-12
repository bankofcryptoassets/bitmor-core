# Issue Audit Loop - Agent Memory

## Audit History

### Issue #70 - Collateral Stuck in LSA on Last Micro-Liquidation (2026-02-19)
- Branch: `fix/vuln-8-collateral-stuck-last-microliq`
- APPROVED after 4 iterations

### Issue #88 (Finding #41) - AutoRepayment Token Rescue
- Branch: `fix/vuln-41-autorepayment-no-sweep`
- Status: Changes required (test coverage gap)

### Issue #75 (Finding #21) - Stale btcAmount in checkTypeOfLiquidation
- Branch: `fix/vuln-21-stale-collateral-amount`
- Status: Changes required (harness/fuzz test breakage)

### Issue #124 - Permissionless Repay Desynchronizes Loan State (2026-02-27)
- Branch: `fix/vuln-124-permissionless-repay-desync`
- Iteration 1: See report below

### Issue #111 - Oracle Freshness Validation (#14) (2026-03-01)
- Branch: `fix/issue111`
- Iterations 1-3: CHANGES REQUIRED
- Iteration 4: APPROVED (all production code secure, fuzz test vm.warp fix applied by auditor)
- Files: AaveOracle.sol, PythPriceOracleGetter.sol, IPriceOracleGetter.sol, IChainlinkAggregator.sol, AaveOracleHarness.sol, MockAggregator.sol, AaveOracle.fuzz.t.sol
- Key changes: latestRoundData() staleness check, Pyth fallback oracle, interface expansion

## Key Patterns Discovered

### LendingPool Access Control (bitmorAccessCheck)
- `LendingPool.repay()` has `bitmorAccessCheck` modifier (line 305)
- `bitmorAccessCheck` requires `msg.sender == usdcVaultAddress || msg.sender == loanProvider`
- `_executeBorrow` additionally checks `msg.sender == getBitmorLoan()` (line 963)

### AaveOracle Staleness Check Pattern
- `_getAssetPrice()` uses `latestRoundData()` (not `latestAnswer()`)
- Correct logic: `price > 0 && updatedAt > block.timestamp - MAX_STALENESS`
- GOTCHA: Solidity 0.6.12 underflow when block.timestamp < MAX_STALENESS (3600)
  - Not production issue but breaks Foundry tests (default block.timestamp = 1)
  - Fix: add vm.warp(100_000) to fuzz test setUp()

### PythPriceOracleGetter Pattern
- Uses `getPriceNoOlderThan(source, MAX_STALENESS)` -- Pyth handles staleness natively
- Price conversion: `(uint64(price.price) * PRICE_PRECISION) / (10 ** uint32(-1 * expo))`
- Has `require(price.price > 0)` check
- No explicit expo < 0 check; positive expo wraps via uint32 and reverts (fail-safe)
- IS the terminal oracle. getFallbackOracle() returns address(0) by design.
- setFallbackOracle() reverts with "PythPriceOracleGetter__FallbackOracleNotSupported"
- Dead code removed: no fallback oracle call in _getAssetPrice (reverts instead)

### CRITICAL LESSON: checkTypeOfLiquidation Return Values Drive Routing
- Return 1 -> only `liquidationCall` works
- Return 2 -> only `microLiquidationCall` works

## Common Patterns
- RepayLogic caps transfer at min(amount, totalDebt), refunds excess
- LendingPool `bitmorAccessCheck` restricts deposit/repay to Loan + USDCVault
- LPCM runs via DELEGATECALL from LendingPool
- Duration clamp to 1 when debt remains but all periods covered
