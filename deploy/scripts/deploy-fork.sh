#!/bin/bash
set -e

# Bitmor Protocol - Fork Deployment Orchestrator
# Deploys complete protocol to Anvil forking Base mainnet (chainId 31337, Base state)
# Requires: BASE_MAINNET_RPC_URL in loan-provider/.env

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RPC="http://127.0.0.1:8545"

# Load env vars (grep only valid KEY=VALUE lines to avoid sourcing bare URLs or mnemonics)
if [ -f "$ROOT/loan-provider/.env" ]; then
    set -a
    eval "$(grep -E '^[A-Za-z_][A-Za-z_0-9]*=' "$ROOT/loan-provider/.env" | sed 's/^/export /')"
    set +a
fi

# Anvil's default funded account (Account 0)
PRIVATE_KEY="${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"

log() { echo "[DEPLOY-FORK] $1"; }
error() { echo "[ERROR] $1"; exit 1; }

# ============ Preflight Checks ============
log "=== Preflight Checks ==="

cast chain-id --rpc-url "$RPC" > /dev/null 2>&1 || error "Anvil not running. Start with: make anvil-fork"
CHAIN_ID=$(cast chain-id --rpc-url "$RPC")
log "Anvil running (chainId: $CHAIN_ID)"

[ "$CHAIN_ID" = "31337" ] || error "Expected chainId 31337 (Anvil fork with --chain-id 31337), got $CHAIN_ID. Start with: make anvil-fork"

mkdir -p "$ROOT/loan-provider/deployments"

# ============ Phase 0: swap-routers (UniswapV4Swapper) ============
log ""
log "=========================================="
log "Phase 0: swap-routers (Deploy UniswapV4Swapper)"
log "=========================================="
cd "$ROOT/swap-routers"

FORK=base forge script script/deployment/DeployUniswapV4Swapper.s.sol:DeployUniswapV4Swapper \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -v

# Read deployed swapper address from swap-routers/deployments.json
SWAPPER_ADDR=$(jq -r '.deployments["31337"].contracts.uniswapV4Swapper' deployments.json 2>/dev/null)
[ -n "$SWAPPER_ADDR" ] && [ "$SWAPPER_ADDR" != "null" ] || error "Failed to read UniswapV4Swapper address from swap-routers/deployments.json"
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

FORK=base FOUNDRY_PROFILE=fork-deploy forge script script/deployment/fork/DeployPhase1Fork.s.sol:DeployPhase1Fork \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast --force -v

log "Phase 1 complete."

# ============ Phase 2: lending-pool ============
log ""
log "=========================================="
log "Phase 2: lending-pool (LendingPool with real token reserves)"
log "=========================================="
cd "$ROOT/lending-pool"

FORK=base npm run bitmor:localhost:dev:migration

log "Phase 2 complete."

# ============ Phase 3a: libraries + contracts + roles ============
log ""
log "=========================================="
log "Phase 3a: loan-provider (Libraries + Contracts + Roles)"
log "=========================================="
cd "$ROOT/loan-provider"

# Deploy linked libraries
log "Deploying linked libraries..."
FORK=base FOUNDRY_PROFILE=fork-deploy forge script script/deployment/DeployLibraries.s.sol:DeployLibraries \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast --force -v

# Read library addresses from deployments.json (under "31337-fork" key)
LOAN_LOGIC_ADDR=$(jq -r '.deployments["31337-fork"].networkConfig.loanLogicLib' deployments.json)
REPAY_LOGIC_ADDR=$(jq -r '.deployments["31337-fork"].networkConfig.repayLogicLib' deployments.json)
CLOSE_LOAN_LOGIC_ADDR=$(jq -r '.deployments["31337-fork"].networkConfig.closeLoanLogicLib' deployments.json)
FLASH_LOAN_LOGIC_ADDR=$(jq -r '.deployments["31337-fork"].networkConfig.flashLoanLogicLib' deployments.json)

