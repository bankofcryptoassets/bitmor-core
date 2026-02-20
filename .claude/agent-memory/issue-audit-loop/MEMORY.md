# Issue Audit Loop - Agent Memory

## Audit History

### Issue #70 - Collateral Stuck in LSA on Last Micro-Liquidation (2026-02-19)
- Branch: `fix/vuln-8-collateral-stuck-last-microliq`
- Iteration 1: Initial audit - found H-01, M-01, M-02, L-01, I-01, I-02, I-03
- Iteration 2: Re-audit after fixes
  - H-01 (zero-balance revert) RESOLVED
  - M-01 fix INTRODUCED REGRESSION (C-01): `&& loanData.duration != 1` on line 132
  - M-02: ACCEPTED by user
- Iteration 3: Re-audit after C-01 fix - ALL CRITICAL/HIGH/MEDIUM RESOLVED
  - C-01/M-01 RESOLVED: `amountToBeDeducted = currentDebtBalance` when duration==1 (line 107)
  - Line 132 reverted to original (no duration!=1 exclusion)
  - Guard now correctly returns type 2 for duration==1 (aligned with LPCM)
  - H-01 still in place (getATokenAmount==0 early return)
  - Remaining: L-01 (defensive check), I-01 (missing event in LP ILoan), test gaps
  - APPROVED for merge
- Iteration 4 (2026-02-20): Final audit of all 8 fix implementations
  - All 8 findings (C-01, C-02, M-01, L-01, I-01, I-02, I-03, I-04) implemented correctly
  - 0 Critical, 0 High, 0 Medium, 2 Low (non-blocking), 4 Info
  - 127/127 loan-provider unit tests pass, 230/230 lending-pool tests pass
  - APPROVED for merge and PR creation

### CRITICAL LESSON: checkTypeOfLiquidation Return Values Drive Routing
- Return 1 -> only `liquidationCall` works (validateLiquidationCall requires type==1)
- Return 2 -> only `microLiquidationCall` works (validateMicroLiquidationCall requires type==2)
- `liquidationCall` ALWAYS calls `_updateLoanForFullLiquidation` (marks as Liquidated)
- `microLiquidationCall` has branching: duration==1 -> completion, else -> regular micro
- NEVER change guard to return 1 for duration==1 unless full liquidation is intended

## Common Patterns

### LendingPoolCollateralManager Flow
- LPCM runs via DELEGATECALL from LendingPool
- Micro-liquidation: seize collateral -> burn aTokens -> redeem bvBTC -> update loan state
- Full liquidation: same flow but with full debt coverage requirement
- State updates happen AFTER collateral operations

### Aave V2 Lending Pool Withdraw Validation
- `LendingPool.withdraw()` with `type(uint256).max` resolves to `userBalance`
- `ValidationLogic.validateWithdraw()` reverts if `amount == 0` (Error: VL_INVALID_AMOUNT)
- If all aTokens burned during liquidation, subsequent withdraw will revert

### Access Control for Liquidation Functions
- `updateLoanDataForMicroLiquidation`: LPCM role (id=2), no delay
- `updateLoanForMicroLiquidationCompletion`: LPCM role (id=2), no delay
- `updateLoanDataForFullLiquidation`: LPCM role (id=2), no delay
- LPCM role granted to LendingPoolCollateralManager contract

### Test Infrastructure Notes
- Pre-existing test failure: `Insurance.t.sol::test_insurance_initializeLoan_premiumAboveEstimate_dontRefundExcess`
- Liquidation tests: `test/unit/MicroLiquidation.t.sol`, `test/unit/FullLiquidation.t.sol`
- LiquidationUpdates tests: `test/unit/Loan/LiquidationUpdates.t.sol`
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

## Audit History

### Issue #88 (Finding #41) - AutoRepayment Token Rescue
- Branch: `fix/vuln-41-autorepayment-no-sweep`
- Iteration 1: 0C/0H/1M/2L/4I
- M-01: Excess refund test doesn't trigger the code path
- Status: Changes required (test coverage gap)
