# Bitmor Protocol - Root Makefile

.PHONY: help install build clean anvil anvil-stop deploy-local test

# Chain configuration
LOCAL_CHAIN_ID := 31337
ANVIL_PORT := 8545

# ============ Help ============

help:
	@echo ""
	@echo "Bitmor Protocol"
	@echo "==============="
	@echo ""
	@echo "Setup:"
	@echo "  make install             Install all dependencies"
	@echo "  make build               Build all contracts"
	@echo "  make clean               Clean build artifacts"
	@echo ""
	@echo "Local Development:"
	@echo "  make anvil               Start Anvil (localhost:$(ANVIL_PORT), chainId $(LOCAL_CHAIN_ID))"
	@echo "  make anvil-stop          Stop Anvil"
	@echo "  make deploy-local        Deploy full protocol to Anvil"
	@echo ""
	@echo "Testing (loan-provider):"
	@echo "  make test                Run unit tests (default, no RPC needed)"
	@echo "  make test:unit           Run unit tests with mocks"
	@echo "  make test:fork           Run fork tests (requires BASE_SEPOLIA_RPC_URL)"
	@echo "  make test:loan:unit      Run Loan contract unit tests"
	@echo "  make test:vault:unit     Run Vault unit tests"
	@echo "  make test:liquidation:unit  Run liquidation unit tests"
	@echo ""
	@echo "Testing (lending-pool):"
	@echo "  make test:lp             Run lending-pool Bitmor tests"
	@echo "  make test:lp:aave        Run lending-pool core Aave tests"
	@echo "  make test:lp:scenarios   Run lending-pool scenario tests"
	@echo ""
	@echo "Testing (combined):"
	@echo "  make test:all            Run all tests (unit + lending-pool)"
	@echo ""
	@echo "See TEST.md for complete testing documentation."
	@echo ""

# ============ Setup ============

install:
	@echo "Installing dependencies..."
	@cd lending-pool && npm install
	@cd loan-provider && forge install
	@echo "Done."

build:
	@echo "Building contracts..."
	@cd lending-pool && npm run compile
	@cd loan-provider && forge build
	@echo "Done."

clean:
	@echo "Cleaning..."
	@rm -rf deploy/artifacts/*.log
	@cd lending-pool && rm -rf artifacts cache
	@cd loan-provider && forge clean
	@echo "Done."

# ============ Anvil ============

anvil:
	@anvil --port $(ANVIL_PORT) --chain-id $(LOCAL_CHAIN_ID) --accounts 10 --balance 10000

anvil-stop:
	@pkill -f "anvil" 2>/dev/null || echo "Anvil not running"

# ============ Deployment ============

deploy-local:
	@./deploy/scripts/deploy-local.sh

# ============ Testing (loan-provider) ============

# Default: run unit tests (no RPC needed)
test:
	@cd loan-provider && make test

test\:unit:
	@cd loan-provider && make test:unit

test\:fork:
	@cd loan-provider && make test:fork

test\:loan\:unit:
	@cd loan-provider && make test:loan:unit

test\:vault\:unit:
	@cd loan-provider && make test:vault:unit

test\:liquidation\:unit:
	@cd loan-provider && make test:liquidation:unit

test\:fuzz:
	@cd loan-provider && make test:fuzz

test\:invariant:
	@cd loan-provider && make test:invariant

test\:integration:
	@cd loan-provider && make test:integration

# ============ Testing (lending-pool) ============

test\:lp:
	@echo "Running lending-pool Bitmor tests..."
	@cd lending-pool && npm run test-bitmor

test\:lp\:aave:
	@echo "Running lending-pool Aave tests..."
	@cd lending-pool && npm test

test\:lp\:scenarios:
	@echo "Running lending-pool scenario tests..."
	@cd lending-pool && npm run test-scenarios

# ============ Testing (combined) ============

test\:all: test\:unit test\:lp
	@echo "All tests complete."
