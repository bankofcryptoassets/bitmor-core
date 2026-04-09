-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil coverage coverage-lcov coverage-html \
	deploy\:phase1\:local deploy\:libraries\:local deploy\:phase3\:local deploy\:check\:local \
	deploy\:phase1\:fork deploy\:libraries\:fork deploy\:phase3\:fork deploy\:check\:fork \
	deploy\:phase1\:testnet deploy\:libraries\:testnet deploy\:phase3\:testnet deploy\:check\:testnet \
	deploy\:oracle-wrappers\:testnet \
	deploy\:check

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Overridable signer keys (default to Anvil account 0)
LOCAL_PRIVATE_KEY ?= $(DEFAULT_ANVIL_KEY)
FORK_PRIVATE_KEY ?= $(PK_FORK)

# ============ Help ============

help:
	@echo ""
	@echo "Bitmor loan-provider"
	@echo "===================="
	@echo ""
	@echo "Testing:"
	@echo "  make test                Run unit tests (default, no RPC needed)"
	@echo "  make test:unit           Run unit tests with mocks"
	@echo "  make test:fork           Run fork tests (requires make anvil-fork + make deploy-fork)"
	@echo "  make test:loan:unit      Run Loan contract unit tests"
	@echo "  make test:vault:unit     Run Vault unit tests"
	@echo "  make test:strategy:unit  Run Strategy unit tests"
	@echo "  make test:liquidation:unit  Run liquidation unit tests"
	@echo "  make test:fuzz           Run fuzz tests (FOUNDRY_PROFILE=fuzz, 10k runs)"
	@echo "  make test:invariant      Run invariant tests (FOUNDRY_PROFILE=invariant, 10k runs, depth 50)"
	@echo "  make test:integration              Run all integration tests"
	@echo "  make test:integration:setup        SetUpState tests"
	@echo "  make test:integration:access       AccessControl tests"
	@echo "  make test:integration:liquidation  Liquidation tests"
	@echo "  make test:integration:lifecycle    LoanLifecycle tests"
	@echo "  make test:integration:vault        VaultStrategy tests"
	@echo "  make test:integration:initloan           All InitLoan adversarial tests"
	@echo "  make test:integration:initloan:usdcvault InitLoan USDCVault tests"
	@echo "  make test:integration:initloan:btcvault  InitLoan BTCVault tests"
	@echo "  make test:integration:initloan:oracle    InitLoan Oracle tests"
	@echo "  make test:integration:initloan:swap      InitLoan Swap tests"
	@echo "  make test:integration:initloan:accounting InitLoan Accounting tests"
	@echo "  make test:integration:initloan:irm       InitLoan IRM tests"
	@echo "  make test:integration:initloan:erc4626   InitLoan ERC4626 tests"
	@echo "  make test:integration:initloan:strategy  InitLoan Strategy tests"
	@echo "  make test:integration:initloan:timing    InitLoan Timing tests"
	@echo "  make test:integration:single TEST=name  Single integration test"
	@echo "  make test:integration:contract CONTRACT=Name  Integration tests by contract"
	@echo "  make test:fork:single TEST=name     Single fork test"
	@echo "  make test:fork:contract CONTRACT=Name  Fork tests by contract"
	@echo ""
	@echo "Single Test:"
	@echo "  make test:single TEST=test_name    Run single test by name"
	@echo "  make test:contract CONTRACT=Name   Run tests for contract"
	@echo ""
	@echo "Reports:"
	@echo "  make coverage            Generate coverage report"
	@echo "  make gas-report          Generate gas report"
	@echo ""
	@echo "Build:"
	@echo "  make build               Build contracts"
	@echo "  make clean               Clean build artifacts"
	@echo "  make format              Format code"
	@echo ""
	@echo "Interactions:"
	@echo "  make interact:local:initloan      Initialize loan (local Anvil)"
	@echo "  make interact:fork:initloan       Initialize loan (fork Anvil)"
	@echo "  make interact:live:initloan       Initialize loan (live, default base_mainnet)"
	@echo "  make interact:live:initloan NETWORK=base_sepolia  (live, Base Sepolia)"
	@echo "  make interact:local:fund:usdc     Fund user with USDC (local)"
	@echo "  make interact:fork:fund:usdc      Fund user with USDC (fork)"
	@echo "  make interact:local:seed          Seed lending pool (local)"
	@echo "  make interact:fork:seed           Seed lending pool (fork)"
	@echo ""

# ============ Build ============

all: clean remove install update build

clean:
	@forge clean

