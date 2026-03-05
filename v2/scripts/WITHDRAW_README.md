# 用户提现脚本使用说明

## 脚本文件

1. **`withdraw.sh`** - 完整版脚本（推荐，包含详细检查和验证）
2. **`withdraw_simple.sh`** - 简化版脚本（快速执行）

## 快速使用

### 方式一：使用完整脚本（推荐）

```bash
cd /Users/quanligao/project/contract/kuant-user-vault-management
./scripts/withdraw.sh
```

### 方式二：使用简化脚本

```bash
cd /Users/quanligao/project/contract/kuant-user-vault-management
./scripts/withdraw_simple.sh
```

### 方式三：直接使用 cast 命令

如果脚本无法运行，可以直接使用以下命令：

```bash
cast send 0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E \
    "withdraw(uint256)" \
    30000000000000000000 \
    --private-key 39b36efe563e1d284dcc5cfe7c5b00207e8fef1bd41d343ee5c1cb0dc805a668 \
    --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 \
    --legacy
```

## 配置信息

### 当前配置

- **合约地址**: `0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E`
- **Token 地址**: `0x76CeE3E0FDF715F50B15Ca83c0ed8C454c7F88A3`
- **用户私钥**: `39b36efe563e1d284dcc5cfe7c5b00207e8fef1bd41d343ee5c1cb0dc805a668`
- **提现金额**: 30 tokens
- **RPC URL**: `https://data-seed-prebsc-1-s1.binance.org:8545`

### 金额说明

脚本中使用的金额是 `30000000000000000000` wei，这假设 token 有 18 位小数。

如果您的 token 有不同的小数位数，需要调整：

- **18 位小数** (如 ETH): `30000000000000000000` (30 * 10^18)
- **6 位小数** (如 USDC): `30000000` (30 * 10^6)
- **8 位小数** (如 BTC): `3000000000` (30 * 10^8)

### 检查 Token Decimals

```bash
cast call 0x76CeE3E0FDF715F50B15Ca83c0ed8C454c7F88A3 \
    "decimals()(uint8)" \
    --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545
```

## 脚本执行流程

1. **获取用户地址** - 从私钥推导用户地址
2. **检查用户余额** - 验证用户在合约中的余额是否足够
3. **检查合约状态** - 验证合约是否暂停
4. **执行提现** - 调用 `withdraw` 函数
5. **验证结果** - 检查用户余额和钱包余额

## 函数说明

### withdraw

```solidity
function withdraw(uint256 amount) 
    external 
    whenNotPaused 
    nonReentrant
```

**前置条件**：
- 合约未暂停
- 用户余额 >= 提现金额

**功能**：
- 从用户在合约中的余额扣除提现金额
- 将代币从合约转账到用户钱包

**安全机制**：
- 使用 `nonReentrant` 防止重入攻击
- 使用 `whenNotPaused` 确保合约正常运行

## 验证提现

### 检查用户在合约中的余额

```bash
cast call 0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E \
    "balances(address)(uint256)" \
    0x<用户地址> \
    --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545
```

### 检查用户钱包 Token 余额

```bash
cast call 0x76CeE3E0FDF715F50B15Ca83c0ed8C454c7F88A3 \
    "balanceOf(address)(uint256)" \
    0x<用户地址> \
    --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545
```

### 在 BSCScan 上查看

访问交易哈希链接查看交易详情：
```
https://testnet.bscscan.com/tx/<交易哈希>
```

## 常见问题

### Q1: 提现失败，提示 "insufficient balance"

**A:** 用户在合约中的余额不足，需要先充值。

### Q2: 提现失败，提示 "paused"

**A:** 合约已暂停，需要等待多签恢复合约。

### Q3: 如何修改提现金额？

**A:** 编辑脚本中的 `WITHDRAW_AMOUNT` 变量，或使用环境变量：

```bash
export WITHDRAW_AMOUNT="100000000000000000000"  # 100 tokens (18 decimals)
./scripts/withdraw.sh
```

### Q4: 提现后多久到账？

**A:** 交易确认后立即到账，通常需要几秒钟到几分钟。

## 安全提醒

⚠️ **重要**:
- 用户私钥已硬编码在脚本中，仅用于测试
- 生产环境请使用环境变量或密钥管理工具
- 不要将包含私钥的脚本提交到代码仓库
- 提现会直接从用户在合约中的余额扣除，请确认金额正确
