# Deployment and Testing Infrastructure Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create unified deployment infrastructure with `make deploy-local` to deploy complete Bitmor protocol to local Anvil with bvBTC (vault shares) as collateral.

**Architecture:** Interleaved deployment across modules:
- Phase 1: loan-provider deploys AccessManager, vaults (BTCVault → bvBTC), mocks
- Phase 2: lending-pool reads bvBTC address, deploys LendingPool with bvBTC reserve
- Phase 3: loan-provider reads LendingPool, deploys Loan contracts

**Tech Stack:** Foundry (loan-provider), Hardhat v3 (lending-pool), Bash orchestration, cast wallets

---

## Task 1: Create Deploy Directory Structure

**Files:**
- Create: `deploy/scripts/.gitkeep`
- Create: `deploy/artifacts/.gitkeep`

**Step 1: Create directories**

```bash
mkdir -p deploy/scripts deploy/artifacts
```

**Step 2: Create gitkeep files**

```bash
touch deploy/scripts/.gitkeep deploy/artifacts/.gitkeep
```

**Step 3: Commit**

```bash
git add deploy/
git commit -m "$(cat <<'EOF'
chore: add deploy directory structure

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Create dev Cast Wallet

**Files:** None (keystore operation)

**Step 1: Import Anvil's default account as 'dev' wallet**

```bash
cast wallet import dev --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

**Step 2: Verify wallet exists**

Run: `cast wallet list`

Expected: Shows `dev` in the list

**Step 3: Document in README or DEPLOYMENT_SETUP.md** (done in Task 8)

---

## Task 3: Create SaveLocalDeployment Script

**Files:**
- Create: `loan-provider/script/deployment/SaveLocalDeployment.s.sol`

**Step 1: Create the script**

Create `loan-provider/script/deployment/SaveLocalDeployment.s.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

/// @title SaveLocalDeployment
/// @notice Saves Phase 1 deployment addresses to deployments.json for chainId 31337
contract SaveLocalDeployment is Script {
    using stdJson for string;

    function run(
        address accessManager,
        address cbBTC,
        address usdc,
        address btcVault,
        address usdcVault,
        address mockAave,
        address btcOracle,
        address usdcOracle
    ) external {
        string memory json = "local";

        // Network config - lending-pool reads collateralAsset from here
        json.serialize("network", "local");
        json.serialize("collateralAsset", btcVault);  // bvBTC = BTCVault address
        json.serialize("debtAsset", usdc);
        json.serialize("cbBTC", cbBTC);
        json.serialize("accessManager", accessManager);
        json.serialize("usdcVault", usdcVault);
        json.serialize("aaveV3Pool", mockAave);
        json.serialize("btcOracle", btcOracle);
        string memory output = json.serialize("usdcOracle", usdcOracle);

        // Write to deployments.json under chainId 31337
        string memory path = "./deployments.json";
        vm.writeJson(output, path, ".deployments.31337.networkConfig");

        console.log("=== Local Deployment Saved ===");
        console.log("Chain ID: 31337");
        console.log("bvBTC (collateralAsset):", btcVault);
        console.log("USDC (debtAsset):", usdc);
        console.log("Saved to:", path);
    }
}
```

**Step 2: Verify compilation**

Run: `cd loan-provider && forge build --match-contract SaveLocalDeployment`

Expected: `Compiler run successful`

**Step 3: Commit**

```bash
cd loan-provider
git add script/deployment/SaveLocalDeployment.s.sol
git commit -m "$(cat <<'EOF'
feat(loan-provider): add SaveLocalDeployment script

Saves Phase 1 addresses to deployments.json for chainId 31337.
Lending-pool reads collateralAsset (bvBTC) from this file.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Create DeployMockTokens Script

**Files:**
- Create: `loan-provider/script/deployment/DeployMockTokens.s.sol`

**Step 1: Create the script**

Create `loan-provider/script/deployment/DeployMockTokens.s.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {MockUSDC, MockCbBTC} from "@bitmor/mocks/MintableERC20.sol";

