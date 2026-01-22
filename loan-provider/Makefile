-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

help:
	@echo "Usage:"
	@echo "  make deploy [ARGS=...]\n    example: make deploy ARGS=\"--network sepolia\""
	@echo ""
	@echo "  make fund [ARGS=...]\n    example: make deploy ARGS=\"--network sepolia\""

all: clean remove install update build

# Clean the repo
clean  :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; forge install Cyfrin/foundry-devops && forge install foundry-rs/forge-std && forge install OpenZeppelin/openzeppelin-contracts && forge install vectorized/solady

# Update Dependencies
update:; forge update

build:; forge build

# Read block from deployment file, fallback to .env
DEPLOYMENT_BLOCK := $(shell if [ -f "deployments.json" ]; then node -e "try { const d=JSON.parse(require('fs').readFileSync('deployments.json')); const chainData = d.deployments['84532']; console.log(chainData && chainData.blockNumber ? chainData.blockNumber : process.env.BLOCK_NUMBER || 'latest'); } catch(e) { console.log(process.env.BLOCK_NUMBER || 'latest'); }"; else echo $${BLOCK_NUMBER:-latest}; fi)

FORK_NETWORK_ARGS := --fork-url base_sepolia --fork-block-number $(DEPLOYMENT_BLOCK) --etherscan-api-key etherscan_api_key

# Local args (for unit tests - Anvil)
LOCAL_NETWORK_ARGS := --rpc-url http://127.0.0.1:8545

# Fork args for Base Mainnet (for integration tests)
MAINNET_FORK_ARGS := --fork-url base_mainnet

test :; forge test $(FORK_NETWORK_ARGS)

# Unit tests (local Anvil + MockAaveV3Pool)
# Requires: make anvil (in separate terminal)
test-unit:
	forge test $(LOCAL_NETWORK_ARGS)

# Integration tests (Base Mainnet fork + real Aave V3)
test-integration:
	forge test $(MAINNET_FORK_ARGS)

# Run both (unit first, then integration)
test-all: test-unit test-integration

snapshot :; forge snapshot

format :; forge fmt

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

gasReport:
	forge test $(FORK_NETWORK_ARGS) --gas-report

coverage:
	forge coverage $(FORK_NETWORK_ARGS)

coverageLCOV:
	forge coverage $(FORK_NETWORK_ARGS) --report lcov

# =============== SETUP Commands ================

# !DO NOT DEPLOY MOCK TOKENS while setup. Mocks tokens are deployed in the Lending Pool.
deployMockTokens:
	forge script script/deployment/DeployMockTokens.s.sol:DeployMockTokens --rpc-url base_sepolia --broadcast  --verify --verifier sourcify  --account bitmor_owner

deploySwapAdapterWrapper:
	forge script script/deployment/DeploySwapAdapterWrapper.s.sol:DeploySwapAdapterWrapper --rpc-url base_sepolia --broadcast --verify --verifier sourcify --account bitmor_owner

mintTokens:
	forge script script/interaction/MockToken.s.sol:MockToken_MintTokens --rpc-url base_sepolia --broadcast --account bitmor_owner && forge script script/interaction/MockToken.s.sol:MockToken_MintTokens --rpc-url base_sepolia --broadcast --account bitmor_user

depositDebtTokenToBitmorLendingPool:
	forge script script/interaction/MockToken.s.sol:MockToken_AddToLendingPool --rpc-url base_sepolia --broadcast --account bitmor_owner

deployAccessManager:
	forge script script/deployment/DeployAccessManager.s.sol:DeployAccessManager --rpc-url base_sepolia --broadcast --verify --verifier sourcify --account bitmor_owner

deployLoanVault:
	forge script script/deployment/DeployLoanVault.s.sol:DeployLoanVault --rpc-url base_sepolia --broadcast --verify --verifier sourcify --account bitmor_owner

deployLoan:
	forge script script/deployment/DeployLoan.s.sol:DeployLoan --rpc-url base_sepolia --broadcast --verify --verifier sourcify --account bitmor_owner

deployLoanVaultFactory:
	forge script script/deployment/DeployLoanVaultFactory.s.sol:DeployLoanVaultFactory --rpc-url base_sepolia --broadcast --verify --verifier sourcify --account bitmor_owner

saveAddresses:
	forge script script/deployment/SaveDeployedAddresses.s.sol:SaveDeployedAddresses --rpc-url base_sepolia

setLoanVaultFactory:
	forge script script/interaction/Loan.s.sol:Loan_SetLoanVaultFactory --rpc-url base_sepolia --broadcast --account bitmor_owner

setGracePeriod:
	forge script script/interaction/Loan.s.sol:Loan_SetGracePeriod --rpc-url base_sepolia --broadcast --account bitmor_owner

setBitmorLoan:
	forge script script/interaction/AddressesProvider.s.sol:AddressesProvider_SetBitmorLoan --rpc-url base_sepolia --broadcast --account bitmor_owner

verifyAll:
	@echo "🔍 Verifying all deployed contracts..."
	forge script script/verification/VerifyAllContracts.s.sol:VerifyAllContracts --rpc-url base_sepolia --ffi

setup:
	make deployAccessManager && make deploySwapAdapterWrapper && make mintTokens && make depositDebtTokenToBitmorLendingPool && make deployLoanVault && make deployLoan && make deployLoanVaultFactory && make setLoanVaultFactory && make setBitmorLoan && make saveAddresses && make verifyAll

# ==============================================================

# =============================== Test Commands ===============================

testLoanInitialization:
	forge test --mt test_initializeLoan $(FORK_NETWORK_ARGS) -vvvv

testRepay:
	forge test --mt test_repay $(FORK_NETWORK_ARGS) -vvvv

testCloseLoan:
	forge test --mt test_closeLoan $(FORK_NETWORK_ARGS) -vvvv

testCreateAutoRepayment:
	forge test --mt test_createAutoRepayment $(FORK_NETWORK_ARGS) -vvvv

testExecuteRepayment:
	forge test --mt test_executeAutoRepayment $(FORK_NETWORK_ARGS) -vvvv

# ==============================================================

initializeLoan:
	forge script script/interaction/Loan.s.sol:Loan_InitializeLoan --rpc-url base_sepolia --broadcast --account bitmor_user

initializeLoanOnFork:
	forge script script/interaction/Interaction.s.sol:LoanInteraction $(FORK_NETWORK_ARGS) --account bitmor_user -vvvvv

# ============ Unit Test Variants ============

testLoanInitialization-unit:
	forge test --mt test_initializeLoan $(LOCAL_NETWORK_ARGS) -vvvv

testRepay-unit:
	forge test --mt test_repay $(LOCAL_NETWORK_ARGS) -vvvv

testCloseLoan-unit:
	forge test --mt test_closeLoan $(LOCAL_NETWORK_ARGS) -vvvv
