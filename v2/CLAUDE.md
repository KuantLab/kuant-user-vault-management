# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Solidity smart contract project for user fund custody (UserVault) built with Foundry. The contract manages ERC20 token deposits/withdrawals with multi-signature owner control, operator permissions, and anti-replay mechanisms.

**Core Architecture:**
- **UserVault.sol**: Main custody contract with internal balance ledger for users
- **Multi-signature system**: N-of-M proposal-based governance for critical operations
- **Operator system**: Authorized addresses can deposit/transfer on behalf of users
- **Anti-replay protection**: Uses unique IDs (depositId, opId) to prevent duplicate operations

## Development Commands

### Building and Testing
```bash
# Clean build artifacts
forge clean

# Compile contracts
forge build

# Run all tests
forge test

# Run tests with verbosity
forge test -vv

# Run specific test
forge test --match-test testDeposit -vv

# Run tests via script
./run_tests.sh

# Format code
forge fmt
```

### Deployment
```bash
# Deploy to local Anvil testnet
anvil  # Start local node first
forge script script/DeployUserVaultSimple.s.sol:DeployUserVaultSimple --rpc-url http://localhost:8545 --private-key <key> --broadcast

# Deploy to BSC Testnet
./deploy_bsc.sh
# OR
forge script script/DeployBSC.s.sol:DeployBSC --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 --private-key <key> --broadcast -vv

# Deploy to mainnet/other networks
forge script script/DeployUserVault.s.sol:DeployScript --rpc-url <rpc_url> --private-key <key> --broadcast
```

### Interaction Scripts
The `scripts/` directory contains bash scripts for contract interactions:
- `deposit_simple.sh` / `deposit.sh` - User deposits
- `withdraw_simple.sh` / `withdraw.sh` - User withdrawals
- `operator_deposit_simple.sh` / `operator_deposit.sh` - Operator deposits for users
- `operator_transfer_simple.sh` / `operator_transfer.sh` - Operator transfers user funds
- `add_operator_simple.sh` / `add_operator.sh` - Multi-sig add operator
- `multisig_example.sh` - Complete multi-sig workflow example
- `check_and_execute_proposal.sh` - Check and execute proposals
- `execute_proposal.sh` - Execute specific proposal

Each script has a "simple" version (standalone) and a full version (with additional checks).

### ABI Generation
```bash
# Generate ABI files
./generate_abi.sh

# Extract specific contract ABI
forge inspect UserVault abi > abis/UserVault.json
```

## Key Contract Patterns

### Multi-Signature Proposal Flow
All privileged operations (add/remove operator, pause/unpause) require multi-sig approval:

1. **Submit**: Any owner calls `submitProposal(ProposalType, bytes data)` - auto-confirms for submitter
2. **Confirm**: Other owners call `confirmProposal(uint256 proposalId)`
3. **Execute**: When confirmations reach `requiredConfirmations`, call `executeProposal(uint256 proposalId)`

**Proposal Types:**
- `AddOperator` - data: `abi.encode(address operator)`
- `RemoveOperator` - data: `abi.encode(address operator)`
- `Pause` - data: `abi.encode()` (empty)
- `Unpause` - data: `abi.encode()` (empty)

### Anti-Replay Mechanisms
The contract uses two separate ID tracking systems:

1. **User deposits**: `usedDepositIds` mapping prevents duplicate `deposit()` calls with same `depositId`
2. **Operator operations**: `usedOpIds` mapping prevents duplicate `operatorDeposit()` and `operatorTransfer()` calls

Both use `bytes32` IDs - typically generated as `keccak256(abi.encodePacked(timestamp, random))` or similar.

### Balance Consistency Model
- Contract maintains internal `balances` mapping for each user
- Actual ERC20 token balance held by contract must always equal sum of all user balances
- All operations follow Checks → Effects → Interactions pattern
- `withdraw()` uses `nonReentrant` modifier for reentrancy protection