remove:
	@rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install:
	@forge install Cyfrin/foundry-devops && forge install foundry-rs/forge-std && forge install OpenZeppelin/openzeppelin-contracts && forge install vectorized/solady

update:
	@forge update

build:
	@forge build

format:
	@forge fmt

snapshot:
	@forge snapshot

anvil:
	@anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

# ============ Test Commands ============

# Default: run unit tests (no RPC needed)
test:
	@$(MAKE) test:unit

# Unit tests with mocks
test\:unit:
	@echo "Running unit tests..."
	@FOUNDRY_PROFILE=unit forge test --match-path "test/unit/**/*.sol" -vvv

# Fork tests (requires make anvil-fork + make deploy-fork)
test\:fork:
	@echo "Running fork tests (Base mainnet fork on Anvil)..."
	@FORK=base FOUNDRY_PROFILE=fork forge test --fork-url http://127.0.0.1:8545 -vvv

test\:fork\:single:
	@echo "Running single fork test: $(TEST)..."
	@FORK=base FOUNDRY_PROFILE=fork forge test --fork-url http://127.0.0.1:8545 --match-test $(TEST) -vvvv

test\:fork\:contract:
	@echo "Running fork tests for contract: $(CONTRACT)..."
	@FORK=base FOUNDRY_PROFILE=fork forge test --fork-url http://127.0.0.1:8545 --match-contract $(CONTRACT) -vvvv

# ============ Domain-Specific Unit Tests ============

test\:loan\:unit:
	@echo "Running Loan unit tests..."
	@FOUNDRY_PROFILE=unit forge test --match-path "test/unit/Loan/**/*.sol" -vvv

test\:vault\:unit:
	@echo "Running Vault unit tests..."
	@FOUNDRY_PROFILE=unit forge test --match-path "test/unit/Vault/**/*.sol" -vvv

test\:liquidation\:unit:
	@echo "Running liquidation unit tests..."
	@FOUNDRY_PROFILE=unit forge test --match-path "test/unit/*Liquidation*.sol" -vvv

test\:strategy\:unit:
	@echo "Running Strategy unit tests..."
	@FOUNDRY_PROFILE=unit forge test --match-path "test/unit/Strategy/**/*.sol" -vvv

test\:fuzz:
	@echo "Running Fuzz tests..."
	@FOUNDRY_PROFILE=fuzz forge test --match-path "test/fuzz/**/*.sol" -vvv

test\:fuzz\:usdcVault:
	@echo "Running Fuzz USDC Vault tests..."
	@FOUNDRY_PROFILE=fuzz forge test --match-path "test/fuzz/**/USDCVault.fuzz.t.sol" -vvv


test\:invariant:
	@echo "Running invariant tests..."
	@FOUNDRY_PROFILE=invariant forge test --match-path "test/invariant/**/*.sol" -vvv

test\:integration:
	@echo "Running integration tests (requires running Anvil + make deploy-local)..."
	@FOUNDRY_PROFILE=integration forge test --fork-url http://127.0.0.1:8545 -vvv

test\:integration\:setup:
	@echo "Running SetUpState integration tests..."
	@FOUNDRY_PROFILE=integration forge test --match-path "test/integration/SetUpState.t.sol" --fork-url http://127.0.0.1:8545 -vvv

test\:integration\:access:
	@echo "Running AccessControl integration tests..."
	@FOUNDRY_PROFILE=integration forge test --match-path "test/integration/AccessControl.t.sol" --fork-url http://127.0.0.1:8545 -vvv

test\:integration\:liquidation:
	@echo "Running Liquidation integration tests..."
	@FOUNDRY_PROFILE=integration forge test --match-path "test/integration/Liquidation.t.sol" --fork-url http://127.0.0.1:8545 -vvv

test\:integration\:lifecycle:
	@echo "Running LoanLifecycle integration tests..."
	@FOUNDRY_PROFILE=integration forge test --match-path "test/integration/LoanLifecycle.t.sol" --fork-url http://127.0.0.1:8545 -vvv

test\:integration\:vault:
	@echo "Running VaultStrategy integration tests..."
	@FOUNDRY_PROFILE=integration forge test --match-path "test/integration/VaultStrategy.t.sol" --fork-url http://127.0.0.1:8545 -vvv

test\:integration\:initloan:
	@echo "Running all InitLoan adversarial integration tests..."
	@FOUNDRY_PROFILE=integration forge test --match-path "test/integration/InitLoan_*.t.sol" --fork-url http://127.0.0.1:8545 -vvv

