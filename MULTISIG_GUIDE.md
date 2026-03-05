# 多签机制详细说明

## 多签模型

合约使用 **N-of-M 多签机制**：
- **M**: Owner 总数（例如：3个 Owner）
- **N**: 最少确认数（例如：2个确认）
- **示例**: 3-of-3 多签，需要 2 个确认 = **2-of-3 多签**

## 完整流程示例（3个Owner，需要2个确认）

### 场景设置

- **Owner 1**: `0xOwner1`
- **Owner 2**: `0xOwner2`
- **Owner 3**: `0xOwner3`
- **最少确认数**: `2` (2-of-3 多签)
- **目标**: 添加 Operator `0xOperator1`

---

## 流程步骤详解

### 步骤 1: Owner1 提交提案

**操作**: Owner1 调用 `submitProposal()`

```solidity
// Owner1 提交添加 Operator 的提案
bytes memory data = abi.encode(0xOperator1);
uint256 proposalId = vault.submitProposal(
    ProposalType.AddOperator,  // 提案类型：添加 Operator
    data                        // 编码的 Operator 地址
);
```

**执行结果**:
- ✅ 创建提案，`proposalId = 1`
- ✅ 提案人（Owner1）自动确认
- ✅ `confirmations = 1`（Owner1 已确认）
- ✅ `confirmedBy[Owner1] = true`
- ✅ 发出 `MultiSigSubmitted` 事件

**当前状态**:
```
提案 ID: 1
确认数: 1/2
已确认的 Owner: [Owner1]
状态: 等待更多确认
```

---

### 步骤 2: Owner2 确认提案

**操作**: Owner2 调用 `confirmProposal(1)`

```solidity
// Owner2 确认提案
vault.confirmProposal(1);
```

**执行过程**:
1. ✅ 检查：Owner2 是否为 Owner → 通过
2. ✅ 检查：提案是否存在 → 通过
3. ✅ 检查：提案是否已执行 → 未执行
4. ✅ 检查：Owner2 是否已确认 → 未确认
5. ✅ 标记 `confirmedBy[Owner2] = true`
6. ✅ `confirmations++` → `confirmations = 2`
7. ✅ 发出 `MultiSigConfirmed` 事件
8. ✅ **自动检查**: `confirmations (2) >= requiredConfirmations (2)` → **自动执行提案**

**当前状态**:
```
提案 ID: 1
确认数: 2/2 ✅
已确认的 Owner: [Owner1, Owner2]
状态: 自动执行中...
```

---

### 步骤 3: 自动执行提案

**触发**: 在 `confirmProposal()` 中，当确认数达到要求时自动调用 `executeProposal()`

**执行过程**:
1. ✅ 检查：提案是否存在 → 通过
2. ✅ 检查：提案是否已执行 → 未执行
3. ✅ 检查：确认数是否足够 → `2 >= 2` → 通过
4. ✅ 标记 `executed = true`
5. ✅ 根据提案类型执行操作：
   ```solidity
   address operator = abi.decode(proposal.data, (address));
   _addOperator(operator);  // 添加 Operator
   ```
6. ✅ 发出 `MultiSigExecuted` 事件
7. ✅ 发出 `OperatorAdded` 事件

**最终状态**:
```
提案 ID: 1
确认数: 2/2
已确认的 Owner: [Owner1, Owner2]
状态: ✅ 已执行
Operator 0xOperator1: ✅ 已添加
```

---

## 关键理解点

### ✅ 您的理解基本正确，但有一些细节：

1. **提交提案**：
   - ✅ 只需要 **1个 Owner** 调用 `submitProposal()`
   - ✅ 提交者自动确认（`confirmations = 1`）
   - ✅ 返回提案 ID

2. **确认提案**：
   - ✅ 需要 **其他 Owner** 调用 `confirmProposal(proposalId)`
   - ✅ 每个 Owner 只能确认一次
   - ✅ 确认数达到要求时**自动执行**（无需手动调用）

3. **执行提案**：
   - ✅ **自动执行**：当确认数达到要求时，在 `confirmProposal()` 中自动调用
   - ✅ **手动执行**（可选）：也可以直接调用 `executeProposal(proposalId)`，但需要确认数已足够

---

## 完整流程图

```
┌─────────────────────────────────────────────────────────┐
│  步骤 1: Owner1 提交提案                                 │
│  submitProposal(AddOperator, operatorAddress)           │
│  → 提案 ID = 1                                          │
│  → 确认数 = 1 (Owner1 自动确认)                         │
│  → 状态: 等待更多确认                                    │
└─────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────┐
│  步骤 2: Owner2 确认提案                                 │
│  confirmProposal(1)                                     │
│  → 确认数 = 2 (Owner1 + Owner2)                        │
│  → 检查: 2 >= 2 (requiredConfirmations) ✅              │
│  → 自动执行提案                                          │
└─────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────┐
│  步骤 3: 自动执行提案                                     │
│  executeProposal(1) [自动调用]                          │
│  → 执行: _addOperator(operatorAddress)                    │
│  → Operator 已添加 ✅                                    │
│  → 状态: 已执行                                          │
└─────────────────────────────────────────────────────────┘
```

