#!/bin/bash
set -e

# Bitmor Protocol - Local Deployment Orchestrator (Optimized)
# Deploys complete protocol to Anvil (chainId 31337)
# Uses consolidated scripts for faster deployment

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

mkdir -p "$ROOT/loan-provider/deployments"

# ============ Phase 1: loan-provider (consolidated) ============
log ""
log "=========================================="
log "Phase 1: loan-provider (AccessManager, Tokens, Oracles, BTCVault)"
log "=========================================="
cd "$ROOT/loan-provider"

FOUNDRY_PROFILE=local forge script script/deployment/local/DeployPhase1Local.s.sol:DeployPhase1Local \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -v

log "Phase 1 complete."

# ============ Phase 2: lending-pool ============
log ""
log "=========================================="
log "Phase 2: lending-pool (LendingPool with bvBTC reserve)"
log "=========================================="
cd "$ROOT/lending-pool"

npm run bitmor:localhost:dev:migration

log "Phase 2 complete."

# ============ Phase 3a: loan-provider (deploy + roles) ============
log ""
log "=========================================="
log "Phase 3a: loan-provider (Deploy contracts + Setup roles)"
log "=========================================="
cd "$ROOT/loan-provider"

FOUNDRY_PROFILE=local forge script script/deployment/local/DeployPhase3Local.s.sol:DeployPhase3Local \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast --slow -v

log "Phase 3a complete. Contracts deployed, roles granted."

# ============ Phase 3b: Schedule operations ============
log ""
log "=========================================="
log "Phase 3b: Schedule timelocked operations"
log "=========================================="

FOUNDRY_PROFILE=local forge script script/deployment/local/SchedulePhase3Local.s.sol:SchedulePhase3Local \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -v

log "Phase 3b complete. Operations scheduled."

# ============ Phase 3c: Advance time and execute ============
log ""
log "=========================================="
log "Phase 3c: Advance Anvil time and execute scheduled operations"
log "=========================================="

# Advance Anvil's time by 1 day + 10 minutes + 1 second (87001 seconds)
# Matches DeploymentConstants.TIME_ADVANCE_SECONDS
TIME_ADVANCE=87001
log "Advancing Anvil time by $TIME_ADVANCE seconds (1 day + 10 min + 1 second)..."
cast rpc evm_increaseTime $TIME_ADVANCE --rpc-url "$RPC" > /dev/null
cast rpc evm_mine --rpc-url "$RPC" > /dev/null
log "Time advanced and block mined."

# Execute scheduled operations
FOUNDRY_PROFILE=local forge script script/deployment/local/ExecutePhase3Local.s.sol:ExecutePhase3Local \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -v

log "Phase 3c complete. All operations executed."

# ============ Phase 4: Post-Deploy Validation ============
log ""
log "=========================================="
log "Phase 4: Post-Deploy Validation"
log "=========================================="

FOUNDRY_PROFILE=local forge script script/deployment/PostDeployChecks.s.sol:PostDeployChecks \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" -v

log "Phase 4 complete. All deployment checks passed."

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