/// @title DeployMockTokens
/// @notice Deploys mock USDC and cbBTC tokens for local testing
contract DeployMockTokens is Script {
    function run() external returns (address usdc, address cbBTC) {
        vm.startBroadcast();

        MockUSDC mockUSDC = new MockUSDC();
        MockCbBTC mockCbBTC = new MockCbBTC();

        vm.stopBroadcast();

        usdc = address(mockUSDC);
        cbBTC = address(mockCbBTC);

        console.log("=== Mock Tokens Deployed ===");
        console.log("MockUSDC:", usdc);
        console.log("MockCbBTC:", cbBTC);

        return (usdc, cbBTC);
    }
}
```

**Step 2: Verify compilation**

Run: `cd loan-provider && forge build --match-contract DeployMockTokens`

Expected: `Compiler run successful`

**Step 3: Commit**

```bash
cd loan-provider
git add script/deployment/DeployMockTokens.s.sol
git commit -m "$(cat <<'EOF'
feat(loan-provider): add DeployMockTokens script

Deploys MockUSDC (6 decimals) and MockCbBTC (8 decimals).

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Create DeployMockOracles Script

**Files:**
- Create: `loan-provider/script/deployment/DeployMockOracles.s.sol`
- Create: `loan-provider/test/mock/MockChainlinkOracle.sol` (if not exists)

**Step 1: Create MockChainlinkOracle if needed**

Create `loan-provider/test/mock/MockChainlinkOracle.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title MockChainlinkOracle
/// @notice Mock Chainlink AggregatorV3Interface for testing
contract MockChainlinkOracle {
    uint8 public immutable decimals;
    string public description;
    uint256 public constant version = 3;

    int256 private _latestAnswer;
    uint256 private _latestTimestamp;
    uint80 private _latestRoundId;

    mapping(uint80 => int256) private _answers;
    mapping(uint80 => uint256) private _timestamps;

    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);

    constructor(uint8 _decimals, int256 _initialAnswer, string memory _description) {
        decimals = _decimals;
        description = _description;
        _updateAnswer(_initialAnswer);
    }

    function updateAnswer(int256 _answer) external {
        _updateAnswer(_answer);
    }

    function makeStale(uint256 secondsOld) external {
        _latestTimestamp = block.timestamp - secondsOld;
        _timestamps[_latestRoundId] = _latestTimestamp;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_latestRoundId, _latestAnswer, _latestTimestamp, _latestTimestamp, _latestRoundId);
    }

    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _answers[_roundId], _timestamps[_roundId], _timestamps[_roundId], _roundId);
    }

    function latestAnswer() external view returns (int256) {
        return _latestAnswer;
    }

    function _updateAnswer(int256 _answer) internal {
        _latestRoundId++;
        _latestAnswer = _answer;
        _latestTimestamp = block.timestamp;
        _answers[_latestRoundId] = _answer;
        _timestamps[_latestRoundId] = block.timestamp;
        emit AnswerUpdated(_answer, _latestRoundId, block.timestamp);
    }
}
```

**Step 2: Create DeployMockOracles script**

Create `loan-provider/script/deployment/DeployMockOracles.s.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {MockChainlinkOracle} from "../../test/mock/MockChainlinkOracle.sol";

/// @title DeployMockOracles
/// @notice Deploys mock Chainlink oracles for BTC and USDC
contract DeployMockOracles is Script {
    int256 public constant BTC_PRICE = 100_000e8;  // $100,000
    int256 public constant USDC_PRICE = 1e8;       // $1.00

    function run() external returns (address btcOracle, address usdcOracle) {
        vm.startBroadcast();

        MockChainlinkOracle btc = new MockChainlinkOracle(8, BTC_PRICE, "BTC/USD");
        MockChainlinkOracle usdc = new MockChainlinkOracle(8, USDC_PRICE, "USDC/USD");

        vm.stopBroadcast();

        btcOracle = address(btc);
        usdcOracle = address(usdc);

        console.log("=== Mock Oracles Deployed ===");
        console.log("BTC Oracle:", btcOracle, "Price:", uint256(BTC_PRICE));
        console.log("USDC Oracle:", usdcOracle, "Price:", uint256(USDC_PRICE));

        return (btcOracle, usdcOracle);
    }
}
```

