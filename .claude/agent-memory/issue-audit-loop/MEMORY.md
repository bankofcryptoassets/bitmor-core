# Issue Audit Loop - Agent Memory

## Key Patterns Discovered

### RepayLogic caps transfer at min(amount, totalDebt)
- `RepayLogic.executeRepay` at `src/libraries/logic/RepayLogic.sol:74` caps `maxRepayableAmt = min(amount, totalDebt)`
- Only pulls `maxRepayableAmt` from caller, not the full `amount`
- If amount > totalDebt, the difference stays with the caller (e.g., AutoRepayment)
- Refunds `maxRepayableAmt - finalAmountRepaid` back to `msg.sender`
- This means excess refund tests must use `amount > totalDebt` to trigger the excess path

### MockBitmorLendingPool behavior
- `repay()` caps at `currentDebt` (line 184-186 in mock)
- Has `_repaymentShortfall` mechanism for simulating pool returning less
- Use `setRepaymentShortfall()` in tests when needed

### Common test anti-patterns found
- Generic `vm.expectRevert()` for AccessManaged unauthorized checks (should use specific selector)
- False positive tests that pass without exercising the code path under test (e.g., excess refund tests where amount < totalDebt)

### Pre-existing issues (not in scope for individual PRs)
- `AutoRepayment` constructor has no zero-address validation for `_loan` and `_debtAsset` immutables
- `Insurance.t.sol:test_insurance_initializeLoan_premiumAboveEstimate_dontRefundExcess` is a known failing test

### Access Control Architecture
- ARE role (ID: 4) is EOA, no delay, no guardian -- suitable for bot operations
- Rescue/sweep functions assigned to same role as operational functions is acceptable when contract normally holds zero funds
- For higher security: separate admin role with timelock for rescue operations

### Lending-pool Foundry test infrastructure
- `lending-pool/` has `foundry.toml` but requires manual `forge install foundry-rs/forge-std` to get lib
- Fuzz tests in `test-foundry/fuzz/` use interfaces to interact with harness contracts (cross-version workaround: tests >=0.8.13, contracts 0.6.12)
- Harness contracts in `contracts/test-harness/` expose internal library functions
- When adding new reads from ReserveData fields, harness MUST have a setter for that field

### LoanLiquidationLogic pattern: live balance vs stale LoanData
- `checkTypeOfLiquidation()` should always read live on-chain state for collateral and debt
- `loanData.collateralAmount` is set once at creation and never updated after micro-liquidations
- Fix pattern: use `Helpers.getUserCurrentCollateral(user, reserve)` which reads `aTokenAddress.balanceOf(user)`
- `Helpers.getUserCurrentDebt(user, reserve)` was already used for debt -- collateral was the gap

## Audit History

### Issue #88 (Finding #41) - AutoRepayment Token Rescue
- Branch: `fix/vuln-41-autorepayment-no-sweep`
- Iteration 1: 0C/0H/1M/2L/4I
- M-01: Excess refund test doesn't trigger the code path
- Status: Changes required (test coverage gap)

### Issue #75 (Finding #21) - Stale collateralAmount in checkTypeOfLiquidation
- Branch: `fix/vuln-21-stale-collateral-amount`
- Iteration 1: 0C/1H/0M/1L/3I
- H-01: Fuzz test harness missing `setReserveAToken` -- 5/10 fuzz tests fail
- Hardhat tests: all 12 micro-liquidation tests pass including vuln-21 specific test
- Status: Changes required (harness/fuzz test breakage)