---

## 实际执行示例

### 场景：3个Owner，需要2个确认（2-of-3）

```bash
# ============ 步骤 1: Owner1 提交提案 ============
# Owner1 的私钥
OWNER1_KEY="0x..."

# 准备提案数据
OPERATOR_ADDRESS="0xOperator1"
PROPOSAL_DATA=$(cast abi-encode "f(address)" $OPERATOR_ADDRESS)

# Owner1 提交提案
cast send $VAULT_CONTRACT \
    "submitProposal(uint8,bytes)" \
    0 \
    $PROPOSAL_DATA \
    --private-key $OWNER1_KEY \
    --rpc-url $RPC_URL \
    --legacy

# 输出: 提案 ID = 1，确认数 = 1

# ============ 步骤 2: Owner2 确认提案 ============
# Owner2 的私钥
OWNER2_KEY="0x..."

# Owner2 确认提案（会自动执行）
cast send $VAULT_CONTRACT \
    "confirmProposal(uint256)" \
    1 \
    --private-key $OWNER2_KEY \
    --rpc-url $RPC_URL \
    --legacy

# 输出: 确认数 = 2，提案自动执行，Operator 已添加
```

---

## 不同多签配置示例

### 示例 1: 2-of-3 多签（当前部署）

```
Owner: [Owner1, Owner2, Owner3]
Required Confirmations: 2

流程:
1. Owner1 提交 → 确认数 = 1
2. Owner2 确认 → 确认数 = 2 → 自动执行 ✅
```

### 示例 2: 3-of-5 多签

```
Owner: [Owner1, Owner2, Owner3, Owner4, Owner5]
Required Confirmations: 3

流程:
1. Owner1 提交 → 确认数 = 1
2. Owner2 确认 → 确认数 = 2
3. Owner3 确认 → 确认数 = 3 → 自动执行 ✅
```

### 示例 3: 1-of-1 多签（当前测试部署）

```
Owner: [Owner1]
Required Confirmations: 1

流程:
1. Owner1 提交 → 确认数 = 1 → 自动执行 ✅
```

---

## 重要注意事项

### ✅ 自动执行机制

**关键点**: 当确认数达到要求时，提案会**自动执行**，无需手动调用 `executeProposal()`。

```solidity
// 在 confirmProposal() 中
if (proposal.confirmations >= requiredConfirmations) {
    executeProposal(proposalId);  // 自动执行
}
```

### ⚠️ 防止重复确认

- 每个 Owner 只能确认一次
- 如果已确认，再次调用会失败：`"UserVault: already confirmed"`

### ⚠️ 防止重复执行

- 每个提案只能执行一次
- 如果已执行，再次调用会失败：`"UserVault: proposal already executed"`

### ⚠️ 提案顺序

- 提案按顺序编号（1, 2, 3, ...）
- 可以同时有多个提案等待确认
- 每个提案独立处理

---

## 查询提案状态

### 查看提案信息

```bash
# 获取提案详情
cast call $VAULT_CONTRACT \
    "getProposal(uint256)(uint256,address,uint8,uint256,bool)" \
    1 \
    --rpc-url $RPC_URL

# 返回: (id, proposer, proposalType, confirmations, executed)
```

### 查看确认数

```bash
cast call $VAULT_CONTRACT \
    "getProposalConfirmations(uint256)(uint256)" \
    1 \
    --rpc-url $RPC_URL
```

### 检查 Owner 是否已确认

```bash
cast call $VAULT_CONTRACT \
    "hasConfirmed(uint256,address)(bool)" \
    1 \
    0xOwner1 \
    --rpc-url $RPC_URL
```

---

## 总结

### 对于 3个Owner，需要2个确认的情况：

1. ✅ **1个 Owner** 提交提案 → 获得提案 ID
2. ✅ **1个其他 Owner** 确认提案 → 达到2个确认
3. ✅ **自动执行** → Operator 已添加

**总共需要**: 2个 Owner 的操作（1个提交 + 1个确认）

**不需要**: 手动调用 `executeProposal()`（会自动执行）

---

## 与您的理解对比

| 您的理解 | 实际情况 |
|---------|---------|
| 需要2个owner调用提案方法 | ✅ 正确：1个提交 + 1个确认 = 2个操作 |
| 获取提案id | ✅ 正确：提交时返回提案ID |
| 执行提案id流程 | ⚠️ 部分正确：**自动执行**，也可手动执行 |

**关键区别**: 执行是**自动的**，当确认数达到要求时，在 `confirmProposal()` 中自动调用 `executeProposal()`。
