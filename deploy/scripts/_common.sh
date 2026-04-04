#!/bin/bash
# Shared functions for Bitmor deploy scripts
# Source this file: source "$(dirname "$0")/_common.sh"

: "${DEPLOY_PREFIX:=DEPLOY}"

log() { echo "[$DEPLOY_PREFIX] $1"; }
error() { echo "[ERROR] $1"; exit 1; }

load_env() {
    local env_file="$1"
    if [ -f "$env_file" ]; then
        set -a
        eval "$(grep -E '^[A-Za-z_][A-Za-z_0-9]*=' "$env_file")"
        set +a
    fi
}

# Verify RPC connectivity and chain ID
# Usage: check_rpc <rpc_url> <expected_chain_id> <error_hint>
# The hint is REQUIRED — callers must provide a context-appropriate remediation message.
check_rpc() {
    local rpc="$1" expected_chain="$2" hint="$3"
    CHAIN_ID=$(cast chain-id --rpc-url "$rpc" 2>/dev/null) || error "Cannot connect to RPC at $rpc. $hint"
    log "Connected to chain (chainId: $CHAIN_ID)"
    [ "$CHAIN_ID" = "$expected_chain" ] || error "Expected chainId $expected_chain, got $CHAIN_ID"
}

# Run bitmor-deploy CLI (TS tool for registry JSON operations)
bitmor_deploy() {
    npx --prefix "$ROOT/deploy/tools" tsx "$ROOT/deploy/tools/src/cli.ts" "$@"
}
