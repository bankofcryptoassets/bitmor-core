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

install :; forge install Cyfrin/foundry-devops && forge install foundry-rs/forge-std && forge install OpenZeppelin/openzeppelin-contracts

# Update Dependencies
update:; forge update

build:; forge build

FORK_NETWORK_ARGS := --fork-url base_sepolia 

test :; forge test $(FORK_NETWORK_ARGS)

snapshot :; forge snapshot

format :; forge fmt

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

deployMockTokens:
	forge script script/deployment/DeployMockTokens.s.sol:DeployMockTokens --rpc-url base_sepolia --broadcast  --verify --verifier sourcify  --account bitmor_owner

mintTokens: 
	forge script script/interaction/MockToken.s.sol:MockToken_MintTokens --rpc-url base_sepolia --broadcast --account bitmor_owner

depositDebtTokenToBitmorLendingPool: 
	forge script script/interaction/MockToken.s.sol:MockToken_AddToLendingPool --rpc-url base_sepolia --broadcast --account bitmor_owner

deployLoanVault:
	forge script script/deployment/DeployLoanVault.s.sol:DeployLoanVault --rpc-url base_sepolia --broadcast --verify --verifier sourcify --account bitmor_owner

deployLoanVaultFactory:
	forge script script/deployment/DeployLoanVaultFactory.s.sol:DeployLoanVaultFactory --rpc-url base_sepolia --broadcast --verify --verifier sourcify --account bitmor_owner

deployLoan:
	forge script script/deployment/DeployLoan.s.sol:DeployLoan --rpc-url base_sepolia --broadcast --verify --verifier sourcify --account bitmor_owner

setLoanVaultFactory: 
	forge script script/interaction/Loan.s.sol:Loan_SetLoanVaultFactory --rpc-url base_sepolia --broadcast --account bitmor_owner

setBitmorLoan: 
	forge script script/interaction/AddressesProvider.s.sol:AddressesProvider_SetBitmorLoan --rpc-url base_sepolia --broadcast --account bitmor_owner

setup:
	make deployMockTokens && make mintTokens && make depositDebtTokenToBitmorLendingPool && make deployLoanVault && make deployLoanVaultFactory && make deployLoan && make setLoanVaultFactory && make setBitmorLoan

initializeLoan: 
	forge script script/interaction/Loan.s.sol:Loan_InitializeLoan --rpc-url base_sepolia --broadcast --account bitmor_user

initializeLoanOnFork: 
	forge script script/interaction/Interaction.s.sol:LoanInteraction $(FORK_NETWORK_ARGS) --account bitmor_user -vvvvv