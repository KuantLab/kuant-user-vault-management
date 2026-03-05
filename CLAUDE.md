# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Solidity smart contract project for futures margin pool management with role-based access control. Built with Hardhat, uses Solidity 0.6.12, and targets BSC mainnet/testnet.

## Commands

```bash
# Install dependencies
pnpm install

# Compile contracts
pnpm compile

# Run tests
pnpm test

# Run a single test file
npx hardhat test test/FuturesMarginPoolClassics.test.js

# Run tests with gas reporting
REPORT_GAS=true npx hardhat test

# Clean build artifacts
pnpm clean

# Start local Hardhat node
npx hardhat node

# Deploy to local
npx hardhat ignition deploy ./ignition/modules/FuturesMarginPool.js --network localhost --parameters ignition/parameters.json

# Deploy to BSC testnet
npx hardhat ignition deploy ./ignition/modules/FuturesMarginPool.js --network bscTestnet --parameters ignition/parameters-bscTestnet.json

# Deploy to BSC mainnet
npx hardhat ignition deploy ./ignition/modules/FuturesMarginPool.js --network bsc --parameters ignition/parameters-bsc.json
```

## Architecture

### Smart Contract: FuturesMarginPoolClassics

Main contract (`contracts/FuturesMarginPoolClassics.sol`) - a margin pool for futures trading with ERC20 token deposits/withdrawals.

**Role System:**
- `admin`: Full configuration access, can add/remove operators, pause/unpause, modify addresses
- `withdrawAdmin`: Processes user withdrawals via `withdraw()` and `withdrawWithItem()`
- `operator`: Can manage invest items and call `withdrawAdminFun()` to transfer funds to vaults

**Key Functions:**
- `deposit(amount, hash)`: Users deposit tokens (requires ERC20 approval first)
- `withdraw(account, amount, fee, hash)`: WithdrawAdmin processes withdrawal with explicit fee
- `withdrawWithItem(account, amount, itemId, hash)`: WithdrawAdmin processes withdrawal using invest item's commission rate
- `withdrawAdminFun(amount)`: Admin/Operator transfers pool funds to vaults address
- `createInvestItem(commissionBps)`: Create investment product with commission rate (basis points, max 1000 = 10%)

**Security Features:**
- ReentrancyGuard on deposit/withdraw functions
- Pausable mechanism for emergency stops
- Two-step admin transfer (`transferAdmin` + `acceptAdmin`)
- Fee cap at 10% (MAX_FEE_BPS = 1000)
- Hash-based deduplication for deposits and withdrawals
- Balance validation: withdrawals validated against user's available balance (inAmount - outAmount)

**State Tracking:**
- `UserAsset` struct tracks `inAmount` (total deposited) and `outAmount` (total withdrawn) per user
- `investItems` mapping stores invest item configs (exists, active, commissionBps)

### Dependencies

- **OpenZeppelin 3.4.1**: SafeERC20, SafeMath, ReentrancyGuard, Pausable (legacy version for Solidity 0.6.12)
- **LayerZero v2, Stargate v2, Aave v3**: Available in dependencies for future cross-chain features

### Network Configuration

Networks in `hardhat.config.js`:
- `hardhat`: Local development (chainId 1337)
- `bsc`: BSC mainnet (requires BSC_RPC_URL)
- `bscTestnet`: BSC testnet (requires BSC_TESTNET_RPC_URL)

Environment variables: `PRIVATE_KEY`, `BSC_RPC_URL`, `BSC_TESTNET_RPC_URL`

### Deployment Parameters

Parameters files in `ignition/` configure constructor args:
- `withdrawAdmin`: Address authorized to process withdrawals
- `admin`: Address with administrative privileges
- `vaults`: Address to receive admin withdrawals
- `feeAddress`: Address to receive withdrawal fees/commissions
- `marginCoinAddress`: ERC20 token address for margin deposits
