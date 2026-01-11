# AGENTS.md

This repository has two independent smart-contract workspaces:
- `lending-pool/`: Hardhat + TypeScript (Aave V2 + Bitmor integration)
- `loan-provider/`: Foundry + Solidity (Bitmor loan system)

Use the commands and style rules below when operating in each workspace.

## Build / Lint / Test

### Hardhat (lending-pool/)
- Install deps: `npm install`
- Compile: `npm run compile`
- Format check (Prettier): `npm run prettier:check`
- Format write (Prettier): `npm run prettier:write`
- Full Aave test suite: `npm test` or `npm run test`
- Bitmor tests: `npm run test-bitmor`
- AMM tests: `npm run test-amm`
- Scenario tests: `npm run test-scenarios`
- Coverage (legacy): `npm run dev:coverage`
- Clean build artifacts: `npm run ci:clean`
- Run a Hardhat task: `npm run hardhat -- <task>`

Single-test examples (Hardhat):
- One file: `TS_NODE_TRANSPILE_ONLY=1 npx hardhat test test-suites/test-aave/<file>.spec.ts`
- One file (Bitmor): `TS_NODE_TRANSPILE_ONLY=1 npx hardhat test test-suites/test-bitmor/<file>.spec.ts`
- One test by grep (Mocha): `TS_NODE_TRANSPILE_ONLY=1 npx hardhat test test-suites/test-aave/<file>.spec.ts --grep "name"`

Environment:
- `lending-pool/.env` is required for network runs (see `CLAUDE.md`).
- Common keys: `MNEMONIC`, `ALCHEMY_KEY`, `INFURA_KEY`, `ETHERSCAN_KEY`.
- Forked runs use `FORK=main` or `FORK=kovan` environment variables.
- Local scripts often set `SKIP_LOAD=true` during compile.

### Foundry (loan-provider/)
- Build: `forge build` or `make build`
- Test (forked Base Sepolia): `forge test --fork-url base_sepolia`
- Test via Makefile: `make test`
- Format (Solidity): `forge fmt` or `make format`
- Snapshot: `forge snapshot` or `make snapshot`
- Gas report: `make gasReport`
- Coverage: `make coverage`
- Security profile build: `FOUNDRY_PROFILE=security forge build`

Environment:
- RPC endpoints come from `.env` (`BASE_SEPOLIA_RPC_URL`, `BASE_RPC_URL`, `MAINNET_RPC_URL`).
- `loan-provider/foundry.toml` sets fork defaults and filesystem permissions.

Single-test examples (Foundry):
- Match test name: `forge test --mt test_<name> --fork-url base_sepolia`
- Match test file: `forge test --match-path test/<File>.t.sol --fork-url base_sepolia`
- Verbose single test: `forge test --mt test_<name> --fork-url base_sepolia -vvvv`

Makefile shortcuts (loan-provider/Makefile):
- `make testLoanInitialization`, `make testRepay`, `make testCloseLoan`
- `make testCreateAutoRepayment`, `make testExecuteRepayment`

### Linting
- There is no dedicated lint script; use Prettier and existing configs.
- TypeScript lint rules are in `lending-pool/tslint.json` (Prettier-enforced).
- Optional TSLint run: `npx tslint -p lending-pool/tsconfig.json -c lending-pool/tslint.json`.
- Pre-commit hook runs `pretty-quick` on staged files.

## Code Style Guidelines

### General
- Keep changes localized and avoid cross-directory churn.
- Prefer existing helpers/utilities instead of new duplicates.
- Keep functions focused; split large logic into helpers/libraries.
- Follow `.editorconfig` defaults for non-Prettier files.
- Do not add inline comments unless explicitly requested.

### TypeScript (lending-pool/)
- Formatting is enforced via Prettier:
  - `printWidth`: 100
  - `tabWidth`: 4
  - `semi`: true
  - `singleQuote`: false (use double quotes)
- TypeScript settings are strict (`strict: true`) in `lending-pool/tsconfig.json`.
- Prefer `async/await` over raw Promise chains.
- Use explicit return types for exported/public helpers.
- Reuse domain types (`tEthereumAddress`, `eContractid`, etc.) from `helpers/types`.
- Use `BigNumber` / `BigNumberish` consistently with `ethers` utilities.
- Imports:
  - Group external imports first, then internal modules.
  - Use named imports (`import { X } from "..."`) where possible.
  - Keep import lists sorted for readability.
- Naming:
  - `camelCase` for variables/functions.
  - `PascalCase` for types, classes, and enums.
  - `UPPER_SNAKE_CASE` for constants.
- Error handling:
  - Validate inputs early with guards (e.g., `notFalsyOrZeroAddress`).
  - Prefer returning typed errors over silent failures.

### Solidity (lending-pool/ + loan-provider/)
- Always include SPDX + `pragma` at the top of files.
- Formatting:
  - Solidity is formatted by Prettier/Foundry; keep print width ~100.
  - Use consistent indentation (follow file-local style).
- Imports:
  - Use explicit named imports (`import {Contract} from "..."`).
  - Group OpenZeppelin/external imports before internal ones.
- Naming:
  - `PascalCase` for contracts, libraries, interfaces.
  - `camelCase` for functions/variables.
  - `UPPER_SNAKE_CASE` for constants.
  - Prefix storage variables consistently (`s_`, `i_`, etc.) when used.
- Error handling:
  - In Aave-style contracts, `require(..., Errors.X)` is standard.
  - In loan-provider contracts, prefer custom errors (`revert Errors.ZeroAddress()`).
  - Validate addresses and amounts early (zero checks, bounds).
- Visibility:
  - Always specify visibility (`public`, `external`, `internal`, `private`).
  - Prefer `external` for entrypoints; `internal` for library logic.

### Tests
- Match existing test patterns and fixtures per workspace.
- Keep test names descriptive and mirror contract method names.
- When adding tests, prefer the smallest test scope possible.

## Config Files
- Prettier config: `.prettierrc`
- EditorConfig defaults: `lending-pool/.editorconfig`
- Hardhat config: `lending-pool/hardhat.config.ts`
- Foundry config: `loan-provider/foundry.toml`

## Directory Layout
- `lending-pool/contracts/`: Aave + Bitmor Solidity contracts
- `lending-pool/helpers/`: Hardhat helpers and utilities
- `lending-pool/tasks/`: Hardhat tasks and scripts
- `lending-pool/test-suites/`: Aave/Bitmor/AMM test suites
- `loan-provider/src/`: Bitmor protocol contracts
- `loan-provider/script/`: Foundry scripts for deploy/interaction
- `loan-provider/test/`: Foundry tests (`*.t.sol`)
- `loan-provider/scripts/`: Deployment helpers and configs

## Repo-Specific Notes
- `lending-pool/` uses Hardhat tasks under `tasks/` and test suites in `test-suites/`.
- `loan-provider/` uses Foundry scripts under `script/` and deployment helpers in `scripts/`.
- Foundry profile config is in `loan-provider/foundry.toml`.

## Safety Notes
- Deployment scripts in `loan-provider/script/` broadcast by default; confirm before running.
- Hardhat network scripts often require funded accounts and correct RPC keys.
- Prefer forked tests before mainnet/sepolia runs.
- Avoid running `make remove` unless explicitly requested.

## Cursor / Copilot Rules
- No `.cursor/rules`, `.cursorrules`, or `.github/copilot-instructions.md` files were found.
