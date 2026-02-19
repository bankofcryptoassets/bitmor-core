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

## Git Config Issue
- Empty branch name config entries (`branch..gh-merge-base`) can appear from `gh issue develop` -- clean with `git config --local --unset 'branch..gh-merge-base'`