**Step 3: Verify compilation**

Run: `cd loan-provider && forge build --match-contract DeployMockOracles`

Expected: `Compiler run successful`

**Step 4: Commit**

```bash
cd loan-provider
git add test/mock/MockChainlinkOracle.sol script/deployment/DeployMockOracles.s.sol
git commit -m "$(cat <<'EOF'
feat(loan-provider): add MockChainlinkOracle and deploy script

MockChainlinkOracle: Chainlink-compatible with updateAnswer() and makeStale().
DeployMockOracles: Deploys BTC ($100k) and USDC ($1) oracles.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Create DeployBTCVault Script

**Files:**
- Create: `loan-provider/script/deployment/DeployBTCVault.s.sol`

**Step 1: Create the script**

Create `loan-provider/script/deployment/DeployBTCVault.s.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {BTCVault} from "@btcVault/BTCVault.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

/// @title DeployBTCVault
/// @notice Deploys BTCVault which produces bvBTC (vault shares)
contract DeployBTCVault is Script {
    function run() external returns (address btcVault) {
        // Read cbBTC and AccessManager from previous deployments
        address cbBTC = DevOpsTools.get_most_recent_deployment(
            "MockCbBTC",
            block.chainid
        );
        address accessManager = DevOpsTools.get_most_recent_deployment(
            "AccessManager",
            block.chainid
        );

        require(cbBTC != address(0), "MockCbBTC not deployed");
        require(accessManager != address(0), "AccessManager not deployed");

        vm.startBroadcast();

        BTCVault vault = new BTCVault(cbBTC, accessManager);

        vm.stopBroadcast();

        btcVault = address(vault);

        console.log("=== BTCVault Deployed ===");
        console.log("BTCVault (bvBTC):", btcVault);
        console.log("Underlying (cbBTC):", cbBTC);
        console.log("AccessManager:", accessManager);

        return btcVault;
    }
}
```

**Step 2: Verify compilation**

Run: `cd loan-provider && forge build --match-contract DeployBTCVault`

Expected: `Compiler run successful`

**Step 3: Commit**

```bash
cd loan-provider
git add script/deployment/DeployBTCVault.s.sol
git commit -m "$(cat <<'EOF'
feat(loan-provider): add DeployBTCVault script

Deploys BTCVault with cbBTC as underlying asset.
BTCVault address IS bvBTC (the ERC-4626 share token).

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Create Local Deployment Orchestrator

**Files:**
- Create: `deploy/scripts/deploy-local.sh`

**Step 1: Create the orchestrator script**

Create `deploy/scripts/deploy-local.sh`:

