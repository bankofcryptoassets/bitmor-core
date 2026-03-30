#!/bin/bash
set -e

# Bitmor Protocol - Testnet Deployment Orchestrator (Base Sepolia)
# Deploys complete protocol with full mocks to Base Sepolia (chainId 84532)
# Uses cast wallet `bitmor_owner` for signing
# Requires: BASE_SEPOLIA_RPC_URL and DEPLOYER_PRIVATE_KEY in loan-provider/.env or environment

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Load env vars from loan-provider/.env (same pattern as deploy-fork.sh)
if [ -f "$ROOT/loan-provider/.env" ]; then
    set -a
    eval "$(grep -E '^[A-Za-z_][A-Za-z_0-9]*=' "$ROOT/loan-provider/.env" | sed 's/^/export /')"
    set +a
fi

RPC="${BASE_SEPOLIA_RPC_URL:?BASE_SEPOLIA_RPC_URL not set — add to loan-provider/.env}"



log() { echo "[DEPLOY-TESTNET] $1"; }
error() { echo "[ERROR] $1"; exit 1; }

# ============ Preflight Checks ============
log "=== Preflight Checks ==="

cast chain-id --rpc-url "$RPC" > /dev/null 2>&1 || error "Cannot connect to Base Sepolia RPC"
CHAIN_ID=$(cast chain-id --rpc-url "$RPC")
log "Connected to chain (chainId: $CHAIN_ID)"

[ "$CHAIN_ID" = "84532" ] || error "Expected chainId 84532 (Base Sepolia), got $CHAIN_ID"

# Verify bitmor_owner wallet exists
cast wallet list 2>/dev/null | grep -q "bitmor_owner" || error "Cast wallet 'bitmor_owner' not found. Create with: cast wallet import bitmor_owner --interactive"

mkdir -p "$ROOT/loan-provider/deployments"

# ============ Phase 1: loan-provider (consolidated) ============
log ""
log "=========================================="
log "Phase 1: loan-provider (AccessManager, Mock Tokens, Mock Oracles, BTCVault)"
log "=========================================="
cd "$ROOT/loan-provider"

FOUNDRY_PROFILE=testnet forge script script/deployment/testnet/DeployPhase1Testnet.s.sol:DeployPhase1Testnet \
    --rpc-url "$RPC" --account bitmor_owner --sender 0xc617C587122256e940e10FA46d30f610139A818E --broadcast --slow --force -v

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

log "Phase 2 complete."

# ============ Phase 3: loan-provider (deploy + strategies + roles) ============
log ""
log "=========================================="
log "Phase 3: loan-provider (Deploy contracts + Strategies + Roles)"
log "=========================================="
cd "$ROOT/loan-provider"

# Deploy all linked libraries
log "Deploying linked libraries (LoanLogic, RepayLogic, CloseLoanLogic, FlashLoanLogic)..."
FOUNDRY_PROFILE=testnet forge script script/deployment/DeployLibraries.s.sol:DeployLibraries \
    --rpc-url "$RPC" --account bitmor_owner --sender 0xc617C587122256e940e10FA46d30f610139A818E --broadcast --slow --force -v

# Read deployed library addresses from deployments.json
LOAN_LOGIC_ADDR=$(jq -r '.deployments["84532"].networkConfig.loanLogicLib' deployments.json)
REPAY_LOGIC_ADDR=$(jq -r '.deployments["84532"].networkConfig.repayLogicLib' deployments.json)
CLOSE_LOAN_LOGIC_ADDR=$(jq -r '.deployments["84532"].networkConfig.closeLoanLogicLib' deployments.json)
FLASH_LOAN_LOGIC_ADDR=$(jq -r '.deployments["84532"].networkConfig.flashLoanLogicLib' deployments.json)

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

FOUNDRY_PROFILE=testnet forge script script/deployment/testnet/DeployPhase3Testnet.s.sol:DeployPhase3Testnet \
    --rpc-url "$RPC" --account bitmor_owner --sender 0xc617C587122256e940e10FA46d30f610139A818E --broadcast --slow --force -v \
    $LIBRARY_FLAG

log "Phase 3 complete. Contracts deployed, strategies wired, roles granted."

# ============ Phase 4: Post-Deploy Validation ============
log ""
log "=========================================="
log "Phase 4: Post-Deploy Validation"
log "=========================================="

FOUNDRY_PROFILE=testnet forge script script/deployment/PostDeployChecks.s.sol:PostDeployChecks \
    --rpc-url "$RPC" --account bitmor_owner --sender 0xc617C587122256e940e10FA46d30f610139A818E -v \
    $LIBRARY_FLAG

log "Phase 4 complete. All deployment checks passed."

# ============ Summary ============
log ""
log "=========================================="
log "Testnet Deployment Complete! (Base Sepolia)"
log "=========================================="
log ""
log "Addresses saved to:"
log "  - loan-provider/deployments.json (under key '84532')"
log "  - lending-pool/deployed-contracts.json (under key 'sepolia')"
log ""
log "Verify with:"
log "  cat loan-provider/deployments.json | jq '.deployments[\"84532\"]'"