test\:integration\:initloan\:usdcvault:
	@echo "Running InitLoan USDCVault integration tests..."
	@FOUNDRY_PROFILE=integration forge test --match-path "test/integration/InitLoan_USDCVault.t.sol" --fork-url http://127.0.0.1:8545 -vvv

test\:integration\:initloan\:btcvault:
	@echo "Running InitLoan BTCVault integration tests..."
	@FOUNDRY_PROFILE=integration forge test --match-path "test/integration/InitLoan_BTCVault.t.sol" --fork-url http://127.0.0.1:8545 -vvv

test\:integration\:initloan\:oracle:
	@echo "Running InitLoan Oracle integration tests..."
	@FOUNDRY_PROFILE=integration forge test --match-path "test/integration/InitLoan_Oracle.t.sol" --fork-url http://127.0.0.1:8545 -vvv

test\:integration\:initloan\:swap:
	@echo "Running InitLoan Swap integration tests..."
	@FOUNDRY_PROFILE=integration forge test --match-path "test/integration/InitLoan_Swap.t.sol" --fork-url http://127.0.0.1:8545 -vvv

test\:integration\:initloan\:accounting:
	@echo "Running InitLoan Accounting integration tests..."
	@FOUNDRY_PROFILE=integration forge test --match-path "test/integration/InitLoan_Accounting.t.sol" --fork-url http://127.0.0.1:8545 -vvv

test\:integration\:initloan\:irm:
	@echo "Running InitLoan IRM integration tests..."
	@FOUNDRY_PROFILE=integration forge test --match-path "test/integration/InitLoan_IRM.t.sol" --fork-url http://127.0.0.1:8545 -vvv

test\:integration\:initloan\:erc4626:
	@echo "Running InitLoan ERC4626 integration tests..."
	@FOUNDRY_PROFILE=integration forge test --match-path "test/integration/InitLoan_ERC4626.t.sol" --fork-url http://127.0.0.1:8545 -vvv

test\:integration\:initloan\:strategy:
	@echo "Running InitLoan Strategy integration tests..."
	@FOUNDRY_PROFILE=integration forge test --match-path "test/integration/InitLoan_Strategy.t.sol" --fork-url http://127.0.0.1:8545 -vvv

test\:integration\:initloan\:timing:
	@echo "Running InitLoan Timing integration tests..."
	@FOUNDRY_PROFILE=integration forge test --match-path "test/integration/InitLoan_Timing.t.sol" --fork-url http://127.0.0.1:8545 -vvv

test\:integration\:single:
	@FOUNDRY_PROFILE=integration forge test --match-test $(TEST) --fork-url http://127.0.0.1:8545 -vvvv

test\:integration\:contract:
	@FOUNDRY_PROFILE=integration forge test --match-contract $(CONTRACT) --fork-url http://127.0.0.1:8545 -vvv

# ============ Single Test Helpers ============

test\:single:
	@forge test --match-test $(TEST) -vvvv

test\:contract:
	@forge test --match-contract $(CONTRACT) -vvv

# ============ Reports ============

coverage:
	@FOUNDRY_PROFILE=coverage forge coverage --ir-minimum

coverage-lcov:
	@FOUNDRY_PROFILE=coverage forge coverage --ir-minimum --report lcov

coverage-html:
	@FOUNDRY_PROFILE=coverage forge coverage --ir-minimum --report lcov && genhtml lcov.info -o coverage-html && open coverage-html/index.html

gas-report:
	@forge test $(FORK_NETWORK_ARGS) --gas-report

# ============ Proxy Deployment Commands (New) ============

deploy\:phase1\:local:
	@echo "Deploying Phase 1 (local, proxy-based)..."
	@FOUNDRY_PROFILE=local forge script script/deployment/local/DeployPhase1Local.s.sol:DeployPhase1Local --rpc-url http://127.0.0.1:8545 --private-key $(LOCAL_PRIVATE_KEY) --broadcast --force -v

# Library deployment (all envs)
deploy\:libraries\:local:
	@echo "Deploying linked libraries (local)..."
	@FOUNDRY_PROFILE=local forge script script/deployment/DeployLibraries.s.sol:DeployLibraries \
		--rpc-url http://127.0.0.1:8545 --private-key $(LOCAL_PRIVATE_KEY) --broadcast --force -v

