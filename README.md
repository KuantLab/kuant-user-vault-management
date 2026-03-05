# Kuant-User-Vault-Management

A Solidity smart contract project for futures margin pool management with role-based access control, invest item management, configurable commission rates, and per-deposit time locks.

## Core Features

- **Margin Pool Management**: Secure deposit and withdrawal of ERC20 tokens for futures trading
- **Role-Based Access Control**: Admin, Operator, and WithdrawAdmin roles with distinct permissions
- **Operator System**: Operators can manage invest items and perform admin withdrawals
- **Invest Items**: Configurable investment products with individual commission rates and lock durations
- **Per-Deposit Time Lock**: Each deposit has its own lock period (24-240 hours), preventing early withdrawal
- **Per-Item Commission**: Each invest item has its own commission rate (in basis points)
- **Fee Management**: Configurable fee collection on withdrawals (max 10%)
- **Partial Withdrawals**: Support for withdrawing portions of a deposit after unlock
- **Withdrawal Deduplication**: Hash-based tracking to prevent duplicate withdrawals
- **Pause Mechanism**: Emergency pause functionality for deposits and withdrawals
- **Two-Step Admin Transfer**: Secure admin ownership transfer with acceptance requirement
- **Reentrancy Protection**: Built-in security using OpenZeppelin's ReentrancyGuard
- **Multi-Sig Compatible**: Admin can be a multi-signature wallet (e.g., Gnosis Safe)

## Architecture

### System Overview

```mermaid
graph TB
    subgraph Users
        U[User]
    end

    subgraph Roles
        A[Admin / Multi-Sig]
        OP[Operator]
        WAdmin[Withdraw Admin]
    end

    subgraph FuturesMarginPoolClassics
        D[Deposit with Lock]
        W[Withdraw from Deposit]
        WWI[WithdrawWithItem]
        WA[Withdraw to Vaults]
        IM[Invest Item Management]
    end

    subgraph External
        V[Vaults]
        F[Fee Address]
        MC[Margin Coin ERC20]
    end

    U -->|deposit + lock| D
    WAdmin -->|withdraw after unlock| W
    WAdmin -->|withdrawWithItem| WWI
    A -->|withdrawAdminFun| WA
    OP -->|withdrawAdminFun| WA

    A -->|add/remove| OP
    A -->|manage| IM
    OP -->|manage| IM

    D -->|transferFrom| MC
    W -->|transfer user amount| MC
    WWI -->|transfer user amount| MC
    WA -->|transfer| V

    W -->|fee| F
    WWI -->|commission| F

    A -.->|configure| FuturesMarginPoolClassics
```

### Role Hierarchy

```mermaid
graph TD
    A[Admin] -->|can add/remove| OP[Operator]
    A -->|can set| WA[Withdraw Admin]
    A -->|full access| ALL[All Functions]

    OP -->|can manage| II[Invest Items]
    OP -->|can call| WAF[withdrawAdminFun]

    WA -->|can call| W[withdraw]
    WA -->|can call| WWI[withdrawWithItem]

    U[User] -->|can call| D[deposit]
    U -->|can view| V[View Functions]

    style A fill:#ff6b6b
    style OP fill:#4ecdc4
    style WA fill:#45b7d1
    style U fill:#96ceb4
```

### Deposit Flow with Time Lock

```mermaid
sequenceDiagram
    participant User
    participant Pool as FuturesMarginPoolClassics
    participant Token as ERC20 Token

    User->>Token: approve(pool, amount)
    User->>Pool: deposit(amount, investItemId, lockDuration, depositHash)

    Pool->>Pool: Check amount > 0
    Pool->>Pool: Check depositHash not used
    Pool->>Pool: Validate invest item exists & active
    Pool->>Pool: Validate lockDuration >= item.minLockDuration
    Pool->>Pool: Validate lockDuration >= 24 hours
    Pool->>Pool: Validate lockDuration <= 240 hours

    Pool->>Pool: Mark depositHash as used
    Pool->>Pool: Calculate unlockTime = now + lockDuration
    Pool->>Pool: Store DepositRecord

    Pool->>Token: transferFrom(user, pool, amount)
    Pool->>Pool: Update userAssetInfo.inAmount

    Pool-->>User: emit FuturesMarginDeposit(hash, user, amount, itemId, unlockTime)
```

### Withdrawal Flows

