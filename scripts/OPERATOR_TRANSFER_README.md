# Operator 转账脚本使用说明

## 脚本文件

1. **`operator_transfer.sh`** - 完整版脚本（推荐，包含详细检查和验证）
2. **`operator_transfer_simple.sh`** - 简化版脚本（快速执行）

## 快速使用

### 方式一：使用完整脚本（推荐）

```bash
cd /Users/quanligao/project/contract/kuant-user-vault-management
./scripts/operator_transfer.sh
```

### 方式二：使用简化脚本

```bash
cd /Users/quanligao/project/contract/kuant-user-vault-management
./scripts/operator_transfer_simple.sh
```

### 方式三：直接使用 cast 命令

如果脚本无法运行，可以直接使用以下命令：

```bash
# 1. 生成唯一的 opId
OP_ID=$(cast keccak256 $(echo -n "$(date +%s)$RANDOM" | xxd -p))

# 2. 执行转账
cast send 0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E \
    "operatorTransfer(address,address,uint256,bytes32)" \
    0x22ae03eccb791e547478f50c584c58a3d342796f \
    0x22ae03eccb791e547478f50c584c58a3d342796f \
    50000000000000000000 \
    $OP_ID \
    --private-key ae4a4050afb424fd7fb75518ed89dfe4caf300aed49e5b7976036fc4b9da3a97 \
    --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 \
    --legacy
```

## 配置信息

### 当前配置

- **合约地址**: `0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E`
- **Token 地址**: `0x76CeE3E0FDF715F50B15Ca83c0ed8C454c7F88A3`
- **Operator 私钥**: `ae4a4050afb424fd7fb75518ed89dfe4caf300aed49e5b7976036fc4b9da3a97`
- **用户地址**: `0x22ae03eccb791e547478f50c584c58a3d342796f`
- **接收地址**: `0x22ae03eccb791e547478f50c584c58a3d342796f`
- **转账金额**: 50 tokens
- **RPC URL**: `https://data-seed-prebsc-1-s1.binance.org:8545`

### 金额说明

脚本中使用的金额是 `50000000000000000000` wei，这假设 token 有 18 位小数。

如果您的 token 有不同的小数位数，需要调整：

- **18 位小数** (如 ETH): `50000000000000000000` (50 * 10^18)
- **6 位小数** (如 USDC): `50000000` (50 * 10^6)
- **8 位小数** (如 BTC): `5000000000` (50 * 10^8)

## 脚本执行流程

1. **检查 Operator 权限** - 验证调用者是否为 Operator
2. **检查用户余额** - 验证用户在合约中的余额是否足够
3. **检查 opId** - 验证操作 ID 是否已使用（防重）
4. **检查合约状态** - 验证合约是否暂停
5. **执行转账** - 调用 `operatorTransfer` 函数
6. **验证结果** - 检查用户余额和接收地址余额

## 函数说明

### operatorTransfer

```solidity
function operatorTransfer(
    address user,      // 用户地址（资金从哪个用户账户转出）
    address to,        // 接收地址（资金转到哪里）
    uint256 amount,    // 转账金额
    bytes32 opId       // 唯一操作 ID（用于防重）
) external onlyOperator whenNotPaused nonReentrant
```

**前置条件**：
- 调用者必须是 Operator
- 合约未暂停
- 用户余额 >= 转账金额
- opId 未被使用

**功能**：
- 从用户在合约中的余额扣除转账金额
- 将代币从合约转账到接收地址
- 标记 opId 为已使用

## 验证转账

### 检查用户余额

```bash
cast call 0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E \
    "balances(address)(uint256)" \
    0x22ae03eccb791e547478f50c584c58a3d342796f \
    --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545
```

### 检查接收地址 Token 余额

```bash
cast call 0x76CeE3E0FDF715F50B15Ca83c0ed8C454c7F88A3 \
    "balanceOf(address)(uint256)" \
    0x22ae03eccb791e547478f50c584c58a3d342796f \
    --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545
```

### 在 BSCScan 上查看

访问交易哈希链接查看交易详情：
```
https://testnet.bscscan.com/tx/<交易哈希>
```

## 常见问题

### Q1: 转账失败，提示 "caller is not operator"

**A:** 确保使用的私钥是 Operator 的私钥，并且该地址已被添加为 Operator。

### Q2: 转账失败，提示 "insufficient balance"

**A:** 用户在合约中的余额不足，需要先充值。

### Q3: 转账失败，提示 "opId already used"

**A:** 操作 ID 已使用，脚本会自动生成新的 opId。

### Q4: 转账失败，提示 "paused"

**A:** 合约已暂停，需要先恢复合约。

### Q5: 如何修改转账金额？

**A:** 编辑脚本中的 `TRANSFER_AMOUNT` 变量，或使用环境变量：

```bash
export TRANSFER_AMOUNT="100000000000000000000"  # 100 tokens (18 decimals)
./scripts/operator_transfer.sh
```

## 安全提醒

⚠️ **重要**:
- Operator 私钥已硬编码在脚本中，仅用于测试
- 生产环境请使用环境变量或密钥管理工具
- 不要将包含私钥的脚本提交到代码仓库
- Operator 转账会直接从用户在合约中的余额扣除，请谨慎操作
