#!/bin/bash
set -e

# Bitmor Protocol - Local Deployment Orchestrator
# Deploys complete protocol to Anvil (chainId 31337)

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RPC="http://127.0.0.1:8545"

# Anvil's default funded account (Account 0)
PRIVATE_KEY="${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"

log() { echo "[DEPLOY] $1"; }
error() { echo "[ERROR] $1"; exit 1; }

# ============ Preflight Checks ============
log "=== Preflight Checks ==="

cast chain-id --rpc-url "$RPC" > /dev/null 2>&1 || error "Anvil not running. Start with: make anvil"
CHAIN_ID=$(cast chain-id --rpc-url "$RPC")
log "Anvil running (chainId: $CHAIN_ID)"

[ "$CHAIN_ID" = "31337" ] || error "Expected chainId 31337, got $CHAIN_ID"

# ============ Phase 1: loan-provider (vaults) ============
log ""
log "=========================================="
log "Phase 1: loan-provider (AccessManager, Vaults)"
log "=========================================="
cd "$ROOT/loan-provider"

log "Deploying AccessManager..."
forge script script/deployment/DeployAccessManager.s.sol:DeployAccessManager \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -vvv

log "Deploying Mock Tokens (USDC, cbBTC)..."
forge script script/deployment/DeployMockTokens.s.sol:DeployMockTokens \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -vvv

log "Deploying Mock Oracles..."
forge script script/deployment/DeployMockOracles.s.sol:DeployMockOracles \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -vvv

log "Deploying BTCVault (produces bvBTC)..."
forge script script/deployment/DeployBTCVault.s.sol:DeployBTCVault \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -vvv

log "Deploying USDCVault..."
forge script script/deployment/DeployUSDCVault.s.sol:DeployUSDCVault \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -vvv

log "Saving Phase 1 addresses to deployments.json..."
forge script script/deployment/SaveLocalDeployment.s.sol:SaveLocalDeployment \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -vvv

log "Phase 1 complete."

# ============ Phase 2: lending-pool ============
log ""
log "=========================================="
log "Phase 2: lending-pool (LendingPool with bvBTC reserve)"
log "=========================================="
cd "$ROOT/lending-pool"

log "Deploying Bitmor Lending Pool..."
npm run bitmor:localhost:dev:migration

log "Phase 2 complete."

# ============ Phase 3: loan-provider (Loan contracts) ============
log ""
log "=========================================="
log "Phase 3: loan-provider (Loan contracts + AccessManager setup)"
log "=========================================="
cd "$ROOT/loan-provider"

log "Deploying SwapAdapterWrapper..."
forge script script/deployment/DeploySwapAdapterWrapper.s.sol:DeploySwapAdapterWrapper \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -vvv

log "Deploying LoanVault..."
forge script script/deployment/DeployLoanVault.s.sol:DeployLoanVault \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -vvv

log "Deploying Loan..."
forge script script/deployment/DeployLoan.s.sol:DeployLoan \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -vvv

log "Deploying LoanVaultFactory..."
forge script script/deployment/DeployLoanVaultFactory.s.sol:DeployLoanVaultFactory \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -vvv

log "Deploying Strategies..."
forge script script/deployment/DeployStrategies.s.sol:DeployStrategies \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -vvv

log "Running LocalFullSetup (roles, grants, schedule, warp, execute)..."
forge script script/interaction/AccessManager/LocalFullSetup.s.sol:LocalFullSetup \
    --sig "run(bool)" true \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -vvv

log "Saving final addresses..."
forge script script/deployment/SaveDeployedAddresses.s.sol:SaveDeployedAddresses \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -vvv

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
