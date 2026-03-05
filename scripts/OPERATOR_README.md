# 添加 Operator 脚本使用说明

## 脚本文件

1. **`add_operator.sh`** - 完整版脚本（推荐，包含详细检查和验证）
2. **`add_operator_simple.sh`** - 简化版脚本（快速执行）

## 快速使用

### 方式一：使用完整脚本（推荐）

```bash
cd /Users/quanligao/project/contract/kuant-user-vault-management
./scripts/add_operator.sh
```

### 方式二：使用简化脚本

```bash
cd /Users/quanligao/project/contract/kuant-user-vault-management
./scripts/add_operator_simple.sh
```

### 方式三：直接使用 cast 命令

如果脚本无法运行，可以直接使用以下命令：

```bash
# 1. 准备提案数据（编码 operator 地址）
OPERATOR_ADDRESS="0x07e3aabd2d4d5dcec107ef9555dc0e5ef24f62b3"
PROPOSAL_DATA=$(cast abi-encode "f(address)" $OPERATOR_ADDRESS)

# 2. 提交提案（ProposalType.AddOperator = 0）
cast send 0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E \
    "submitProposal(uint8,bytes)" \
    0 \
    $PROPOSAL_DATA \
    --private-key 6f4058fa7ab22b3c83290a6bca1be7d43ed911d4ffe5f3d1003d413fdfd425c7 \
    --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 \
    --legacy
```

## 配置信息

### 当前配置

- **合约地址**: `0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E`
- **Owner 私钥**: `6f4058fa7ab22b3c83290a6bca1be7d43ed911d4ffe5f3d1003d413fdfd425c7`
- **Operator 地址**: `0x07e3aabd2d4d5dcec107ef9555dc0e5ef24f62b3`
- **RPC URL**: `https://data-seed-prebsc-1-s1.binance.org:8545`

### 多签说明

当前合约配置为 **1-of-1 多签**，这意味着：
- 提交提案后会自动确认（因为提交者就是唯一的 Owner）
- 确认数达到要求后会自动执行
- 无需额外的确认步骤

## 脚本执行流程

1. **检查 Operator 状态** - 验证 Operator 是否已存在
2. **检查 Owner 权限** - 验证提交者是否为 Owner
3. **准备提案数据** - 编码 Operator 地址
4. **提交提案** - 调用 `submitProposal(AddOperator, data)`
5. **自动执行** - 由于是 1-of-1 多签，提案会自动执行
6. **验证结果** - 检查 Operator 是否已成功添加

## 验证 Operator

### 检查 Operator 状态

```bash
cast call 0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E \
    "operators(address)(bool)" \
    0x07e3aabd2d4d5dcec107ef9555dc0e5ef24f62b3 \
    --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545
```

返回 `true` 表示 Operator 已添加。

### 在 BSCScan 上查看

访问交易哈希链接查看交易详情：
```
https://testnet.bscscan.com/tx/<交易哈希>
```

## 移除 Operator

如果需要移除 Operator，可以使用类似的脚本，但提案类型改为 `RemoveOperator` (1)：

```bash
# 准备提案数据
OPERATOR_ADDRESS="0x07e3aabd2d4d5dcec107ef9555dc0e5ef24f62b3"
PROPOSAL_DATA=$(cast abi-encode "f(address)" $OPERATOR_ADDRESS)

# 提交移除提案（ProposalType.RemoveOperator = 1）
cast send 0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E \
    "submitProposal(uint8,bytes)" \
    1 \
    $PROPOSAL_DATA \
    --private-key 6f4058fa7ab22b3c83290a6bca1be7d43ed911d4ffe5f3d1003d413fdfd425c7 \
    --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 \
    --legacy
```

## 提案类型

- `AddOperator` = 0
- `RemoveOperator` = 1
- `Pause` = 2
- `Unpause` = 3

## 常见问题

### Q1: 提交提案失败，提示 "caller is not owner"

**A:** 确保使用的私钥是 Owner 的私钥。

### Q2: Operator 已存在

**A:** 脚本会检测并提示，不会重复添加。

### Q3: 如何查看所有 Operator？

**A:** 合约没有提供查看所有 Operator 的函数，需要逐个检查地址。

### Q4: 提案提交后多久执行？

**A:** 由于是 1-of-1 多签，提案提交后会在同一个交易中自动执行。

## 安全提醒

⚠️ **重要**:
- Owner 私钥已硬编码在脚本中，仅用于测试
- 生产环境请使用环境变量或密钥管理工具
- 不要将包含私钥的脚本提交到代码仓库