```bash
#!/bin/bash
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RPC="http://127.0.0.1:8545"
ACCOUNT="${DEPLOY_ACCOUNT:-dev}"

log() { echo "[DEPLOY] $1"; }
error() { echo "[ERROR] $1"; exit 1; }

# ============ Preflight Checks ============
log "=== Preflight Checks ==="

# Check Anvil is running
cast chain-id --rpc-url "$RPC" > /dev/null 2>&1 || error "Anvil not running. Start with: make anvil"
CHAIN_ID=$(cast chain-id --rpc-url "$RPC")
log "Anvil running (chainId: $CHAIN_ID)"

# Verify it's chainId 31337
[ "$CHAIN_ID" = "31337" ] || error "Expected chainId 31337, got $CHAIN_ID"

# Check cast wallet exists
cast wallet list 2>/dev/null | grep -q "$ACCOUNT" || error "Wallet '$ACCOUNT' not found. Create with: cast wallet import $ACCOUNT --private-key <key>"
log "Using account: $ACCOUNT"

# ============ Phase 1: loan-provider (vaults) ============
log ""
log "=========================================="
log "Phase 1: loan-provider (AccessManager, Vaults)"
log "=========================================="
cd "$ROOT/loan-provider"

log "Deploying AccessManager..."
forge script script/deployment/DeployAccessManager.s.sol:DeployAccessManager \
    --rpc-url "$RPC" --account "$ACCOUNT" --broadcast -vvv

log "Deploying Mock Tokens (USDC, cbBTC)..."
forge script script/deployment/DeployMockTokens.s.sol:DeployMockTokens \
    --rpc-url "$RPC" --account "$ACCOUNT" --broadcast -vvv

log "Deploying Mock Oracles..."
forge script script/deployment/DeployMockOracles.s.sol:DeployMockOracles \
    --rpc-url "$RPC" --account "$ACCOUNT" --broadcast -vvv

log "Deploying BTCVault (produces bvBTC)..."
forge script script/deployment/DeployBTCVault.s.sol:DeployBTCVault \
    --rpc-url "$RPC" --account "$ACCOUNT" --broadcast -vvv

log "Deploying USDCVault..."
forge script script/deployment/DeployUSDCVault.s.sol:DeployUSDCVault \
    --rpc-url "$RPC" --account "$ACCOUNT" --broadcast -vvv

log "Saving Phase 1 addresses to deployments.json..."
forge script script/deployment/SaveLocalDeployment.s.sol:SaveLocalDeployment \
    --rpc-url "$RPC" --account "$ACCOUNT" --broadcast -vvv

log "Phase 1 complete. bvBTC saved to deployments.json"

# ============ Phase 2: lending-pool ============
log ""
log "=========================================="
log "Phase 2: lending-pool (LendingPool with bvBTC reserve)"
log "=========================================="
cd "$ROOT/lending-pool"

log "Deploying Bitmor Lending Pool..."
npm run bitmor:localhost:dev:migration

log "Phase 2 complete. LendingPool deployed."

# ============ Phase 3: loan-provider (Loan contracts) ============
log ""
log "=========================================="
log "Phase 3: loan-provider (Loan contracts)"
log "=========================================="
cd "$ROOT/loan-provider"

log "Deploying SwapAdapterWrapper..."
forge script script/deployment/DeploySwapAdapterWrapper.s.sol:DeploySwapAdapterWrapper \
    --rpc-url "$RPC" --account "$ACCOUNT" --broadcast -vvv

log "Deploying LoanVault..."
forge script script/deployment/DeployLoanVault.s.sol:DeployLoanVault \
    --rpc-url "$RPC" --account "$ACCOUNT" --broadcast -vvv

log "Deploying Loan..."
forge script script/deployment/DeployLoan.s.sol:DeployLoan \
    --rpc-url "$RPC" --account "$ACCOUNT" --broadcast -vvv

log "Deploying LoanVaultFactory..."
forge script script/deployment/DeployLoanVaultFactory.s.sol:DeployLoanVaultFactory \
    --rpc-url "$RPC" --account "$ACCOUNT" --broadcast -vvv

log "Configuring: SetLoanVaultFactory..."
forge script script/interaction/SetLoanVaultFactory.s.sol:SetLoanVaultFactory \
    --rpc-url "$RPC" --account "$ACCOUNT" --broadcast -vvv

log "Configuring: SetBitmorLoan..."
forge script script/interaction/SetBitmorLoan.s.sol:SetBitmorLoan \
    --rpc-url "$RPC" --account "$ACCOUNT" --broadcast -vvv

log "Saving final addresses..."
forge script script/deployment/SaveDeployedAddresses.s.sol:SaveDeployedAddresses \
    --rpc-url "$RPC" --account "$ACCOUNT" --broadcast -vvv

# ============ Summary ============
log ""
log "=========================================="
log "Deployment Complete!"
log "=========================================="
log ""
log "Addresses saved to:"
log "  - loan-provider/deployments.json"
log "  - lending-pool/deployed-contracts.json"
log ""
log "Verify with:"
log "  cat loan-provider/deployments.json | jq '.deployments[\"31337\"]'"
```

