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

## Key Patterns Discovered

### LendingPool Access Control (bitmorAccessCheck)
- `LendingPool.repay()` has `bitmorAccessCheck` modifier (line 305)
- `bitmorAccessCheck` requires `msg.sender == usdcVaultAddress || msg.sender == loanProvider`
- This is a GLOBAL restriction -- covers Path A of issue #124 by preventing ANY direct calls
- `_executeBorrow` additionally checks `msg.sender == getBitmorLoan()` (line 963)

### RepayLogic Caller Check Pattern
- RepayLogic.sol line 84-85: `if (loan.borrower != msg.sender && msg.sender != autoRepayer) revert`
- AutoRepayer is fetched via `BitmorAddressesProvider.getAutoRepayer()`
- This covers Path B of issue #124

### BitmorAddressesProvider Architecture
- New contract: `loan-provider/src/protocol/BitmorAddressesProvider.sol`
- Stores: LoanVaultFactory, Swapper, PremiumCollector, LiquidationFeeCollector, AutoRepayer
- Interface: `loan-provider/src/interfaces/IBitmorAddressesProvider.sol`
- Addresses stored in mapping by keccak256 key, access-controlled setters

### claimSurplusCollateral Pattern
- New function for borrower to claim remaining collateral after liquidation/completion
- Replaces auto-claim during liquidation/completion (prevents force-completion timing attack)
- Guards: status != Active, msg.sender == borrower, debt <= DEBT_DUST_THRESHOLD
- Dust debt (1-10 wei) handled during claim

### Micro-Liquidation Completion Pattern
- New `updateLoanForMicroLiquidationCompletion()` for duration==1 case
- Sets status to Completed (not Liquidated) -- correct distinction
- LPCM routes: `duration.sub(1) == 0` -> completion, else -> regular micro

### CRITICAL LESSON: checkTypeOfLiquidation Return Values Drive Routing
- Return 1 -> only `liquidationCall` works
- Return 2 -> only `microLiquidationCall` works
- NEVER change guard to return 1 for duration==1 unless full liquidation is intended

## Common Patterns
- RepayLogic caps transfer at min(amount, totalDebt), refunds excess
- LendingPool `bitmorAccessCheck` restricts deposit/repay to Loan + USDCVault
- LPCM runs via DELEGATECALL from LendingPool
- Duration clamp to 1 when debt remains but all periods covered
