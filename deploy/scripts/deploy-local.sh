#!/bin/bash
set -e

# Bitmor Protocol - Local Deployment Orchestrator (Optimized)
# Deploys complete protocol to Anvil (chainId 31337)
# Uses consolidated scripts for faster deployment

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEPLOY_PREFIX="DEPLOY"
source "$(dirname "$0")/_common.sh"

RPC="http://127.0.0.1:8545"

# Anvil's default funded account (Account 0)
PRIVATE_KEY="${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"

# ============ Preflight Checks ============
log "=== Preflight Checks ==="
check_rpc "$RPC" "31337" "Start with: make anvil"

mkdir -p "$ROOT/loan-provider/deployments"

# ============ Phase 1: loan-provider (consolidated) ============
log ""
log "=========================================="
log "Phase 1: loan-provider (AccessManager, Tokens, Oracles, BTCVault)"
log "=========================================="
cd "$ROOT/loan-provider"

make -C "$ROOT/loan-provider" deploy:phase1:local LOCAL_PRIVATE_KEY="$PRIVATE_KEY"

log "Phase 1 complete."

# ============ Phase 2: lending-pool ============
log ""
log "=========================================="
log "Phase 2: lending-pool (LendingPool with bvBTC reserve)"
log "=========================================="
cd "$ROOT/lending-pool"

npm run bitmor:localhost:dev:migration

log "Phase 2 complete."

# ============ Phase 3: loan-provider (deploy + strategies + roles) ============
log ""
log "=========================================="
log "Phase 3: loan-provider (Deploy contracts + Strategies + Roles)"
log "=========================================="
cd "$ROOT/loan-provider"

# Deploy linked libraries
log "Deploying linked libraries..."
make -C "$ROOT/loan-provider" deploy:libraries:local LOCAL_PRIVATE_KEY="$PRIVATE_KEY"

# Read deployed addresses and build LIBRARY_FLAG
cd "$ROOT/loan-provider"
read_library_addresses "31337"

# Deploy Phase 3
make -C "$ROOT/loan-provider" deploy:phase3:local LOCAL_PRIVATE_KEY="$PRIVATE_KEY" LIBRARY_FLAG="$LIBRARY_FLAG"

log "Phase 3 complete. Contracts deployed, strategies wired, roles granted."

# ============ Phase 4: Post-Deploy Validation ============
log ""
log "=========================================="
log "Phase 4: Post-Deploy Validation"
log "=========================================="

make -C "$ROOT/loan-provider" deploy:check:local LOCAL_PRIVATE_KEY="$PRIVATE_KEY" LIBRARY_FLAG="$LIBRARY_FLAG"

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
