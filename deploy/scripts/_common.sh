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

read_library_addresses() {
    local chain_key="$1" json_file="deployments.json"
    local loan_logic repay_logic close_loan_logic flash_loan_logic
    loan_logic=$(jq -r ".deployments[\"$chain_key\"].networkConfig.loanLogicLib" "$json_file")
    repay_logic=$(jq -r ".deployments[\"$chain_key\"].networkConfig.repayLogicLib" "$json_file")
    close_loan_logic=$(jq -r ".deployments[\"$chain_key\"].networkConfig.closeLoanLogicLib" "$json_file")
    flash_loan_logic=$(jq -r ".deployments[\"$chain_key\"].networkConfig.flashLoanLogicLib" "$json_file")
    [ -n "$loan_logic" ] && [ "$loan_logic" != "null" ] || error "Failed to read LoanLogic address"
    [ -n "$repay_logic" ] && [ "$repay_logic" != "null" ] || error "Failed to read RepayLogic address"
    [ -n "$close_loan_logic" ] && [ "$close_loan_logic" != "null" ] || error "Failed to read CloseLoanLogic address"
    [ -n "$flash_loan_logic" ] && [ "$flash_loan_logic" != "null" ] || error "Failed to read FlashLoanLogic address"
    log "Libraries:"
    log "  LoanLogic:      $loan_logic"
    log "  RepayLogic:     $repay_logic"
    log "  CloseLoanLogic: $close_loan_logic"
    log "  FlashLoanLogic: $flash_loan_logic"
    LIBRARY_FLAG="--libraries src/libraries/logic/LoanLogic.sol:LoanLogic:$loan_logic"
    LIBRARY_FLAG="$LIBRARY_FLAG --libraries src/libraries/logic/RepayLogic.sol:RepayLogic:$repay_logic"
    LIBRARY_FLAG="$LIBRARY_FLAG --libraries src/libraries/logic/CloseLoanLogic.sol:CloseLoanLogic:$close_loan_logic"
    LIBRARY_FLAG="$LIBRARY_FLAG --libraries src/libraries/logic/FlashLoanLogic.sol:FlashLoanLogic:$flash_loan_logic"
    export LIBRARY_FLAG
}