deploy\:libraries\:fork:
	@echo "Deploying linked libraries (fork)..."
	@FORK=base FOUNDRY_PROFILE=fork-deploy forge script script/deployment/DeployLibraries.s.sol:DeployLibraries \
		--rpc-url $(RPC_FORK) --private-key $(FORK_PRIVATE_KEY) --broadcast --force -v

deploy\:libraries\:testnet:
	@echo "Deploying linked libraries (testnet)..."
	@FOUNDRY_PROFILE=testnet forge script script/deployment/DeployLibraries.s.sol:DeployLibraries \
		--rpc-url $(RPC_URL) --account $(ACCOUNT) --sender $(SENDER) --broadcast --slow --force -v

deploy\:phase3\:local:
	@echo "Deploying Phase 3 (local, proxy-based)..."
	@FOUNDRY_PROFILE=local forge script script/deployment/local/DeployPhase3Local.s.sol:DeployPhase3Local \
		--rpc-url http://127.0.0.1:8545 --private-key $(LOCAL_PRIVATE_KEY) --broadcast --slow --force -v \
		$(LIBRARY_FLAG)

# Fork deployment (Base mainnet fork on Anvil)
RPC_FORK := http://127.0.0.1:8545
PK_FORK := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
# Anvil account 0 address (derived from DEFAULT_ANVIL_KEY)
ANVIL_SENDER := 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
# Whale addresses for fork impersonation
USDC_WHALE := 0x20FE51A9229EEf2cF8Ad9E89d91CAb9312cF3b7A
CBBTC_WHALE := 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb

deploy\:phase1\:fork:
	FORK=base FOUNDRY_PROFILE=fork-deploy forge script script/deployment/fork/DeployPhase1Fork.s.sol:DeployPhase1Fork \
		--rpc-url $(RPC_FORK) --private-key $(FORK_PRIVATE_KEY) --broadcast --force -v

deploy\:phase3\:fork:
	FORK=base FOUNDRY_PROFILE=fork-deploy forge script script/deployment/fork/DeployPhase3Fork.s.sol:DeployPhase3Fork \
		--rpc-url $(RPC_FORK) --private-key $(FORK_PRIVATE_KEY) --broadcast --slow --force -v \
		$(LIBRARY_FLAG)

# Testnet deployment (RPC_URL is REQUIRED, passed by caller)
ACCOUNT ?= bitmor_owner
SENDER ?= $(shell cast wallet address --account $(ACCOUNT) 2>/dev/null)

deploy\:phase1\:testnet:
	@echo "Deploying Phase 1 (testnet)..."
	@FOUNDRY_PROFILE=testnet forge script script/deployment/testnet/DeployPhase1Testnet.s.sol:DeployPhase1Testnet \
		--rpc-url $(RPC_URL) --account $(ACCOUNT) --sender $(SENDER) --broadcast --slow --force -v

deploy\:phase3\:testnet:
	@echo "Deploying Phase 3 (testnet)..."
	@FOUNDRY_PROFILE=testnet forge script script/deployment/testnet/DeployPhase3Testnet.s.sol:DeployPhase3Testnet \
		--rpc-url $(RPC_URL) --account $(ACCOUNT) --sender $(SENDER) --broadcast --slow --force -v \
		$(LIBRARY_FLAG)

deploy\:check\:local:
	@echo "Running post-deploy checks (local)..."
	@FOUNDRY_PROFILE=local forge script script/deployment/PostDeployChecks.s.sol:PostDeployChecks \
		--rpc-url http://127.0.0.1:8545 --private-key $(LOCAL_PRIVATE_KEY) -v \
		$(LIBRARY_FLAG)

deploy\:check\:fork:
	@echo "Running post-deploy checks (fork)..."
	@FORK=base FOUNDRY_PROFILE=fork-deploy forge script script/deployment/PostDeployChecks.s.sol:PostDeployChecks \
		--rpc-url $(RPC_FORK) --private-key $(FORK_PRIVATE_KEY) -v \
		$(LIBRARY_FLAG)

deploy\:oracle-wrappers\:testnet:
	@echo "Deploying Chainlink oracle wrappers (testnet)..."
	@FOUNDRY_PROFILE=testnet forge script script/deployment/testnet/DeployOracleWrappers.s.sol:DeployOracleWrappers \
		--rpc-url $(NETWORK) --account $(ACCOUNT) --broadcast --slow -v

deploy\:check\:testnet:
	@echo "Running post-deploy checks (testnet)..."
	@FOUNDRY_PROFILE=testnet forge script script/deployment/PostDeployChecks.s.sol:PostDeployChecks \
		--rpc-url $(RPC_URL) --account $(ACCOUNT) --sender $(SENDER) -v \
		$(LIBRARY_FLAG)

