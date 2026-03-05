# 用户充值脚本使用说明

## 脚本文件

1. **`deposit_simple.sh`** - 简化版充值脚本（推荐，不依赖 Python）
2. **`deposit.sh`** - 完整版充值脚本（自动检测 token decimals）

## 快速使用

### 方式一：使用简化脚本（推荐）

```bash
cd /Users/quanligao/project/contract/kuant-user-vault-management
./scripts/deposit_simple.sh
```

### 方式二：直接使用 cast 命令

如果脚本无法运行，可以直接使用以下命令：

#### 步骤 1: 授权合约使用代币

```bash
cast send 0x76CeE3E0FDF715F50B15Ca83c0ed8C454c7F88A3 \
    "approve(address,uint256)" \
    0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E \
    50000000000000000000 \
    --private-key 39b36efe563e1d284dcc5cfe7c5b00207e8fef1bd41d343ee5c1cb0dc805a668 \
    --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 \
    --legacy
```

#### 步骤 2: 充值到合约

```bash
# 生成 depositId
DEPOSIT_ID=$(cast keccak256 $(echo -n "$(date +%s)$RANDOM" | xxd -p))

# 执行充值
cast send 0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E \
    "deposit(uint256,bytes32)" \
    50000000000000000000 \
    $DEPOSIT_ID \
    --private-key 39b36efe563e1d284dcc5cfe7c5b00207e8fef1bd41d343ee5c1cb0dc805a668 \
    --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 \
    --legacy
```

## 配置说明

### 当前配置

- **合约地址**: `0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E`
- **Token 地址**: `0x76CeE3E0FDF715F50B15Ca83c0ed8C454c7F88A3`
- **用户私钥**: `39b36efe563e1d284dcc5cfe7c5b00207e8fef1bd41d343ee5c1cb0dc805a668`
- **充值金额**: 50 tokens
- **RPC URL**: `https://data-seed-prebsc-1-s1.binance.org:8545`

### 金额说明

脚本中使用的金额是 `50000000000000000000` wei，这假设 token 有 18 位小数。

如果您的 token 有不同的小数位数，需要调整：

- **18 位小数** (如 ETH): `50000000000000000000` (50 * 10^18)
- **6 位小数** (如 USDC): `50000000` (50 * 10^6)
- **8 位小数** (如 BTC): `5000000000` (50 * 10^8)

### 检查 Token Decimals

```bash
cast call 0x76CeE3E0FDF715F50B15Ca83c0ed8C454c7F88A3 \
    "decimals()(uint8)" \
    --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545
```

## 脚本执行流程

1. **检查用户余额** - 验证用户有足够的 token
2. **检查授权额度** - 检查是否已授权合约使用代币
3. **授权（如需要）** - 如果授权不足，自动授权
4. **执行充值** - 调用合约的 deposit 函数
5. **验证结果** - 检查充值是否成功

## 验证充值

### 检查用户在合约中的余额

```bash
cast call 0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E \
    "balances(address)(uint256)" \
    0x<用户地址> \
    --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545
```

### 在 BSCScan 上查看

访问交易哈希链接查看交易详情：
```
https://testnet.bscscan.com/tx/<交易哈希>
```

## 常见问题

### Q1: 授权失败

**A:** 检查：
- 用户是否有足够的 token
- 网络连接是否正常
- RPC URL 是否正确

### Q2: 充值失败，提示 "depositId already used"

**A:** 生成的 depositId 已使用，脚本会自动生成新的，重试即可。

### Q3: 充值失败，提示 "insufficient allowance"

**A:** 授权额度不足，确保授权金额 >= 充值金额。

### Q4: 如何修改充值金额？

**A:** 编辑脚本中的 `DEPOSIT_AMOUNT` 变量，或使用环境变量：

```bash
export DEPOSIT_AMOUNT="100000000000000000000"  # 100 tokens (18 decimals)
./scripts/deposit_simple.sh
```

## 安全提醒

⚠️ **重要**:
- 私钥已硬编码在脚本中，仅用于测试
- 生产环境请使用环境变量或密钥管理工具
- 不要将包含私钥的脚本提交到代码仓库