```mermaid
sequenceDiagram
    participant WAdmin as Withdraw Admin
    participant Pool as FuturesMarginPoolClassics
    participant Token as ERC20 Token
    participant User
    participant FeeAddr as Fee Address

    Note over WAdmin,FeeAddr: Standard Withdrawal (with explicit fee)
    WAdmin->>Pool: withdraw(account, amount, fee, depositHash, withdrawHash)
    Pool->>Pool: Validate deposit exists & belongs to account
    Pool->>Pool: Check block.timestamp >= unlockTime
    Pool->>Pool: Check amount <= deposit.remainingAmount
    Pool->>Pool: Check fee <= 10% of amount
    Pool->>Pool: Mark withdrawHash as processed
    Pool->>Pool: Update deposit.remainingAmount
    Pool->>Pool: Update userAssetInfo.outAmount
    Pool->>Token: transfer(user, amount - fee)
    Pool->>Token: transfer(feeAddress, fee)
    Pool-->>User: emit FuturesMarginWithdraw

    Note over WAdmin,FeeAddr: Withdrawal with Invest Item (auto-calculated fee)
    WAdmin->>Pool: withdrawWithItem(account, amount, depositHash, withdrawHash)
    Pool->>Pool: Validate deposit & time lock
    Pool->>Pool: Get investItemId from deposit record
    Pool->>Pool: Calculate fee = amount * item.commissionBps / 10000
    Pool->>Pool: Mark withdrawHash as processed
    Pool->>Pool: Update deposit.remainingAmount
    Pool->>Pool: Update userAssetInfo.outAmount
    Pool->>Token: transfer(user, amount - fee)
    Pool->>Token: transfer(feeAddress, fee)
    Pool-->>User: emit FuturesMarginWithdraw
```

### Time Lock Mechanism

```mermaid
sequenceDiagram
    participant User
    participant Pool
    participant WAdmin as Withdraw Admin

    Note over User,WAdmin: Day 0: User deposits with 48-hour lock
    User->>Pool: deposit(1000, itemId, 48 hours, hash1)
    Pool->>Pool: Store unlockTime = now + 48 hours

    Note over User,WAdmin: Day 1: Early withdrawal attempt (BLOCKED)
    WAdmin->>Pool: withdraw(user, 500, fee, hash1, wHash1)
    Pool-->>WAdmin: REVERT: FuturesMarginPool/DEPOSIT_LOCKED

    Note over User,WAdmin: Day 2+: After unlock time
    WAdmin->>Pool: withdraw(user, 500, fee, hash1, wHash1)
    Pool->>Pool: Check timestamp >= unlockTime ✓
    Pool-->>User: Transfer 500 - fee

    Note over User,WAdmin: Partial withdrawal: 500 remaining
    WAdmin->>Pool: withdraw(user, 500, fee, hash1, wHash2)
    Pool-->>User: Transfer remaining 500 - fee
```

### Invest Item Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Created: createInvestItem(commissionBps, minLockDuration)
    Created --> Active: Initial state
    Active --> Inactive: setInvestItemStatus(id, false)
    Inactive --> Active: setInvestItemStatus(id, true)

    Active --> Active: setInvestItemCommission(id, newBps)
    Active --> Active: setInvestItemLockDuration(id, newDuration)
    Inactive --> Inactive: setInvestItemCommission(id, newBps)
    Inactive --> Inactive: setInvestItemLockDuration(id, newDuration)

    note right of Active: Can be used for deposits & withdrawals
    note right of Inactive: Cannot be used for new deposits
