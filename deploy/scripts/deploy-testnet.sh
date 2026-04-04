#!/bin/bash
set -e

# Bitmor Protocol - Testnet Deployment Orchestrator (Base Sepolia)
# Deploys complete protocol with full mocks to Base Sepolia (chainId 84532)
# Uses cast wallet `bitmor_owner` for signing
# Requires: BASE_SEPOLIA_RPC_URL and DEPLOYER_PRIVATE_KEY in loan-provider/.env or environment

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEPLOY_PREFIX="DEPLOY-TESTNET"
source "$(dirname "$0")/_common.sh"

load_env "$ROOT/loan-provider/.env"

RPC="${BASE_SEPOLIA_RPC_URL:?BASE_SEPOLIA_RPC_URL not set — add to loan-provider/.env}"

# ============ Preflight Checks ============
log "=== Preflight Checks ==="
check_rpc "$RPC" "84532" "Check BASE_SEPOLIA_RPC_URL in loan-provider/.env"

# Verify bitmor_owner wallet exists
cast wallet list 2>/dev/null | grep -q "bitmor_owner" || error "Cast wallet 'bitmor_owner' not found. Create with: cast wallet import bitmor_owner --interactive"

mkdir -p "$ROOT/deployments/84532"

# ============ Phase 1: loan-provider (consolidated) ============
log ""
log "=========================================="
log "Phase 1: loan-provider (AccessManager, Mock Tokens, Mock Oracles, BTCVault)"
log "=========================================="
cd "$ROOT/loan-provider"

make -C "$ROOT/loan-provider" deploy:phase1:testnet RPC_URL="$RPC"
bitmor_deploy save --chain 84532 --phase phase1 --script DeployPhase1Testnet --env testnet

log "Phase 1 complete."

# ============ Phase 2: lending-pool ============
log ""
log "=========================================="
log "Phase 2: lending-pool (LendingPool with bvBTC reserve)"
log "=========================================="
cd "$ROOT/lending-pool"

# Run bitmor:sepolia WITHOUT --verify to avoid nonce desync.
# The synchronous Blockscout/Sourcify verification between deploy and setLendingPoolImpl
# causes ethers to send the next tx with a stale nonce. Verify contracts separately after.
cd "$ROOT/lending-pool" && npm run compile && npx hardhat --network sepolia bitmor:sepolia --skip-registry
bitmor_deploy save-lp --chain 84532

log "Phase 2 complete."

# ============ Phase 3: loan-provider (deploy + strategies + roles) ============
log ""
log "=========================================="
log "Phase 3: loan-provider (Deploy contracts + Strategies + Roles)"
log "=========================================="
cd "$ROOT/loan-provider"

log "Deploying linked libraries..."
make -C "$ROOT/loan-provider" deploy:libraries:testnet RPC_URL="$RPC"
bitmor_deploy save --chain 84532 --phase libraries --script DeployLibraries --env testnet

LIBRARY_FLAG=$(bitmor_deploy libraries --chain 84532)

make -C "$ROOT/loan-provider" deploy:phase3:testnet RPC_URL="$RPC" LIBRARY_FLAG="$LIBRARY_FLAG"
bitmor_deploy save --chain 84532 --phase phase3 --script DeployPhase3Testnet --env testnet

log "Phase 3 complete. Contracts deployed, strategies wired, roles granted."

# ============ Phase 4: Post-Deploy Validation ============
log ""
log "=========================================="
log "Phase 4: Post-Deploy Validation"
log "=========================================="

make -C "$ROOT/loan-provider" deploy:check:testnet RPC_URL="$RPC" LIBRARY_FLAG="$LIBRARY_FLAG"

log "Phase 4 complete. All deployment checks passed."

# ============ Summary ============
log ""
log "=========================================="
log "Testnet Deployment Complete! (Base Sepolia)"
log "=========================================="
log ""
log "Addresses saved to: deployments/84532/latest.json"
log ""
log "Verify with:"
log "  cat deployments/84532/latest.json | jq ."
