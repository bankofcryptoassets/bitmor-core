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