```

### Smart Contract Structure

```mermaid
classDiagram
    class FuturesMarginPoolClassics {
        +uint256 MAX_FEE_BPS = 1000
        +uint256 BPS_DENOMINATOR = 10000
        +uint256 MIN_LOCK_DURATION = 24 hours
        +uint256 MAX_LOCK_DURATION = 240 hours
        +address marginCoinAddress
        +address pendingAdmin
        +uint256 investItemCount
        -address withdrawAdmin
        -address vaults
        -address feeAddress
        -address admin
        -mapping~address,bool~ operators
        -mapping~address,UserAsset~ userAssetInfo
        -mapping~bytes32,uint256~ withdrawFlag
        -mapping~bytes32,bool~ depositFlag
        -mapping~uint256,InvestItem~ investItems
        -mapping~bytes32,DepositRecord~ depositRecords

        +deposit(uint256, uint256, uint256, bytes32)
        +withdraw(address, uint256, uint256, bytes32, bytes32)
        +withdrawWithItem(address, uint256, bytes32, bytes32)
        +withdrawAdminFun(uint256)
        +addOperator(address)
        +removeOperator(address)
        +createInvestItem(uint256, uint256) uint256
        +setInvestItemStatus(uint256, bool)
        +setInvestItemCommission(uint256, uint256)
        +setInvestItemLockDuration(uint256, uint256)
        +pause()
        +unpause()
        +transferAdmin(address)
        +acceptAdmin()
        +cancelAdminTransfer()
        +modifyMarginAddress(address)
        +modifyWithdrawAdmin(address)
        +modifyVaultsAddress(address)
        +modifyFeeAddress(address)
        +isOperator(address) bool
        +getInvestItem(uint256) tuple
        +getDepositRecord(bytes32) tuple
        +getUserAddressBalance() tuple
        +getAvailableBalance(address) uint256
        +getWithdrawStatus(bytes32) uint256
        +getDepositStatus(bytes32) bool
        +adminAddress() address
        +vaultsAddress() address
        +getFeeAddress() address
        +withdrawAdminAddress() address
        +getMaxFeeBps() uint256
    }

    class UserAsset {
        +uint256 inAmount
        +uint256 outAmount
    }

    class InvestItem {
        +bool exists
        +bool active
        +uint256 commissionBps
        +uint256 minLockDuration
    }

    class DepositRecord {
        +address user
        +uint256 amount
        +uint256 investItemId
        +uint256 unlockTime
        +uint256 remainingAmount
    }

    class ReentrancyGuard {
        <<OpenZeppelin>>
    }

    class Pausable {
        <<OpenZeppelin>>
    }

    FuturesMarginPoolClassics --|> ReentrancyGuard
    FuturesMarginPoolClassics --|> Pausable
    FuturesMarginPoolClassics *-- UserAsset
    FuturesMarginPoolClassics *-- InvestItem
    FuturesMarginPoolClassics *-- DepositRecord
```

## Access Control Matrix

| Function | Admin | Operator | WithdrawAdmin | User |
|----------|:-----:|:--------:|:-------------:|:----:|
| `deposit` | - | - | - | Yes |
| `withdraw` | - | - | Yes | - |
| `withdrawWithItem` | - | - | Yes | - |
| `withdrawAdminFun` | Yes | Yes | - | - |
| `addOperator` | Yes | - | - | - |
| `removeOperator` | Yes | - | - | - |
| `createInvestItem` | Yes | Yes | - | - |
| `setInvestItemStatus` | Yes | Yes | - | - |
| `setInvestItemCommission` | Yes | Yes | - | - |
| `setInvestItemLockDuration` | Yes | Yes | - | - |
| `pause/unpause` | Yes | - | - | - |
| `transferAdmin` | Yes | - | - | - |
| `modifyWithdrawAdmin` | Yes | - | - | - |
| `modifyVaultsAddress` | Yes | - | - | - |
| `modifyFeeAddress` | Yes | - | - | - |
| `modifyMarginAddress` | Yes | - | - | - |

## Installation

```bash
# Clone the repository
git clone <repository-url>
cd kuant-user-vault-management

# Install dependencies
pnpm install
```

## Configuration

Create a `.env` file in the project root:

```env
PRIVATE_KEY=your_private_key_here
BSC_RPC_URL=https://bsc-dataseed.binance.org/
BSC_TESTNET_RPC_URL=https://data-seed-prebsc-1-s1.binance.org:8545/
```

## Development

```bash
# Compile contracts
pnpm compile

# Run tests
pnpm test

# Run tests with gas reporting
REPORT_GAS=true npx hardhat test

# Clean build artifacts
pnpm clean

# Start local Hardhat node
npx hardhat node
```

## Usage

### Create Invest Item (Required First)

```javascript
// Admin or operator creates invest item with commission rate and minimum lock duration
// 5% commission, 24-hour minimum lock
const tx = await pool.connect(admin).createInvestItem(500, 86400);
const itemId = 0; // First item

// Get invest item details
const [exists, active, commissionBps, minLockDuration] = await pool.getInvestItem(itemId);
```

### Deposit Tokens with Time Lock

```javascript
// User approves and deposits tokens with a lock period
await token.approve(poolAddress, depositAmount);

// Deposit with 48-hour lock (must be >= invest item's minLockDuration)
const lockDuration = 48 * 60 * 60; // 48 hours in seconds
await pool.deposit(
  depositAmount,
  investItemId,
  lockDuration,
  depositHash
);