**Step 2: Make executable**

```bash
chmod +x deploy/scripts/deploy-local.sh
```

**Step 3: Verify script runs (dry run)**

Run: `./deploy/scripts/deploy-local.sh` (with Anvil running)

Expected: Should fail at "Wallet 'dev' not found" if wallet not created

**Step 4: Commit**

```bash
git add deploy/scripts/deploy-local.sh
git commit -m "$(cat <<'EOF'
feat(deploy): add local deployment orchestrator

Three-phase deployment to Anvil:
1. loan-provider: AccessManager, vaults (BTCVault → bvBTC)
2. lending-pool: LendingPool with bvBTC reserve
3. loan-provider: Loan contracts

Uses cast wallet 'dev' (or DEPLOY_ACCOUNT env var).

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Create Root Makefile

**Files:**
- Create: `Makefile` (repository root)

**Step 1: Create Makefile**

Create `Makefile` at repository root:

```makefile
# Bitmor Protocol - Root Makefile

.PHONY: help install build clean anvil anvil-stop deploy-local test test-unit test-lending-pool

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
	@echo "  make anvil         Start Anvil (localhost:8545, chainId 31337)"
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
	anvil --port 8545 --chain-id 31337 --accounts 10 --balance 10000

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
```

**Step 2: Verify Makefile**

Run: `make help`

Expected: Shows help text

**Step 3: Commit**

```bash
git add Makefile
git commit -m "$(cat <<'EOF'
feat: add root Makefile

Commands:
- make install/build/clean
- make anvil/anvil-stop
- make deploy-local
- make test/test-unit/test-lending-pool

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Update HelperConfig for Local Deployment

**Files:**
- Modify: `loan-provider/script/HelperConfig.s.sol`

**Step 1: Read current HelperConfig**

Run: `head -100 loan-provider/script/HelperConfig.s.sol`

**Step 2: Add chainId 31337 handling**

Ensure HelperConfig handles chainId 31337 (local Anvil). Add case if missing:

```solidity
function getNetworkConfig() public returns (NetworkConfig memory) {
    if (block.chainid == 31337) {
        return _getLocalNetworkConfig();
    } else if (block.chainid == 84532) {
        return _getBaseSepoliaConfig();
    }
    revert("Unsupported chain");
}

function _getLocalNetworkConfig() internal returns (NetworkConfig memory) {
    // Read from deployments.json or use defaults
    return NetworkConfig({
        bitmorPool: _readAddressFromDeployments("bitmorPool"),
        aaveV3Pool: _readAddressFromDeployments("aaveV3Pool"),
        collateralAsset: _readAddressFromDeployments("collateralAsset"),
        debtAsset: _readAddressFromDeployments("debtAsset"),
        // ... other fields
    });
}
```

**Step 3: Verify compilation**

Run: `cd loan-provider && forge build`

Expected: `Compiler run successful`

**Step 4: Commit**

```bash
cd loan-provider
git add script/HelperConfig.s.sol
git commit -m "$(cat <<'EOF'
feat(loan-provider): add chainId 31337 support to HelperConfig

Enables local Anvil deployment by reading addresses from deployments.json.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Update DEPLOYMENT_SETUP.md

**Files:**
- Modify: `DEPLOYMENT_SETUP.md`

**Step 1: Rewrite DEPLOYMENT_SETUP.md**

Replace `DEPLOYMENT_SETUP.md`:

```markdown
# Bitmor Protocol Deployment Guide

## Quick Start (Local)

```bash
# 1. Create dev wallet (one-time setup)
cast wallet import dev --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# 2. Start Anvil (terminal 1)
make anvil

# 3. Deploy protocol (terminal 2)
make deploy-local

# 4. Run tests
make test
```

## Architecture

