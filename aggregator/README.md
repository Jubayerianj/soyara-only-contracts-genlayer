# AGGFlow DEX Aggregator Contracts

Foundry-based smart contracts for the AGGFlow routing engine and settlement entrypoint.

## Architecture

- **`AGGFlowRouter`**: Core contract handling hop routing and swap executions across liquidity pools.
- **`AGGFlowEntrypoint`**: High-level execution entrypoint managing user approvals, fees, and multi-pool paths.

## Build & Test

```bash
# Build
forge build

# Test
forge test

# Deploy
forge script script/deployAll.sol:deployAll --rpc-url <RPC_URL> --broadcast
```