// Get deposit record details
const [user, amount, itemId, unlockTime, remainingAmount] = await pool.getDepositRecord(depositHash);
```

### Withdraw Tokens (After Unlock)

```javascript
// WithdrawAdmin processes withdrawal with explicit fee
// Only works after deposit.unlockTime has passed
await pool.connect(withdrawAdmin).withdraw(
  userAddress,
  withdrawAmount,
  feeAmount,      // Must be <= 10% of withdrawAmount
  depositHash,    // Reference to the original deposit
  withdrawHash    // Unique hash for this withdrawal
);
```

### Withdraw with Invest Item Commission

```javascript
// WithdrawAdmin processes withdrawal using invest item's commission rate
// Fee is automatically calculated from the deposit's invest item
await pool.connect(withdrawAdmin).withdrawWithItem(
  userAddress,
  withdrawAmount,
  depositHash,    // Reference to the original deposit (invest item is read from here)
  withdrawHash    // Unique hash for this withdrawal
);
// Fee is automatically calculated: withdrawAmount * item.commissionBps / 10000
```

### Partial Withdrawals

```javascript
// Deposit 1000 tokens with 24-hour lock
await pool.deposit(parseEther("1000"), itemId, 86400, depositHash1);

// After unlock, withdraw 400 tokens
await pool.connect(withdrawAdmin).withdraw(
  userAddress,
  parseEther("400"),
  feeAmount,
  depositHash1,
  withdrawHash1
);

// Later, withdraw remaining 600 tokens
await pool.connect(withdrawAdmin).withdraw(
  userAddress,
  parseEther("600"),
  feeAmount,
  depositHash1,
  withdrawHash2  // Different withdraw hash
);
```

### Manage Operators

```javascript
// Admin adds operator
await pool.connect(admin).addOperator(operatorAddress);

// Admin removes operator
await pool.connect(admin).removeOperator(operatorAddress);

// Check if address is operator
const isOp = await pool.isOperator(operatorAddress);
```

### Manage Invest Items

```javascript
// Create invest item with 3% commission and 48-hour minimum lock
await pool.connect(admin).createInvestItem(300, 172800);

// Deactivate invest item
await pool.connect(operator).setInvestItemStatus(itemId, false);

// Change commission rate to 2%
await pool.connect(operator).setInvestItemCommission(itemId, 200);

// Change minimum lock duration to 72 hours
await pool.connect(operator).setInvestItemLockDuration(itemId, 259200);

// Get invest item details
const [exists, active, commissionBps, minLockDuration] = await pool.getInvestItem(itemId);
```

### Admin Functions

```javascript
// Transfer funds to vaults (admin or operator)
await pool.connect(admin).withdrawAdminFun(amount);

// Pause contract
await pool.connect(admin).pause();

// Unpause contract
await pool.connect(admin).unpause();

// Two-step admin transfer
await pool.connect(admin).transferAdmin(newAdminAddress);
await pool.connect(newAdmin).acceptAdmin();
```

## Deployment

### Configuration

1. Copy the example parameters file and configure your addresses:

```bash
# For local development
cp ignition/parameters.json.example ignition/parameters.json

# For BSC Testnet
cp ignition/parameters-bscTestnet.json.example ignition/parameters-bscTestnet.json

# For BSC Mainnet
cp ignition/parameters-bsc.json.example ignition/parameters-bsc.json
```

2. Edit the parameters file with your actual addresses:

```json
{
  "FuturesMarginPoolModule": {
    "withdrawAdmin": "0x...",
    "admin": "0x...",
    "vaults": "0x...",
    "feeAddress": "0x...",
    "marginCoinAddress": "0x..."
  }
}
```

**Note**: The `admin` address can be a multi-signature wallet (e.g., Gnosis Safe with 5 validators) for enhanced security.

### Local Development

```bash
# Start local node
npx hardhat node

