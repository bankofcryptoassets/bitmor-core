-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# ============ Help ============

help:
	@echo ""
	@echo "Bitmor loan-provider"
	@echo "===================="
	@echo ""
	@echo "Testing:"
	@echo "  make test                Run unit tests (default, no RPC needed)"
	@echo "  make test:unit           Run unit tests with mocks"
	@echo "  make test:fork           Run fork tests (requires BASE_SEPOLIA_RPC_URL)"
	@echo "  make test:loan:unit      Run Loan contract unit tests"
	@echo "  make test:vault:unit     Run Vault unit tests"
	@echo "  make test:liquidation:unit  Run liquidation unit tests"
	@echo "  make test:fuzz           Run fuzz tests (placeholder)"
	@echo "  make test:invariant      Run invariant tests (placeholder)"
	@echo "  make test:integration    Run integration tests (placeholder)"
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

# Fork tests (requires BASE_SEPOLIA_RPC_URL)
DEPLOYMENT_BLOCK := $(shell if [ -f "deployments.json" ]; then node -e "try { const d=JSON.parse(require('fs').readFileSync('deployments.json')); const chainData = d.deployments['84532']; console.log(chainData && chainData.blockNumber ? chainData.blockNumber : process.env.BLOCK_NUMBER || 'latest'); } catch(e) { console.log(process.env.BLOCK_NUMBER || 'latest'); }"; else echo $${BLOCK_NUMBER:-latest}; fi)
FORK_NETWORK_ARGS := --fork-url base_sepolia --fork-block-number $(DEPLOYMENT_BLOCK)

test\:fork:
	@echo "Running fork tests (Base Sepolia)..."
	@FOUNDRY_PROFILE=fork forge test --match-path "test/fork/**/*.sol" $(FORK_NETWORK_ARGS) -vvv

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

# ============ Placeholder Tests ============

test\:fuzz:
	@echo "No fuzz tests yet. Add tests to test/fuzz/ to enable."

test\:invariant:
	@echo "No invariant tests yet. Add tests to test/invariant/ to enable."

test\:integration:
	@echo "No integration tests yet. Add tests to test/integration/ to enable."

# ============ Single Test Helpers ============

test\:single:
	@forge test --match-test $(TEST) -vvvv

test\:contract:
	@forge test --match-contract $(CONTRACT) -vvv

# ============ Reports ============

coverage:
	@FOUNDRY_PROFILE=coverage forge coverage --ir-minimum

coverage-lcov:
	@FOUNDRY_PROFILE=coverage forge coverage --report lcov

coverage-html:
	@FOUNDRY_PROFILE=coverage forge coverage --ir-minimum --report lcov && genhtml lcov.info -o coverage-html && open coverage-html/index.html

gas-report:
	@forge test $(FORK_NETWORK_ARGS) --gas-report

# ============ Deployment Commands ============

deployMockTokens:
	@forge script script/deployment/DeployMockTokens.s.sol:DeployMockTokens --rpc-url base_sepolia --broadcast --verify --verifier sourcify --account bitmor_owner

deploySwapAdapterWrapper:
	@forge script script/deployment/DeploySwapAdapterWrapper.s.sol:DeploySwapAdapterWrapper --rpc-url base_sepolia --broadcast --verify --verifier sourcify --account bitmor_owner

mintTokens:
	@forge script script/interaction/MockToken.s.sol:MockToken_MintTokens --rpc-url base_sepolia --broadcast --account bitmor_owner && forge script script/interaction/MockToken.s.sol:MockToken_MintTokens --rpc-url base_sepolia --broadcast --account bitmor_user

depositDebtTokenToBitmorLendingPool:
	@forge script script/interaction/MockToken.s.sol:MockToken_AddToLendingPool --rpc-url base_sepolia --broadcast --account bitmor_owner

deployAccessManager:
	@forge script script/deployment/DeployAccessManager.s.sol:DeployAccessManager --rpc-url base_sepolia --broadcast --verify --verifier sourcify --account bitmor_owner

deployLoanVault:
	@forge script script/deployment/DeployLoanVault.s.sol:DeployLoanVault --rpc-url base_sepolia --broadcast --verify --verifier sourcify --account bitmor_owner

deployLoan:
	@forge script script/deployment/DeployLoan.s.sol:DeployLoan --rpc-url base_sepolia --broadcast --verify --verifier sourcify --account bitmor_owner

deployLoanVaultFactory:
	@forge script script/deployment/DeployLoanVaultFactory.s.sol:DeployLoanVaultFactory --rpc-url base_sepolia --broadcast --verify --verifier sourcify --account bitmor_owner

saveAddresses:
	@forge script script/deployment/SaveDeployedAddresses.s.sol:SaveDeployedAddresses --rpc-url base_sepolia

setLoanVaultFactory:
	@forge script script/interaction/Loan.s.sol:Loan_SetLoanVaultFactory --rpc-url base_sepolia --broadcast --account bitmor_owner

setGracePeriod:
	@forge script script/interaction/Loan.s.sol:Loan_SetGracePeriod --rpc-url base_sepolia --broadcast --account bitmor_owner

setBitmorLoan:
	@forge script script/interaction/AddressesProvider.s.sol:AddressesProvider_SetBitmorLoan --rpc-url base_sepolia --broadcast --account bitmor_owner

verifyAll:
	@echo "Verifying all deployed contracts..."
	@forge script script/verification/VerifyAllContracts.s.sol:VerifyAllContracts --rpc-url base_sepolia --ffi

setup:
	@make deployAccessManager && make deploySwapAdapterWrapper && make mintTokens && make depositDebtTokenToBitmorLendingPool && make deployLoanVault && make deployLoan && make deployLoanVaultFactory && make setLoanVaultFactory && make setBitmorLoan && make saveAddresses && make verifyAll

# ============ Interaction Commands ============

initializeLoan:
	@forge script script/interaction/Loan.s.sol:Loan_InitializeLoan --rpc-url base_sepolia --broadcast --account bitmor_user

initializeLoanOnFork:
	@forge script script/interaction/Interaction.s.sol:LoanInteraction $(FORK_NETWORK_ARGS) --account bitmor_user -vvvvv