### Operator Permissions
Operators can:
- **operatorDeposit(user, amount, opId)**: Credit tokens to user's balance (requires operator holds tokens)
- **operatorTransfer(user, to, amount, opId)**: Transfer user's balance to external address

Operators are managed via multi-sig proposals only.

## Testing Architecture

The test suite (test/UserVault.t.sol) uses:
- **MockERC20**: Test token with 6 decimals (simulates USDC)
- **Foundry Test**: Standard test framework with `setUp()` pattern
- **Test accounts**: owner1/2/3, operator1/2, user1/2

Tests cover:
- User deposit/withdraw flows
- Operator deposit/transfer operations
- Multi-sig proposal lifecycle
- Pause/unpause functionality
- Edge cases and revert scenarios
- Reentrancy protection

## Important Files

**Contracts:**
- `src/UserVault.sol` - Main contract (16KB)
- `src/Counter.sol` - Foundry template example (can be ignored/deleted)

**Tests:**
- `test/UserVault.t.sol` - Comprehensive test suite
- `test/MockERC20.sol` - ERC20 test double

**Deployment:**
- `script/DeployUserVaultSimple.s.sol` - Simplified deployment (hardcoded params)
- `script/DeployUserVault.s.sol` - Full deployment with env var config
- `script/DeployBSC.s.sol` - BSC Testnet specific deployment
- `deploy_bsc.sh` - BSC deployment wrapper script

**Documentation:**
- `README.md` - Main documentation (Chinese)
- `FLOWCHARTS.md` - Detailed mermaid flow diagrams for all operations
- `DEPLOYMENT.md` - Deployment guide with examples
- `BSC_DEPLOYMENT.md` - BSC-specific deployment instructions
- `TEST_REPORT.md` - Test coverage report
- `MULTISIG_GUIDE.md` - Multi-signature usage guide
- `scripts/*_README.md` - Individual script usage guides

## Configuration Notes

**Foundry Config (foundry.toml):**
```toml
src = "src"
out = "out"
libs = ["lib"]
```

**Default Test Setup:**
- Token: MockERC20 with 6 decimals (USDC-like)
- Multi-sig: 3 owners, 2 required confirmations
- Initial supply: 1,000,000 tokens per test account

## Security Considerations

When modifying the contract:
1. **Never skip anti-replay checks** - Both `usedDepositIds` and `usedOpIds` must be checked before marking as used
2. **Maintain balance consistency** - Internal `balances` sum must equal contract's token balance
3. **Preserve multi-sig protection** - All operator/pause operations must go through proposals
4. **Follow CEI pattern** - Checks → Effects → Interactions in all functions
5. **Protect against reentrancy** - Keep `nonReentrant` on `withdraw()` and any external calls
6. **Solidity ^0.8.x** - Relies on built-in overflow protection

## Common Operations

**Query contract state:**
```bash
# Check user balance
cast call <vault_addr> "balances(address)(uint256)" <user_addr> --rpc-url <rpc>

# Check if operator
cast call <vault_addr> "operators(address)(bool)" <operator_addr> --rpc-url <rpc>

# Check if depositId used
cast call <vault_addr> "usedDepositIds(bytes32)(bool)" <deposit_id> --rpc-url <rpc>

# Get contract token balance
cast call <vault_addr> "getContractBalance()(uint256)" --rpc-url <rpc>
```

**Generate unique IDs:**
```bash
# Generate depositId or opId
UNIQUE_ID=$(cast keccak256 $(echo -n "$(date +%s)$RANDOM" | xxd -p))
```

## Token Decimal Handling

Scripts assume 18 decimals by default. Common token decimals:
- **18 decimals** (ETH, most ERC20): amount = value * 10^18
- **6 decimals** (USDC, USDT): amount = value * 10^6
- **8 decimals** (WBTC): amount = value * 10^8

Check token decimals: `cast call <token_addr> "decimals()(uint8)" --rpc-url <rpc>`