```
cbBTC → BTCVault → bvBTC (vault shares) → Lending Pool (collateral) → Borrow USDC
```

**Key:** The lending pool uses **bvBTC** (BTCVault shares) as collateral, not raw cbBTC.

## Deployment Phases

### Phase 1: loan-provider (Foundry → Anvil)
- AccessManager
- Mock tokens (USDC, cbBTC)
- Mock oracles (BTC, USDC)
- BTCVault → produces **bvBTC**
- USDCVault
- Saves `collateralAsset` (bvBTC address) to `deployments.json`

### Phase 2: lending-pool (Hardhat → same Anvil)
- Reads bvBTC from `../loan-provider/deployments.json`
- Deploys LendingPool with bvBTC + USDC reserves
- Deploys AaveOracle with bvBTC pricing

### Phase 3: loan-provider (Foundry → same Anvil)
- Reads LendingPool from `../lending-pool/deployed-contracts.json`
- Loan, LoanVault, LoanVaultFactory
- Post-deployment configuration

## Commands

| Command | Description |
|---------|-------------|
| `make anvil` | Start local Anvil (chainId 31337) |
| `make deploy-local` | Deploy complete protocol |
| `make test` | Run all tests |
| `make build` | Build all contracts |
| `make install` | Install dependencies |

## Prerequisites

### Required Wallets

```bash
# Create dev wallet for local deployment
cast wallet import dev --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# For testnet deployment
cast wallet import bitmor_owner --interactive
cast wallet import bitmor_user --interactive
```

### Environment Variables

**loan-provider/.env:**
```
BASE_SEPOLIA_RPC_URL=https://...
ETHERSCAN_KEY=...
```

**lending-pool/.env:**
```
MNEMONIC="..."
ALCHEMY_KEY=...
ETHERSCAN_KEY=...
```

## Testnet Deployment (Base Sepolia)

```bash
# Use bitmor_owner account
DEPLOY_ACCOUNT=bitmor_owner make deploy-local

# Or use existing Makefile targets
cd lending-pool && npm run aave:baseSepolia:full:migration
cd loan-provider && make setup
```

## Troubleshooting

### "Wallet 'dev' not found"
```bash
cast wallet import dev --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

### "Anvil not running"
```bash
make anvil
```

### "Expected chainId 31337"
```bash
# Restart Anvil with correct chainId
make anvil-stop
make anvil
```

### "bvBTC address not found"
Ensure Phase 1 completed and `loan-provider/deployments.json` contains `collateralAsset`.
```

**Step 2: Commit**

```bash
git add DEPLOYMENT_SETUP.md
git commit -m "$(cat <<'EOF'
docs: comprehensive local deployment guide

- Quick start with cast wallet setup
- Three-phase deployment explanation
- bvBTC as collateral architecture
- Troubleshooting section

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Verification

**1. Prerequisites:**
```bash
cast wallet import dev --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

**2. Build:**
```bash
make build
```

**3. Start Anvil:**
```bash
make anvil &
sleep 3
```

**4. Deploy:**
```bash
make deploy-local
```

**5. Verify addresses:**
```bash
cat loan-provider/deployments.json | jq '.deployments["31337"]'
cat lending-pool/deployed-contracts.json | jq '.LendingPool.localhost'
```

**6. Run tests:**
```bash
make test
```

---

## Files Summary

| Action | File |
|--------|------|
| Create | `deploy/scripts/deploy-local.sh` |
| Create | `Makefile` (root) |
| Create | `loan-provider/script/deployment/SaveLocalDeployment.s.sol` |
| Create | `loan-provider/script/deployment/DeployMockTokens.s.sol` |
| Create | `loan-provider/script/deployment/DeployMockOracles.s.sol` |
| Create | `loan-provider/script/deployment/DeployBTCVault.s.sol` |
| Create | `loan-provider/test/mock/MockChainlinkOracle.sol` |
| Modify | `loan-provider/script/HelperConfig.s.sol` |
| Update | `DEPLOYMENT_SETUP.md` |
