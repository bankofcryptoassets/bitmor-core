#!/bin/bash
set -e

# Bitmor Protocol - Fork Deployment Orchestrator
# Deploys complete protocol to Anvil forking Base mainnet (chainId 31337, Base state)
# Requires: BASE_MAINNET_RPC_URL in loan-provider/.env

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RPC="http://127.0.0.1:8545"
DEPLOY_PREFIX="DEPLOY-FORK"
source "$(dirname "$0")/_common.sh"

load_env "$ROOT/loan-provider/.env"

# Anvil's default funded account (Account 0)
PRIVATE_KEY="${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"

# ============ Preflight Checks ============
log "=== Preflight Checks ==="
check_rpc "$RPC" "31337" "Start with: make anvil-fork"

mkdir -p "$ROOT/deployments/31337-fork"

# ============ Phase 0: swap-routers (UniswapV4Swapper) ============
log ""
log "=========================================="
log "Phase 0: swap-routers (Deploy UniswapV4Swapper)"
log "=========================================="
cd "$ROOT/swap-routers"

make -C "$ROOT/swap-routers" deploy-fork FORK_PRIVATE_KEY="$PRIVATE_KEY"

# Read swapper from swap-routers and write to unified registry
bitmor_deploy save-swap --chain 31337-fork --swap-routers-dir "$ROOT/swap-routers"
SWAPPER_ADDR=$(bitmor_deploy get --chain 31337-fork --key loanProvider.swapper)
[ -n "$SWAPPER_ADDR" ] || error "Failed to read UniswapV4Swapper from registry"
log "UniswapV4Swapper deployed at: $SWAPPER_ADDR"

# Export for Phase 3 to pick up
export SWAP_ADAPTER_OVERRIDE="$SWAPPER_ADDR"

log "Phase 0 complete."

# ============ Phase 1: loan-provider ============
log ""
log "=========================================="
log "Phase 1: loan-provider (AccessManager, BTCVault with real cbBTC)"
log "=========================================="
cd "$ROOT/loan-provider"

make -C "$ROOT/loan-provider" deploy:phase1:fork FORK_PRIVATE_KEY="$PRIVATE_KEY"
bitmor_deploy save --chain 31337-fork --phase phase1 --script DeployPhase1Fork --env fork

log "Phase 1 complete."

# ============ Phase 2: lending-pool ============
log ""
log "=========================================="
log "Phase 2: lending-pool (LendingPool with real token reserves)"
log "=========================================="
cd "$ROOT/lending-pool"

FORK=base npm run bitmor:localhost:dev:migration
bitmor_deploy save-lp --chain 31337-fork

log "Phase 2 complete."

# ============ Phase 3: libraries + contracts + strategies + roles ============
log ""
log "=========================================="
log "Phase 3: loan-provider (Libraries + Contracts + Strategies + Roles)"
log "=========================================="
cd "$ROOT/loan-provider"

log "Deploying linked libraries..."
make -C "$ROOT/loan-provider" deploy:libraries:fork FORK_PRIVATE_KEY="$PRIVATE_KEY"
bitmor_deploy save --chain 31337-fork --phase libraries --script DeployLibraries --env fork

LIBRARY_FLAG=$(bitmor_deploy libraries --chain 31337-fork)

make -C "$ROOT/loan-provider" deploy:phase3:fork FORK_PRIVATE_KEY="$PRIVATE_KEY" LIBRARY_FLAG="$LIBRARY_FLAG"
bitmor_deploy save --chain 31337-fork --phase phase3 --script DeployPhase3Fork --env fork

log "Phase 3 complete."

# ============ Phase 4: Validation ============
log ""
log "=========================================="
log "Phase 4: Post-Deploy Validation"
log "=========================================="

make -C "$ROOT/loan-provider" deploy:check:fork FORK_PRIVATE_KEY="$PRIVATE_KEY" LIBRARY_FLAG="$LIBRARY_FLAG"

log "Phase 4 complete."

# ============ Summary ============
log ""
log "=========================================="
log "Fork Deployment Complete!"
log "=========================================="
log ""
log "Chain: Base mainnet fork (chain ID 31337, forked state from Base 8453)"
log "Addresses saved to: deployments/31337-fork/latest.json"
log ""
log "Verify with:"
log "  cat deployments/31337-fork/latest.json | jq ."
