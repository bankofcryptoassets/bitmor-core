# Bitmor Protocol - Root Makefile

.PHONY: help install build clean anvil anvil-stop deploy-local test test-unit test-lending-pool

# Chain configuration
LOCAL_CHAIN_ID := 31337
ANVIL_PORT := 8545

# Default target
help:
	@echo ""
	@echo "Bitmor Protocol"
	@echo "==============="
	@echo ""
	@echo "Setup:"
	@echo "  make install       Install all dependencies"
	@echo "  make build         Build all contracts"
	@echo "  make clean         Clean build artifacts"
	@echo ""
	@echo "Local Development:"
	@echo "  make anvil         Start Anvil (localhost:$(ANVIL_PORT), chainId $(LOCAL_CHAIN_ID))"
	@echo "  make anvil-stop    Stop Anvil"
	@echo "  make deploy-local  Deploy full protocol to Anvil"
	@echo ""
	@echo "Testing:"
	@echo "  make test          Run all tests"
	@echo "  make test-unit     Run loan-provider unit tests"
	@echo "  make test-lending-pool  Run lending-pool tests"
	@echo ""
	@echo "Prerequisites for deploy-local:"
	@echo "  cast wallet import dev --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
	@echo ""

# Setup
install:
	@echo "Installing dependencies..."
	cd lending-pool && npm install
	cd loan-provider && forge install
	@echo "Done."

build:
	@echo "Building contracts..."
	cd lending-pool && npm run compile
	cd loan-provider && forge build
	@echo "Done."

clean:
	@echo "Cleaning..."
	rm -rf deploy/artifacts/*.log
	cd lending-pool && rm -rf artifacts cache
	cd loan-provider && forge clean
	@echo "Done."

# Anvil
anvil:
	anvil --port $(ANVIL_PORT) --chain-id $(LOCAL_CHAIN_ID) --accounts 10 --balance 10000

anvil-stop:
	@pkill -f "anvil" 2>/dev/null || echo "Anvil not running"

# Deployment
deploy-local:
	@./deploy/scripts/deploy-local.sh

# Testing
test: test-unit test-lending-pool

test-unit:
	@echo "Running loan-provider tests..."
	cd loan-provider && make test

test-lending-pool:
	@echo "Running lending-pool tests..."
	cd lending-pool && npm run test-bitmor