[ -n "$LOAN_LOGIC_ADDR" ] && [ "$LOAN_LOGIC_ADDR" != "null" ] || error "Failed to read LoanLogic address"
[ -n "$REPAY_LOGIC_ADDR" ] && [ "$REPAY_LOGIC_ADDR" != "null" ] || error "Failed to read RepayLogic address"
[ -n "$CLOSE_LOAN_LOGIC_ADDR" ] && [ "$CLOSE_LOAN_LOGIC_ADDR" != "null" ] || error "Failed to read CloseLoanLogic address"
[ -n "$FLASH_LOAN_LOGIC_ADDR" ] && [ "$FLASH_LOAN_LOGIC_ADDR" != "null" ] || error "Failed to read FlashLoanLogic address"

log "Libraries deployed:"
log "  LoanLogic: $LOAN_LOGIC_ADDR"
log "  RepayLogic: $REPAY_LOGIC_ADDR"
log "  CloseLoanLogic: $CLOSE_LOAN_LOGIC_ADDR"
log "  FlashLoanLogic: $FLASH_LOAN_LOGIC_ADDR"

LIBRARY_FLAG="--libraries src/libraries/logic/LoanLogic.sol:LoanLogic:$LOAN_LOGIC_ADDR"
LIBRARY_FLAG="$LIBRARY_FLAG --libraries src/libraries/logic/RepayLogic.sol:RepayLogic:$REPAY_LOGIC_ADDR"
LIBRARY_FLAG="$LIBRARY_FLAG --libraries src/libraries/logic/CloseLoanLogic.sol:CloseLoanLogic:$CLOSE_LOAN_LOGIC_ADDR"
LIBRARY_FLAG="$LIBRARY_FLAG --libraries src/libraries/logic/FlashLoanLogic.sol:FlashLoanLogic:$FLASH_LOAN_LOGIC_ADDR"

FORK=base FOUNDRY_PROFILE=fork-deploy forge script script/deployment/fork/DeployPhase3Fork.s.sol:DeployPhase3Fork \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast --slow --force -v \
    $LIBRARY_FLAG

log "Phase 3a complete."

# ============ Phase 3b: Schedule ============
log ""
log "=========================================="
log "Phase 3b: Schedule timelocked operations"
log "=========================================="

FORK=base FOUNDRY_PROFILE=fork-deploy forge script script/deployment/fork/SchedulePhase3Fork.s.sol:SchedulePhase3Fork \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -v \
    $LIBRARY_FLAG

log "Phase 3b complete."

# ============ Phase 3c: Time advance + Execute ============
log ""
log "=========================================="
log "Phase 3c: Advance time and execute"
log "=========================================="

TIME_ADVANCE=87001
log "Advancing Anvil time by $TIME_ADVANCE seconds..."
cast rpc evm_increaseTime $TIME_ADVANCE --rpc-url "$RPC" > /dev/null
cast rpc evm_mine --rpc-url "$RPC" > /dev/null
log "Time advanced."

FORK=base FOUNDRY_PROFILE=fork-deploy forge script script/deployment/fork/ExecutePhase3Fork.s.sol:ExecutePhase3Fork \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast -v \
    $LIBRARY_FLAG

log "Phase 3c complete."

# ============ Phase 4: Validation ============
log ""
log "=========================================="
log "Phase 4: Post-Deploy Validation"
log "=========================================="

FORK=base FOUNDRY_PROFILE=fork-deploy forge script script/deployment/PostDeployChecks.s.sol:PostDeployChecks \
    --rpc-url "$RPC" --private-key "$PRIVATE_KEY" -v \
    $LIBRARY_FLAG

log "Phase 4 complete."

# ============ Summary ============
log ""
log "=========================================="
log "Fork Deployment Complete!"
log "=========================================="
log ""
log "Chain: Base mainnet fork (chain ID 31337, forked state from Base 8453)"
log "Addresses saved to:"
log "  - loan-provider/deployments.json (key: 31337-fork)"
log "  - lending-pool/deployed-contracts.json (key: localhost)"
log ""
log "Verify with:"
log "  cat loan-provider/deployments.json | jq '.deployments[\"31337-fork\"]'"
