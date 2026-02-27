# Issue Launcher - Agent Memory

## Branch Naming Patterns
- Security/vulnerability fixes: `fix/vuln-<vuln-number>-<short-description>` (e.g., `fix/vuln-6-double-counting-utilization`)
- Base branch for security fixes: `fix/contracts`
- Branch creation via `gh issue develop <number> --repo bankofcryptoassets/bitmor-core --base <base-branch> --name <branch-name>`

## Common Issue Categories
- Vulnerability fixes (labeled: bug, security, severity: high/critical) -> `lending-pool/` or `loan-provider/`
- Interest rate strategy issues -> `lending-pool/contracts/protocol/lendingpool/`
- Vault strategy issues -> `loan-provider/src/vaults/`

## Key File Relationships
- `USDCReserveInterestRateStrategy.sol` is called from `ReserveLogic.sol` via `IReserveInterestRateStrategy` interface
- `USDCVault.totalAssets()` chains to `USDCStrategy.totalAssets()` -> `_getTotalBalanceInMarkets()` -> `_getBalanceInAave() + _getBalanceInBLP()`
- `_getBalanceInBLP()` returns aToken balance (full deposit claim, including lent-out portion)
- Deployment routing: strategy name `rateStrategyUSDC` -> `deployUSDCReserveInterestRateStrategy()` in `helpers/contracts-deployments.ts`

## Lending Pool Testing
- Tests are Hardhat/TypeScript in `lending-pool/test-suites/test-aave/`
- `MockUSDCVault` at `lending-pool/contracts/mocks/vault/MockUSDCVault.sol` uses 1:1 share ratio, deposits 100% to BLP
- Test helper: `make-suite.ts` sets up `testEnv` with `mockBitmorUSDCVault`
- `usdc-rate-strategy.spec.ts` tests the 6-param and 8-param `calculateInterestRates` functions
- The 6-param tests use `dai` as the reserve address (not USDC) to bypass the `require(reserve != vault.asset(), "WA")` check
- Rate strategy params defined in `markets/bitmor/rateStrategies.ts`

## Collateral Recovery Patterns
- `LSALogic.claimRemainingCollateral()` already exists for micro-liquidation completion (withdraws aTokens -> redeems bvBTC -> sends cbBTC to borrower)
- `RepayLogic.executeRepay()` handles full repayment collateral return inline (withdraw + redeem to borrower)
- `LendingPoolCollateralManager.liquidationCall()` only seizes `maxCollateralToLiquidate` (debt + bonus), leaving surplus in LSA
- After `updateLoanDataForFullLiquidation()` marks status as `Liquidated`, no existing function allows surplus withdrawal
- The LSA's `execute()` is `onlyOwner` (Loan contract), so borrower cannot call it directly

## Cross-Module Interface Pattern
- `lending-pool/contracts/interfaces/ILoan.sol` (Solidity 0.6.12) must mirror loan-provider `ILoan.sol` (0.8.30)
- When adding new functions callable from lending-pool, BOTH interfaces must be updated
- `lending-pool/contracts/mocks/MockLoan.sol` must also implement any new ILoan functions

## Loan Provider Interest Rate Paths
- `executeInitializeLoan` -> `_calculateLoanAmountAndMonthlyPayment` -> fetches `getMaxVariableBorrowRate()` from strategy
- `getLoanDetails` preview -> `calculateLoanDetails` -> reads `reserveData.currentVariableBorrowRate` (BUG: vuln-38)
- `getMaxVariableBorrowRate()` = baseRate + slope1 + slope2 (rate at 100% utilization)
- `currentVariableBorrowRate` = what the pool currently stores (utilization-dependent, typically lower)
- Mock USDC strategy: `MockUSDCInterestRateStrategy` registered via `initReserveWithStrategy()` in `LoanUnitTestBase`
- Mock USDC default currentVariableBorrowRate: 0.05e27 (5%) vs max: 0.81e27 (81%)

## Testing Gotchas
- `ViewFunctions.t.sol` line 101: monthly payment only asserts `> 0`, does NOT check exact equality with preview
- `getLoanDetails()` used widely for `minDeposit` value; loan amount and minDeposit are rate-independent
- Only `monthlyPayment` (EMI) depends on the interest rate source

## Liquidation Logic (LoanLiquidationLogic)
- `checkTypeOfLiquidation` in `LoanLiquidationLogic.sol` determines liquidation type (0/1/2)
- After vuln-21 fix: uses `Helpers.getUserCurrentCollateral(user, collateralReserve)` (aToken balance) instead of stale `loanData.btcAmount`
- `_calculateAvailableCollateralToLiquidate` in `LendingPoolCollateralManager.sol` and `checkTypeOfLiquidation` use mathematically equivalent collateral checks -- if type 2 passes, capping won't trigger in execution
- bvBTC liquidation bonus: 10500 (5%), USDC: 10300 (3%)
- Oracle prices in tests: cbBTC=$100,000, USDC=$1 (8 decimal oracle, via `MOCK_CHAINLINK_AGGREGATORS_PRICES`)
- `validateMicroLiquidationCall` check order: active reserve -> type==2 check (error 82) -> collateral enabled (error 43) -> has debt (error 83)
- Tests that mismatch mockLoan data vs real pool positions will break after vuln-21 fix -- always align mock btcAmount with actual deposits

## Micro-Liquidation Tests
- `micro-liquidation.spec.ts` in `test-suites/test-aave/`
- `setupUserWithDebt()`: deposits bvBTC + borrows USDC for checkTypeOfLiquidation tests only
- `setupUserWithVaultDebt()`: deposits via mockLoanProvider for execution tests (CollateralManager calls IERC4626.redeem())
- `test-bitmor/` directory does not exist -- `npm run test-bitmor` will fail (pre-existing)

## Repay Access Control (Issue #124)
- `Loan.repay()` has NO `msg.sender` check -- only `whenNotPaused` + `nonReentrant` (line 164-177)
- `CloseLoanLogic` enforces `loan.borrower != msg.sender` -> `Errors.UnauthorizedCaller()` (line 124)
- `LoanLogic.executeClaimRemainingCollateral` enforces `msg.sender != borrower` -> `Errors.Loan__OnlyBorrower()` (line 400)
- `RepayLogic.executeRepay()` uses `msg.sender` for `safeTransferFrom` (line 89) and refund (line 134) but no ownership check
- `AutoRepayment.sol` calls `ILoan(i_LOAN).repay()` -- will need whitelisting if repay is restricted
- `LendingPool.repay()` (0.6.12) is fully permissionless -- any caller can repay `onBehalfOf` any address
- `_addressesProvider.getBitmorLoan()` already exists in LendingPool for borrow access control (line 875)
- New error code needed in lending-pool: next available after "89" is "90"

## Git Config Issue
- Empty branch name config entries (`branch..gh-merge-base`) can appear from `gh issue develop` -- clean with `git config --local --unset 'branch..gh-merge-base'`