# Deploy to local network (in another terminal)
npx hardhat ignition deploy ./ignition/modules/FuturesMarginPool.js --network localhost --parameters ignition/parameters.json
```

### BSC Testnet

```bash
npx hardhat ignition deploy ./ignition/modules/FuturesMarginPool.js --network bscTestnet --parameters ignition/parameters-bscTestnet.json
```

### BSC Mainnet

```bash
npx hardhat ignition deploy ./ignition/modules/FuturesMarginPool.js --network bsc --parameters ignition/parameters-bsc.json
```

### Constructor Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `_withdrawAdmin` | address | Address authorized to process withdrawals |
| `_admin` | address | Address with administrative privileges (can be multi-sig) |
| `_vaults` | address | Address to receive admin withdrawals |
| `_feeAddress` | address | Address to receive withdrawal fees/commissions |
| `_marginCoinAddress` | address | ERC20 token address for margin deposits |

### Post-Deployment Setup

After deployment, you must create invest items before users can deposit:

1. **Add Operators** (optional):
```javascript
await pool.addOperator(operatorAddress);
```

2. **Create Invest Items** (required):
```javascript
// Create items with different commission rates and lock durations
await pool.createInvestItem(100, 86400);   // 1% commission, 24-hour lock
await pool.createInvestItem(300, 172800);  // 3% commission, 48-hour lock
await pool.createInvestItem(500, 604800);  // 5% commission, 7-day lock
```

### Contract Verification

Contracts are automatically verified on Sourcify. For manual verification on BscScan:

```bash
npx hardhat verify --network bsc <DEPLOYED_CONTRACT_ADDRESS> \
  <WITHDRAW_ADMIN> <ADMIN> <VAULTS> <FEE_ADDRESS> <MARGIN_COIN_ADDRESS>
```

## Networks

| Network | Chain ID | Description |
|---------|----------|-------------|
| hardhat | 1337 | Local development |
| bscTestnet | 97 | BSC Testnet |
| bsc | 56 | BSC Mainnet |

## Security Features

- **Reentrancy Guard**: All state-changing functions protected
- **Pause Mechanism**: Emergency stop for deposits and withdrawals
- **Time Lock**: Per-deposit lock periods prevent early withdrawal (24-240 hours)
- **Balance Validation**: Withdrawals validated against deposit's remaining amount
- **Fee Cap**: Maximum fee limited to 10% (1000 basis points)
- **Two-Step Admin Transfer**: Prevents accidental admin loss
- **Hash Deduplication**: Prevents duplicate deposits and withdrawals
- **Access Control**: Role-based permissions for all sensitive operations
- **Multi-Sig Support**: Admin can be a multi-signature wallet

## Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `MAX_FEE_BPS` | 1000 | Maximum fee (10%) |
| `BPS_DENOMINATOR` | 10000 | Basis points denominator (100%) |
| `MIN_LOCK_DURATION` | 86400 | Minimum lock period (24 hours) |
| `MAX_LOCK_DURATION` | 864000 | Maximum lock period (240 hours) |

## Gas Costs (Approximate)

| Function | Gas |
|----------|-----|
| deposit | ~206,000 |
| withdraw | ~125,000 |
| withdrawWithItem | ~139,000 |
| withdrawAdminFun | ~65,000 |
| createInvestItem | ~116,000 |
| setInvestItemLockDuration | ~34,000 |
| addOperator | ~47,000 |

## Dependencies

- **Solidity**: 0.6.12
- **Hardhat**: ^2.26.3
- **OpenZeppelin Contracts**: 3.4.1
  - ReentrancyGuard
  - Pausable
  - SafeERC20
  - SafeMath

## Testing

The project includes 155 comprehensive tests covering:
- Constructor validation
- Deposit functionality with time locks
- Withdrawal functionality with lock validation
- Partial withdrawals
- Time lock enforcement
- Operator management
- Invest item management (commission and lock duration)
- WithdrawWithItem functionality
- Security features (balance validation, fee limits, lock duration limits)
- Access control
- Pause mechanism
- Two-step admin transfer

Run tests:
```bash
pnpm test
```

## Events

| Event | Parameters | Description |
|-------|------------|-------------|
| `FuturesMarginDeposit` | recordHash, account, amount, investItemId, unlockTime | Emitted on deposit |
| `FuturesMarginWithdraw` | recordHash, account, amount, fee | Emitted on withdrawal |
| `AdminWithdrawal` | vaults, amount | Emitted on admin withdrawal to vaults |
| `InvestItemCreated` | itemId, commissionBps, minLockDuration | Emitted when invest item created |
| `InvestItemStatusChanged` | itemId, active | Emitted when invest item status changes |
| `InvestItemCommissionChanged` | itemId, oldCommission, newCommission | Emitted when commission changes |
| `InvestItemLockDurationChanged` | itemId, oldDuration, newDuration | Emitted when lock duration changes |
| `OperatorAdded` | operator | Emitted when operator added |
| `OperatorRemoved` | operator | Emitted when operator removed |
| `AdminTransferInitiated` | currentAdmin, pendingAdmin | Emitted when admin transfer started |
| `AdminTransferCompleted` | oldAdmin, newAdmin | Emitted when admin transfer completed |

## License

MIT
