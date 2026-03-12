# Bitmor Protocol - Root Makefile

.PHONY: help install build clean anvil anvil-stop deploy-local test coverage \
	test\:unit test\:fork test\:loan\:unit test\:vault\:unit test\:strategy\:unit \
	test\:liquidation\:unit test\:fuzz test\:invariant \
	test\:integration test\:integration\:setup test\:integration\:access \
	test\:integration\:liquidation test\:integration\:lifecycle \
	test\:integration\:vault test\:integration\:initloan \
	test\:lp test\:lp\:aave test\:lp\:scenarios test\:all \
	coverage coverage-lcov coverage-html

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
	@echo "  make install             Install dependencies + configure git hooks"
	@echo "  make build               Build all contracts"
	@echo "  make clean               Clean build artifacts"
	@echo ""
	@echo "Formatting:"
	@echo "  make format              Format all code (Prettier + Forge)"
	@echo "  make format-check        Check formatting without changes"
	@echo ""
	@echo "Local Development:"
	@echo "  make anvil               Start Anvil (localhost:$(ANVIL_PORT), chainId $(LOCAL_CHAIN_ID))"
	@echo "  make anvil-stop          Stop Anvil"
	@echo "  make deploy-local        Deploy full protocol to Anvil"
	@echo ""
	@echo "Testing (loan-provider unit):"
	@echo "  make test                    Run unit tests (default, no RPC needed)"
	@echo "  make test:unit               Run unit tests with mocks"
	@echo "  make test:fork               Run fork tests (requires BASE_SEPOLIA_RPC_URL)"
	@echo "  make test:loan:unit          Run Loan contract unit tests"
	@echo "  make test:vault:unit         Run Vault unit tests"
	@echo "  make test:strategy:unit      Run Strategy unit tests"
	@echo "  make test:liquidation:unit   Run liquidation unit tests"
	@echo "  make test:fuzz               Run fuzz tests (FOUNDRY_PROFILE=fuzz)"
	@echo "  make test:invariant          Run invariant tests (FOUNDRY_PROFILE=invariant)"
	@echo ""
	@echo "Testing (loan-provider integration — requires Anvil + make deploy-local):"
	@echo "  make test:integration              Run all integration tests"
	@echo "  make test:integration:setup        Deployment validation"
	@echo "  make test:integration:access       Access control tests"
	@echo "  make test:integration:liquidation  Liquidation execution"
	@echo "  make test:integration:lifecycle    Init, repay, close flows"
	@echo "  make test:integration:vault        Vault/strategy interaction tests"
	@echo "  make test:integration:initloan     All InitLoan adversarial tests"
	@echo ""
	@echo "Testing (lending-pool):"
	@echo "  make test:lp             Run lending-pool Bitmor tests"
	@echo "  make test:lp:aave        Run lending-pool core Aave tests"
	@echo "  make test:lp:scenarios   Run lending-pool scenario tests"
	@echo ""
	@echo "Testing (combined):"
	@echo "  make test:all            Run all tests (unit + lending-pool)"
	@echo ""
	@echo "See loan-provider/Makefile for single-test and coverage targets."
	@echo ""

# ============ Setup ============

install:
	@echo "Installing dependencies..."
	@cd lending-pool && npm install --legacy-peer-deps
	@cd loan-provider && forge install
	@cd swap-routers && forge install 2>/dev/null || echo "swap-routers: dependencies already present"
	@echo "Configuring git hooks..."
	@git config core.hooksPath .githooks
	@echo "Done."

build:
	@echo "Building contracts..."
	@cd lending-pool && npm run compile
	@cd loan-provider && forge build
	@cd swap-routers && forge build
	@echo "Done."

clean:
	@echo "Cleaning..."
	@rm -rf deploy/artifacts/*.log
	@cd lending-pool && rm -rf artifacts cache
	@cd loan-provider && forge clean
	@cd swap-routers && forge clean
	@echo "Done."

# ============ Formatting ============

format:
	@echo "Formatting lending-pool (Prettier)..."
	@cd lending-pool && npm run prettier:write
	@echo "Formatting loan-provider (Forge)..."
	@cd loan-provider && forge fmt
	@echo "Formatting swap-routers (Forge)..."
	@cd swap-routers && forge fmt
	@echo "Done."

format-check:
	@echo "Checking formatting..."
	@cd lending-pool && npm run prettier:check
	@cd loan-provider && forge fmt --check
	@cd swap-routers && forge fmt --check
	@echo "All files formatted correctly."

# ============ Anvil ============

anvil:
	@anvil --port $(ANVIL_PORT) --chain-id $(LOCAL_CHAIN_ID) --accounts 10 --balance 10000

anvil-stop:
	@pkill -f "anvil" 2>/dev/null || echo "Anvil not running"

# ============ Deployment ============

deploy-local:
	@./deploy/scripts/deploy-local.sh

# Individual phase targets (proxy-based)
deploy\:phase1\:local:
	@cd loan-provider && make deploy:phase1:local

deploy\:phase3\:local:
	@cd loan-provider && make deploy:phase3:local

deploy\:check:
	@cd loan-provider && make deploy:check

# Mainnet deployment
deploy\:phase1\:mainnet:
	@cd loan-provider && make deploy:phase1:mainnet

deploy\:phase3\:mainnet:
	@cd loan-provider && make deploy:phase3:mainnet

deploy\:schedule\:mainnet:
	@cd loan-provider && make deploy:schedule:mainnet

deploy\:transfer\:mainnet:
	@cd loan-provider && make deploy:transfer:mainnet

# Upgrades
upgrade\:uups\:schedule:
	@cd loan-provider && make upgrade:uups:schedule PROXY=$(PROXY) CONTRACT=$(CONTRACT) INIT_DATA=$(INIT_DATA) RPC_URL=$(RPC_URL)

upgrade\:beacon\:schedule:
	@cd loan-provider && make upgrade:beacon:schedule NEW_IMPL=$(NEW_IMPL) RPC_URL=$(RPC_URL)

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

test\:strategy\:unit:
	@cd loan-provider && make test:strategy:unit

test\:liquidation\:unit:
	@cd loan-provider && make test:liquidation:unit

test\:fuzz:
	@cd loan-provider && make test:fuzz

test\:invariant:
	@cd loan-provider && make test:invariant

test\:integration:
	@cd loan-provider && make test:integration

test\:integration\:setup:
	@cd loan-provider && make test:integration:setup

test\:integration\:access:
	@cd loan-provider && make test:integration:access

test\:integration\:liquidation:
	@cd loan-provider && make test:integration:liquidation

test\:integration\:lifecycle:
	@cd loan-provider && make test:integration:lifecycle

test\:integration\:vault:
	@cd loan-provider && make test:integration:vault

test\:integration\:initloan:
	@cd loan-provider && make test:integration:initloan

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

# ============ Coverage ============

coverage:
	@cd loan-provider && make coverage

coverage-lcov:
	@cd loan-provider && make coverage-lcov

coverage-html:
	@cd loan-provider && make coverage-html
