# Swap Routers - Makefile
# ========================
# Commands for building, testing, and deploying UniswapV4Swapper

# Load environment variables
-include .env

# Default target
.PHONY: all
all: build

# ============ Install Dependencies ============

.PHONY: install
install:
	@echo "Installing dependencies..."
	@mkdir -p lib
	@cd lib && ([ -d "v4-core" ] || git clone --depth 1 --recurse-submodules https://github.com/Uniswap/v4-core.git)
	@cd lib && ([ -d "v4-periphery" ] || git clone --depth 1 --recurse-submodules https://github.com/Uniswap/v4-periphery.git)
	@cd lib && ([ -d "universal-router" ] || git clone --depth 1 --recurse-submodules https://github.com/Uniswap/universal-router.git)
	@echo "Dependencies installed!"

.PHONY: update
update:
	@echo "Updating dependencies..."
	@cd lib/v4-core && git pull
	@cd lib/v4-periphery && git pull
	@cd lib/universal-router && git pull
	@echo "Dependencies updated!"

# ============ Build ============

.PHONY: build
build:
	forge build

.PHONY: clean
clean:
	forge clean

.PHONY: fmt
fmt:
	forge fmt

# ============ Test ============

.PHONY: test
test:
	forge test -vvv

.PHONY: test-fork
test-fork:
	@echo "Running fork tests on Base Mainnet..."
	forge test --fork-url base -vvv

.PHONY: test-fork-sepolia
test-fork-sepolia:
	@echo "Running fork tests on Base Sepolia..."
	forge test --fork-url base_sepolia -vvv

.PHONY: coverage
coverage:
	forge coverage

# ============ Deploy ============

.PHONY: deploy-sepolia
deploy-sepolia:
	@echo "Deploying UniswapV4Swapper to Base Sepolia..."
	forge script script/deployment/DeployUniswapV4Swapper.s.sol \
		--rpc-url $(BASE_SEPOLIA_RPC_URL) \
		--account deployer \
		--broadcast \
		--verify \
		-vvvv

.PHONY: deploy-mainnet
deploy-mainnet:
	@echo "Deploying UniswapV4Swapper to Base Mainnet..."
	forge script script/deployment/DeployUniswapV4Swapper.s.sol \
		--rpc-url $(BASE_RPC_URL) \
		--account deployer \
		--broadcast \
		--verify \
		-vvvv

.PHONY: deploy-local
deploy-local:
	@echo "Deploying UniswapV4Swapper to local Anvil..."
	forge script script/deployment/DeployUniswapV4Swapper.s.sol \
		--rpc-url http://127.0.0.1:8545 \
		--broadcast \
		-vvvv

# ============ Help ============

.PHONY: help
help:
	@echo "Swap Routers - Available Commands"
	@echo "=================================="
	@echo ""
	@echo "Setup:"
	@echo "  make install        - Install dependencies (v4-core, v4-periphery, universal-router)"
	@echo "  make update         - Update dependencies"
	@echo ""
	@echo "Build:"
	@echo "  make build          - Compile contracts"
	@echo "  make clean          - Remove build artifacts"
	@echo "  make fmt            - Format code"
	@echo ""
	@echo "Test:"
	@echo "  make test              - Run tests (no fork)"
	@echo "  make test-fork         - Run fork tests on Base Mainnet"
	@echo "  make test-fork-sepolia - Run fork tests on Base Sepolia"
	@echo "  make coverage          - Generate coverage report"
	@echo ""
	@echo "Deploy:"
	@echo "  make deploy-sepolia - Deploy to Base Sepolia"
	@echo "  make deploy-mainnet - Deploy to Base Mainnet"
	@echo "  make deploy-local   - Deploy to local Anvil"
