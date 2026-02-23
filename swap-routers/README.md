# swap-routers

Uniswap V4 swap adapter for the Bitmor BTC-collateralized loan system.

## Overview

This module provides the swap layer used by the Bitmor loan system when converting between USDC and cbBTC. During loan initialization, `loan-provider` calls this adapter to swap flash-loaned USDC into cbBTC collateral. The adapter wraps Uniswap V4's Universal Router and exposes a simple interface for exact-input and exact-output swaps, with quoting via the V4 Quoter.

Pool configuration (fee tier, tick spacing, hooks address) is fixed at deployment time as immutables, targeting the USDC/cbBTC pool on Base.

## Architecture

| Contract | Path | Description |
|---|---|---|
| `UniswapV4Swapper` | `src/uniswap/UniswapV4Swapper.sol` | Main swap adapter. Wraps Universal Router for V4 swaps and IV4Quoter for pre-swap quotes. |
| `ISwapAdaptor` | `src/interface/ISwapAdaptor.sol` | Interface consumed by `loan-provider` (`UniswapV4SwapAdapterWrapper`). |

### Key functions

- `swapExactInput` — swap a fixed amount of `tokenIn` for at least `minAmountOut` of `tokenOut`.
- `swapExactOutput` — spend at most `maxAmountIn` of `tokenIn` to receive exactly `exactAmountOut` of `tokenOut`; unused input is refunded.
- `getMaxTokenInAmount` — quote the maximum input needed for an exact output (uses IV4Quoter).
- `getMinTokenOutAmount` — quote the minimum output for an exact input (uses IV4Quoter).

### Constructor parameters

```solidity
constructor(
    address _universalRouter,  // Uniswap Universal Router
    address _quoter,           // Uniswap V4 Quoter
    uint24  _fee,              // Pool fee tier (default: 3000 = 0.3%)
    int24   _tickSpacing,      // Pool tick spacing (default: 60)
    address _hooks             // Pool hooks (default: address(0))
)
```

Deployed addresses for Universal Router and V4 Quoter are resolved by `script/HelperConfig.s.sol` based on chain ID. Mainnet and Base Sepolia addresses are hardcoded; local addresses are read from `deployments.json`.

## Environment

Create a `.env` file in this directory:

```
BASE_RPC_URL=
BASE_SEPOLIA_RPC_URL=
ETHERSCAN_KEY=
```

These map to the `[rpc_endpoints]` entries in `foundry.toml` (`base` and `base_sepolia`). The deploy scripts also require a `deployer` cast wallet configured via `cast wallet import`.

## Build & Test

```bash
# Install dependencies (v4-core, v4-periphery, universal-router)
make install

# Compile
make build

# Unit tests (no fork required)
make test

# Fork tests against Base Mainnet
make test-fork

# Fork tests against Base Sepolia
make test-fork-sepolia

# Coverage report
make coverage
```

## Deploy

Deployment uses `script/deployment/DeployUniswapV4Swapper.s.sol`, which reads addresses from `HelperConfig` and writes the deployed address to `deployments.json` under the key `uniswapV4Swapper`.

```bash
# Deploy to Base Sepolia (broadcasts + verifies on Basescan)
make deploy-sepolia

# Deploy to Base Mainnet (broadcasts + verifies on Basescan)
make deploy-mainnet

# Deploy to local Anvil (no verification)
make deploy-local
```

All deploy targets require the `deployer` cast wallet and the corresponding RPC environment variable to be set.