# Backward compat alias
deploy\:check: deploy\:check\:local

deploy\:phase1\:mainnet:
	@echo "Deploying Phase 1 (Base mainnet)..."
	@forge script script/deployment/mainnet/DeployPhase1Mainnet.s.sol:DeployPhase1Mainnet --rpc-url base_mainnet --broadcast --verify --account bitmor_owner --force -v

deploy\:phase3\:mainnet:
	@echo "Deploying Phase 3 (Base mainnet)..."
	@forge script script/deployment/mainnet/DeployPhase3Mainnet.s.sol:DeployPhase3Mainnet --rpc-url base_mainnet --broadcast --verify --slow --account bitmor_owner --force -v

deploy\:transfer\:mainnet:
	@echo "Transferring ADMIN to multisig (Base mainnet)..."
	@forge script script/deployment/mainnet/TransferToMultisig.s.sol:TransferToMultisig --rpc-url base_mainnet --broadcast --account bitmor_owner -v

# ============ Upgrade Commands ============

upgrade\:uups\:schedule:
	@echo "Scheduling UUPS upgrade..."
	@forge script script/upgrade/UpgradeUUPS.s.sol:UpgradeUUPS --sig "schedule(address,string,bytes)" $(PROXY) $(CONTRACT) $(INIT_DATA) --rpc-url $(RPC_URL) --broadcast --account bitmor_owner --force -v

upgrade\:uups\:execute:
	@echo "Executing UUPS upgrade..."
	@forge script script/upgrade/UpgradeUUPS.s.sol:UpgradeUUPS --sig "execute(address,address,bytes)" $(PROXY) $(NEW_IMPL) $(INIT_DATA) --rpc-url $(RPC_URL) --broadcast --account bitmor_owner --force -v

upgrade\:beacon\:schedule:
	@echo "Scheduling beacon upgrade..."
	@forge script script/upgrade/UpgradeBeacon.s.sol:UpgradeBeacon --sig "schedule(address)" $(NEW_IMPL) --rpc-url $(RPC_URL) --broadcast --account bitmor_owner --force -v

upgrade\:beacon\:execute:
	@echo "Executing beacon upgrade..."
	@forge script script/upgrade/UpgradeBeacon.s.sol:UpgradeBeacon --sig "execute(address)" $(NEW_IMPL) --rpc-url $(RPC_URL) --broadcast --account bitmor_owner --force -v

# ============ Legacy Deployment Commands ============

deployMockTokens:
	@forge script script/deployment/DeployMockTokens.s.sol:DeployMockTokens --rpc-url base_sepolia --broadcast --verify --verifier sourcify --account bitmor_owner

deploySwapAdapterWrapper:
	@forge script script/deployment/DeploySwapAdapterWrapper.s.sol:DeploySwapAdapterWrapper --rpc-url base_sepolia --broadcast --verify --verifier sourcify --account bitmor_owner

deployAccessManager:
	@forge script script/deployment/DeployAccessManager.s.sol:DeployAccessManager --rpc-url base_sepolia --broadcast --verify --verifier sourcify --account bitmor_owner

deployLoanVault:
	@forge script script/deployment/DeployLoanVault.s.sol:DeployLoanVault --rpc-url base_sepolia --broadcast --verify --verifier sourcify --account bitmor_owner

deployLoan:
	@forge script script/deployment/DeployLoan.s.sol:DeployLoan --rpc-url base_sepolia --broadcast --verify --verifier sourcify --account bitmor_owner

deployLoanVaultFactory:
	@forge script script/deployment/DeployLoanVaultFactory.s.sol:DeployLoanVaultFactory --rpc-url base_sepolia --broadcast --verify --verifier sourcify --account bitmor_owner

verifyAll:
	@echo "Verifying all deployed contracts..."
	@forge script script/verification/VerifyAllContracts.s.sol:VerifyAllContracts --rpc-url base_sepolia --ffi

# ============ Interaction Commands ============
# Usage: make interact:<env>:<action>
# Environments: local (Anvil), fork (Base mainnet fork on Anvil), live (any network)
# For live targets, pass NETWORK= to select RPC endpoint (must match foundry.toml [rpc_endpoints])
# Examples:
#   make interact:live:initloan                          # defaults to base_mainnet
#   make interact:live:initloan NETWORK=base_sepolia     # Base Sepolia
NETWORK ?= base_mainnet

# --- Initialize Loan ---
interact\:local\:initloan:
	@echo "Initializing loan (local)..."
	@FOUNDRY_PROFILE=local forge script script/interaction/Loan.s.sol:Loan_InitializeLoan \
		--rpc-url http://127.0.0.1:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast -v

interact\:fork\:initloan:
	@echo "Initializing loan (fork)..."
	@cast rpc anvil_impersonateAccount $(USDC_WHALE) --rpc-url $(RPC_FORK) > /dev/null
	@FORK=base FOUNDRY_PROFILE=fork-deploy forge script script/interaction/Loan.s.sol:Loan_InitializeLoan \
		--rpc-url $(RPC_FORK) --sender $(ANVIL_SENDER) --unlocked --broadcast -v

interact\:live\:initloan:
	@echo "Initializing loan (live $(NETWORK))..."
	@forge script script/interaction/Loan.s.sol:Loan_InitializeLoan \
		--rpc-url $(NETWORK) --account bitmor_user --sender $(shell cast wallet address --account bitmor_user 2>/dev/null) --broadcast -v

# --- Fund User ---
interact\:local\:fund\:usdc:
	@FOUNDRY_PROFILE=local forge script script/interaction/FundUser.s.sol:FundUser_USDC \
		--rpc-url http://127.0.0.1:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast -v

interact\:fork\:fund\:usdc:
	@cast rpc anvil_impersonateAccount $(USDC_WHALE) --rpc-url $(RPC_FORK) > /dev/null
	@FORK=base FOUNDRY_PROFILE=fork-deploy forge script script/interaction/FundUser.s.sol:FundUser_USDC \
		--rpc-url $(RPC_FORK) --sender $(ANVIL_SENDER) --unlocked --broadcast -v

interact\:local\:fund\:cbbtc:
	@FOUNDRY_PROFILE=local forge script script/interaction/FundUser.s.sol:FundUser_CbBTC \
		--rpc-url http://127.0.0.1:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast -v

interact\:fork\:fund\:cbbtc:
	@cast rpc anvil_impersonateAccount $(CBBTC_WHALE) --rpc-url $(RPC_FORK) > /dev/null
	@FORK=base FOUNDRY_PROFILE=fork-deploy forge script script/interaction/FundUser.s.sol:FundUser_CbBTC \
		--rpc-url $(RPC_FORK) --sender $(ANVIL_SENDER) --unlocked --broadcast -v

# --- Seed Lending Pool ---
interact\:local\:seed:
	@FOUNDRY_PROFILE=local forge script script/interaction/FundUser.s.sol:SeedLendingPool \
		--rpc-url http://127.0.0.1:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast -v

interact\:fork\:seed:
	@cast rpc anvil_impersonateAccount $(USDC_WHALE) --rpc-url $(RPC_FORK) > /dev/null
	@FORK=base FOUNDRY_PROFILE=fork-deploy forge script script/interaction/FundUser.s.sol:SeedLendingPool \
		--rpc-url $(RPC_FORK) --sender $(ANVIL_SENDER) --unlocked --broadcast -v

# --- Admin Setters ---
interact\:local\:set\:vaultfactory:
	@FOUNDRY_PROFILE=local forge script script/interaction/Loan.s.sol:Loan_SetLoanVaultFactory \
		--rpc-url http://127.0.0.1:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast -v

interact\:local\:set\:graceperiod:
	@FOUNDRY_PROFILE=local forge script script/interaction/Loan.s.sol:Loan_SetGracePeriod \
		--rpc-url http://127.0.0.1:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast -v

interact\:local\:set\:bitmor-loan:
	@FOUNDRY_PROFILE=local forge script script/interaction/AddressesProvider.s.sol:AddressesProvider_SetBitmorLoan \
		--rpc-url http://127.0.0.1:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast -v

interact\:live\:set\:vaultfactory:
	@forge script script/interaction/Loan.s.sol:Loan_SetLoanVaultFactory \
		--rpc-url $(NETWORK) --account bitmor_owner --sender $(SENDER) --broadcast -v

interact\:live\:set\:graceperiod:
	@forge script script/interaction/Loan.s.sol:Loan_SetGracePeriod \
		--rpc-url $(NETWORK) --account bitmor_owner --sender $(SENDER) --broadcast -v

interact\:live\:set\:bitmor-loan:
	@forge script script/interaction/AddressesProvider.s.sol:AddressesProvider_SetBitmorLoan \
		--rpc-url $(NETWORK) --account bitmor_owner --sender $(SENDER) --broadcast -v
