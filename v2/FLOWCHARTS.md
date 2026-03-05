# UserVault 合约详细流程图

本文档包含 UserVault 合约的所有核心功能的详细流程图。

## 目录

1. [整体架构流程图](#整体架构流程图)
2. [用户充值流程图](#用户充值流程图)
3. [用户提现流程图](#用户提现流程图)
4. [Operator 充值流程图](#operator-充值流程图)
5. [Operator 转账流程图](#operator-转账流程图)
6. [多签提案流程图](#多签提案流程图)
7. [合约状态转换图](#合约状态转换图)
8. [防重复机制流程图](#防重复机制流程图)

---

## 整体架构流程图

```mermaid
graph TB
    Start([开始]) --> Init[合约初始化]
    Init --> Config{配置参数}
    Config -->|设置| Token[ERC20 代币地址]
    Config -->|设置| Owners[Owner 地址数组]
    Config -->|设置| Confirmations[最少确认数]
    
    Token --> Deploy[部署合约]
    Owners --> Deploy
    Confirmations --> Deploy
    
    Deploy --> Ready[合约就绪]
    
    Ready --> UserOps[用户操作]
    Ready --> OperatorOps[Operator 操作]
    Ready --> MultiSigOps[多签操作]
    
    UserOps --> Deposit[用户充值]
    UserOps --> Withdraw[用户提现]
    
    OperatorOps --> OpDeposit[Operator 充值]
    OperatorOps --> OpTransfer[Operator 转账]
    
    MultiSigOps --> AddOp[添加 Operator]
    MultiSigOps --> RemoveOp[移除 Operator]
    MultiSigOps --> Pause[暂停合约]
    MultiSigOps --> Unpause[恢复合约]
    
    Deposit --> End([结束])
    Withdraw --> End
    OpDeposit --> End
    OpTransfer --> End
    AddOp --> End
    RemoveOp --> End
    Pause --> End
    Unpause --> End
```

---

## 用户充值流程图

```mermaid
flowchart TD
    Start([用户发起充值]) --> CheckPaused{合约是否暂停?}
    CheckPaused -->|是| Revert1[回退: 合约已暂停]
    CheckPaused -->|否| CheckAmount{金额 > 0?}
    
    CheckAmount -->|否| Revert2[回退: 金额必须大于 0]
    CheckAmount -->|是| CheckDepositId{检查 depositId}
    
    CheckDepositId -->|已使用| Revert3[回退: depositId 已使用]
    CheckDepositId -->|未使用| CheckReentrant{检查重入锁}
    
    CheckReentrant -->|已锁定| Revert4[回退: 重入攻击]
    CheckReentrant -->|未锁定| Lock[设置重入锁]
    
    Lock --> MarkDepositId[标记 depositId 为已使用]
    MarkDepositId --> UpdateBalance[更新用户内部余额]
    UpdateBalance --> TransferFrom[从用户账户转账到合约]
    
    TransferFrom --> CheckTransfer{转账成功?}
    CheckTransfer -->|否| Revert5[回退: 转账失败]
    CheckTransfer -->|是| EmitEvent[发出 Deposit 事件]
    
    EmitEvent --> Unlock[释放重入锁]
    Unlock --> Success([充值成功])
    
    Revert1 --> End([结束])
    Revert2 --> End
    Revert3 --> End
    Revert4 --> End
    Revert5 --> End
    Success --> End
    
    style Start fill:#e1f5ff
    style Success fill:#c8e6c9
    style Revert1 fill:#ffcdd2
    style Revert2 fill:#ffcdd2
    style Revert3 fill:#ffcdd2
    style Revert4 fill:#ffcdd2
    style Revert5 fill:#ffcdd2
```

### 用户充值详细步骤

1. **前置检查**
   - 检查合约是否暂停 (`whenNotPaused`)
   - 检查金额是否大于 0
   - 检查 `depositId` 是否已使用
   - 检查重入锁状态 (`nonReentrant`)

2. **状态更新** (Checks → Effects)
   - 标记 `depositId` 为已使用
   - 更新用户内部余额：`balances[user] += amount`

3. **外部交互** (Interactions)
   - 从用户账户转账到合约：`token.transferFrom(user, contract, amount)`

4. **事件发出**
   - 发出 `Deposit` 事件

5. **清理**
   - 释放重入锁

---

## 用户提现流程图

```mermaid
flowchart TD
    Start([用户发起提现]) --> CheckPaused{合约是否暂停?}
    CheckPaused -->|是| Revert1[回退: 合约已暂停]
    CheckPaused -->|否| CheckAmount{金额 > 0?}
    
    CheckAmount -->|否| Revert2[回退: 金额必须大于 0]
    CheckAmount -->|是| CheckBalance{用户余额 >= 金额?}
    
    CheckBalance -->|否| Revert3[回退: 余额不足]
    CheckBalance -->|是| CheckReentrant{检查重入锁}
    
    CheckReentrant -->|已锁定| Revert4[回退: 重入攻击]
    CheckReentrant -->|未锁定| Lock[设置重入锁]
    
    Lock --> UpdateBalance[更新用户内部余额]
    UpdateBalance --> Transfer[从合约转账给用户]
    
    Transfer --> CheckTransfer{转账成功?}
    CheckTransfer -->|否| Revert5[回退: 转账失败]
    CheckTransfer -->|是| EmitEvent[发出 Withdraw 事件]
    
    EmitEvent --> Unlock[释放重入锁]
    Unlock --> Success([提现成功])
    
    Revert1 --> End([结束])
    Revert2 --> End
    Revert3 --> End
    Revert4 --> End
    Revert5 --> End
    Success --> End
    
    style Start fill:#e1f5ff
    style Success fill:#c8e6c9
    style Revert1 fill:#ffcdd2
    style Revert2 fill:#ffcdd2
    style Revert3 fill:#ffcdd2
    style Revert4 fill:#ffcdd2
    style Revert5 fill:#ffcdd2
```

### 用户提现详细步骤

1. **前置检查**
   - 检查合约是否暂停
   - 检查金额是否大于 0
   - 检查用户余额是否足够
   - 检查重入锁状态

2. **状态更新** (Checks → Effects)
   - 更新用户内部余额：`balances[user] -= amount`

3. **外部交互** (Interactions)
   - 从合约转账给用户：`token.transfer(user, amount)`

4. **事件发出**
   - 发出 `Withdraw` 事件

5. **清理**
   - 释放重入锁

---

## Operator 充值流程图

```mermaid
flowchart TD
    Start([Operator 发起充值]) --> CheckOperator{检查 Operator 权限}
    CheckOperator -->|否| Revert1[回退: 不是 Operator]
    CheckOperator -->|是| CheckPaused{合约是否暂停?}
    
    CheckPaused -->|是| Revert2[回退: 合约已暂停]
    CheckPaused -->|否| CheckUser{用户地址有效?}
    
    CheckUser -->|否| Revert3[回退: 无效用户地址]
    CheckUser -->|是| CheckAmount{金额 > 0?}
    
    CheckAmount -->|否| Revert4[回退: 金额必须大于 0]
    CheckAmount -->|是| CheckOpId{检查 opId}
    
    CheckOpId -->|已使用| Revert5[回退: opId 已使用]
    CheckOpId -->|未使用| CheckReentrant{检查重入锁}
    
    CheckReentrant -->|已锁定| Revert6[回退: 重入攻击]
    CheckReentrant -->|未锁定| Lock[设置重入锁]
    
    Lock --> MarkOpId[标记 opId 为已使用]
    MarkOpId --> UpdateBalance[更新用户内部余额]
    UpdateBalance --> TransferFrom[从 Operator 账户转账到合约]
    
    TransferFrom --> CheckTransfer{转账成功?}
    CheckTransfer -->|否| Revert7[回退: 转账失败]
    CheckTransfer -->|是| EmitEvent[发出 OperatorDeposit 事件]
    
    EmitEvent --> Unlock[释放重入锁]
    Unlock --> Success([充值成功])
    
    Revert1 --> End([结束])
    Revert2 --> End
    Revert3 --> End
    Revert4 --> End
    Revert5 --> End
    Revert6 --> End
    Revert7 --> End
    Success --> End
    
    style Start fill:#e1f5ff
    style Success fill:#c8e6c9
    style Revert1 fill:#ffcdd2
    style Revert2 fill:#ffcdd2
    style Revert3 fill:#ffcdd2
    style Revert4 fill:#ffcdd2
    style Revert5 fill:#ffcdd2
    style Revert6 fill:#ffcdd2
    style Revert7 fill:#ffcdd2
```

---

## Operator 转账流程图

```mermaid
flowchart TD
    Start([Operator 发起转账]) --> CheckOperator{检查 Operator 权限}
    CheckOperator -->|否| Revert1[回退: 不是 Operator]
    CheckOperator -->|是| CheckPaused{合约是否暂停?}
    
    CheckPaused -->|是| Revert2[回退: 合约已暂停]
    CheckPaused -->|否| CheckUser{用户地址有效?}
    
    CheckUser -->|否| Revert3[回退: 无效用户地址]
    CheckUser -->|是| CheckTo{接收地址有效?}
    
    CheckTo -->|否| Revert4[回退: 无效接收地址]
    CheckTo -->|是| CheckAmount{金额 > 0?}
    
    CheckAmount -->|否| Revert5[回退: 金额必须大于 0]
    CheckAmount -->|是| CheckBalance{用户余额 >= 金额?}
    
    CheckBalance -->|否| Revert6[回退: 余额不足]
    CheckBalance -->|是| CheckOpId{检查 opId}
    
    CheckOpId -->|已使用| Revert7[回退: opId 已使用]
    CheckOpId -->|未使用| CheckReentrant{检查重入锁}
    
    CheckReentrant -->|已锁定| Revert8[回退: 重入攻击]
    CheckReentrant -->|未锁定| Lock[设置重入锁]
    
    Lock --> MarkOpId[标记 opId 为已使用]
    MarkOpId --> UpdateBalance[更新用户内部余额]
    UpdateBalance --> Transfer[从合约转账给接收地址]
    
    Transfer --> CheckTransfer{转账成功?}
    CheckTransfer -->|否| Revert9[回退: 转账失败]
    CheckTransfer -->|是| EmitEvent[发出 OperatorTransfer 事件]
    
    EmitEvent --> Unlock[释放重入锁]
    Unlock --> Success([转账成功])
    
    Revert1 --> End([结束])
    Revert2 --> End
    Revert3 --> End
    Revert4 --> End
    Revert5 --> End
    Revert6 --> End
    Revert7 --> End
    Revert8 --> End
    Revert9 --> End
    Success --> End
    
    style Start fill:#e1f5ff
    style Success fill:#c8e6c9
    style Revert1 fill:#ffcdd2
    style Revert2 fill:#ffcdd2
    style Revert3 fill:#ffcdd2
    style Revert4 fill:#ffcdd2
    style Revert5 fill:#ffcdd2
    style Revert6 fill:#ffcdd2
    style Revert7 fill:#ffcdd2
    style Revert8 fill:#ffcdd2
    style Revert9 fill:#ffcdd2
```

---

## 多签提案流程图

```mermaid
flowchart TD
    Start([Owner 提交提案]) --> CheckOwner{检查 Owner 权限}
    CheckOwner -->|否| Revert1[回退: 不是 Owner]
    CheckOwner -->|是| CreateProposal[创建提案]
    
    CreateProposal --> SetProposalId[设置提案 ID]
    SetProposalId --> SetProposer[设置提案人]
    SetProposer --> SetType[设置提案类型]
    SetType --> SetData[设置提案数据]
    SetData --> SetConfirmations[设置确认数 = 1]
    SetConfirmations --> MarkConfirmed[标记提案人已确认]
    MarkConfirmed --> EmitSubmitted[发出 MultiSigSubmitted 事件]
    
    EmitSubmitted --> WaitConfirm[等待其他 Owner 确认]
    
    WaitConfirm --> OwnerConfirm[其他 Owner 确认]
    OwnerConfirm --> CheckOwner2{检查 Owner 权限}
    CheckOwner2 -->|否| Revert2[回退: 不是 Owner]
    CheckOwner2 -->|是| CheckProposal{提案存在?}
    
    CheckProposal -->|否| Revert3[回退: 提案不存在]
    CheckProposal -->|是| CheckExecuted{提案已执行?}
    
    CheckExecuted -->|是| Revert4[回退: 提案已执行]
    CheckExecuted -->|否| CheckConfirmed{已确认过?}
    
    CheckConfirmed -->|是| Revert5[回退: 已确认过]
    CheckConfirmed -->|否| MarkOwnerConfirmed[标记 Owner 已确认]
    
    MarkOwnerConfirmed --> IncrementConfirm[确认数 +1]
    IncrementConfirm --> EmitConfirmed[发出 MultiSigConfirmed 事件]
    
    EmitConfirmed --> CheckEnough{确认数 >= 最少确认数?}
    CheckEnough -->|否| WaitConfirm
    CheckEnough -->|是| ExecuteProposal[执行提案]
    
    ExecuteProposal --> CheckType{提案类型}
    CheckType -->|AddOperator| AddOp[添加 Operator]
    CheckType -->|RemoveOperator| RemoveOp[移除 Operator]
    CheckType -->|Pause| PauseContract[暂停合约]
    CheckType -->|Unpause| UnpauseContract[恢复合约]
    
    AddOp --> MarkExecuted[标记提案已执行]
    RemoveOp --> MarkExecuted
    PauseContract --> MarkExecuted
    UnpauseContract --> MarkExecuted
    
    MarkExecuted --> EmitExecuted[发出 MultiSigExecuted 事件]
    EmitExecuted --> Success([提案执行成功])
    
    Revert1 --> End([结束])
    Revert2 --> End
    Revert3 --> End
    Revert4 --> End
    Revert5 --> End
    Success --> End
    
    style Start fill:#e1f5ff
    style Success fill:#c8e6c9
    style Revert1 fill:#ffcdd2
    style Revert2 fill:#ffcdd2
    style Revert3 fill:#ffcdd2
    style Revert4 fill:#ffcdd2
    style Revert5 fill:#ffcdd2
```

### 多签提案详细步骤

#### 1. 提交提案阶段

```
Owner → submitProposal()
  ├─ 检查：是否为 Owner
  ├─ 创建提案
  │   ├─ proposalId = ++proposalCounter
  │   ├─ proposer = msg.sender
  │   ├─ proposalType = 参数
  │   ├─ data = 参数
  │   ├─ confirmations = 1
  │   └─ confirmedBy[msg.sender] = true
  └─ 发出 MultiSigSubmitted 事件
```

#### 2. 确认提案阶段

```
Owner → confirmProposal(proposalId)
  ├─ 检查：是否为 Owner
  ├─ 检查：提案是否存在
  ├─ 检查：提案是否已执行
  ├─ 检查：是否已确认过
  ├─ 更新状态
  │   ├─ confirmedBy[msg.sender] = true
  │   └─ confirmations++
  ├─ 发出 MultiSigConfirmed 事件
  └─ 如果确认数足够 → 自动执行
```

#### 3. 执行提案阶段

```
executeProposal(proposalId)
  ├─ 检查：提案是否存在
  ├─ 检查：提案是否已执行
  ├─ 检查：确认数是否足够
  ├─ 标记已执行
  ├─ 根据类型执行操作
  │   ├─ AddOperator → _addOperator()
  │   ├─ RemoveOperator → _removeOperator()
  │   ├─ Pause → _pause()
  │   └─ Unpause → _unpause()
  └─ 发出 MultiSigExecuted 事件
```

---

## 合约状态转换图

```mermaid
stateDiagram-v2
    [*] --> 未部署
    
    未部署 --> 已部署: 部署合约
    已部署 --> 运行中: 初始化完成
    
    运行中 --> 暂停: 多签执行 Pause
    暂停 --> 运行中: 多签执行 Unpause
    
    运行中 --> 运行中: 用户充值
    运行中 --> 运行中: 用户提现
    运行中 --> 运行中: Operator 操作
    
    运行中 --> 运行中: 添加 Operator
    运行中 --> 运行中: 移除 Operator
    
    暂停 --> 暂停: 所有操作被阻止
    
    note right of 运行中
        所有功能正常
        用户可以充值和提现
        Operator 可以操作
    end note
    
    note right of 暂停
        所有用户和 Operator
        操作被阻止
        只有多签可以恢复
    end note
```

---

## 防重复机制流程图

### 用户充值防重机制

```mermaid
flowchart LR
    Start([用户充值请求]) --> GenerateId[生成 depositId]
    GenerateId --> CheckId{检查 usedDepositIds}
    CheckId -->|已使用| Reject[拒绝: 重复充值]
    CheckId -->|未使用| MarkUsed[标记为已使用]
    MarkUsed --> Process[处理充值]
    Process --> Success([充值成功])
    Reject --> End([结束])
    Success --> End
    
    style Start fill:#e1f5ff
    style Success fill:#c8e6c9
    style Reject fill:#ffcdd2
```

### Operator 操作防重机制

```mermaid
flowchart LR
    Start([Operator 操作请求]) --> GenerateId[生成 opId]
    GenerateId --> CheckId{检查 usedOpIds}
    CheckId -->|已使用| Reject[拒绝: 重复操作]
    CheckId -->|未使用| MarkUsed[标记为已使用]
    MarkUsed --> Process[处理操作]
    Process --> Success([操作成功])
    Reject --> End([结束])
    Success --> End
    
    style Start fill:#e1f5ff
    style Success fill:#c8e6c9
    style Reject fill:#ffcdd2
```

---

## 完整交互序列图

### 用户充值完整流程

```mermaid
sequenceDiagram
    participant User as 用户
    participant Token as ERC20 代币
    participant Vault as UserVault 合约
    
    User->>Token: approve(vault, amount)
    Token-->>User: 授权成功
    
    User->>Vault: deposit(amount, depositId)
    
    Vault->>Vault: 检查: 合约未暂停
    Vault->>Vault: 检查: amount > 0
    Vault->>Vault: 检查: depositId 未使用
    Vault->>Vault: 检查: 重入锁未锁定
    
    Vault->>Vault: 设置重入锁
    Vault->>Vault: 标记 depositId 已使用
    Vault->>Vault: 更新用户余额
    
    Vault->>Token: transferFrom(user, vault, amount)
    Token-->>Vault: 转账成功
    
    Vault->>Vault: 发出 Deposit 事件
    Vault->>Vault: 释放重入锁
    
    Vault-->>User: 充值成功
```

### 多签添加 Operator 完整流程

```mermaid
sequenceDiagram
    participant Owner1 as Owner 1
    participant Owner2 as Owner 2
    participant Owner3 as Owner 3
    participant Vault as UserVault 合约
    
    Owner1->>Vault: submitProposal(AddOperator, operator)
    Vault->>Vault: 创建提案 (ID=1)
    Vault->>Vault: 确认数 = 1
    Vault-->>Owner1: 提案 ID = 1
    
    Owner2->>Vault: confirmProposal(1)
    Vault->>Vault: 确认数 = 2
    Vault->>Vault: 检查: 确认数 >= 2
    Vault->>Vault: 执行提案
    Vault->>Vault: _addOperator(operator)
    Vault->>Vault: operators[operator] = true
    Vault-->>Owner2: 提案已执行
    
    Note over Vault: Operator 已添加
```

---

## 数据流图

### 用户余额管理数据流

```mermaid
flowchart TD
    User[用户] -->|充值| Vault[UserVault 合约]
    Vault -->|更新| Balance[balances mapping]
    Balance -->|记录| UserBalance[用户余额]
    
    Operator[Operator] -->|充值| Vault
    Vault -->|更新| Balance
    
    User -->|提现| Vault
    Vault -->|检查| Balance
    Balance -->|验证| UserBalance
    Vault -->|转账| User
    
    Operator -->|转账| Vault
    Vault -->|检查| Balance
    Balance -->|验证| UserBalance
    Vault -->|转账| Recipient[接收地址]
    
    Token[ERC20 代币] -->|实际余额| Vault
    Balance -->|内部账本| Vault
    
    style User fill:#e1f5ff
    style Operator fill:#fff9c4
    style Vault fill:#c8e6c9
    style Balance fill:#f3e5f5
```

---

## 权限控制流程图

```mermaid
flowchart TD
    Start([函数调用]) --> CheckPaused{合约暂停?}
    CheckPaused -->|是| BlockAll[阻止所有操作]
    CheckPaused -->|否| CheckFunction{函数类型}
    
    CheckFunction -->|用户函数| AllowUser[允许: deposit/withdraw]
    CheckFunction -->|Operator 函数| CheckOperator{检查 Operator}
    CheckFunction -->|多签函数| CheckOwner{检查 Owner}
    
    CheckOperator -->|是| AllowOperator[允许: operatorDeposit/operatorTransfer]
    CheckOperator -->|否| RejectOperator[拒绝: 不是 Operator]
    
    CheckOwner -->|是| AllowOwner[允许: submitProposal/confirmProposal]
    CheckOwner -->|否| RejectOwner[拒绝: 不是 Owner]
    
    AllowUser --> Execute[执行操作]
    AllowOperator --> Execute
    AllowOwner --> Execute
    
    BlockAll --> End([结束])
    RejectOperator --> End
    RejectOwner --> End
    Execute --> End
    
    style Start fill:#e1f5ff
    style Execute fill:#c8e6c9
    style BlockAll fill:#ffcdd2
    style RejectOperator fill:#ffcdd2
    style RejectOwner fill:#ffcdd2
```

---

## 错误处理流程图

```mermaid
flowchart TD
    Start([操作开始]) --> Try[尝试执行]
    Try --> Check{检查条件}
    
    Check -->|通过| Execute[执行操作]
    Check -->|失败| ErrorType{错误类型}
    
    ErrorType -->|参数错误| ParamError[参数错误回退]
    ErrorType -->|权限错误| PermError[权限错误回退]
    ErrorType -->|状态错误| StateError[状态错误回退]
    ErrorType -->|余额错误| BalanceError[余额错误回退]
    ErrorType -->|重复错误| DuplicateError[重复操作回退]
    
    ParamError --> Revert[回退交易]
    PermError --> Revert
    StateError --> Revert
    BalanceError --> Revert
    DuplicateError --> Revert
    
    Execute --> Success[操作成功]
    Revert --> End([结束])
    Success --> End
    
    style Start fill:#e1f5ff
    style Success fill:#c8e6c9
    style Revert fill:#ffcdd2
```

---

## 总结

### 核心设计原则

1. **Checks → Effects → Interactions**
   - 先检查条件
   - 再更新状态
   - 最后进行外部交互

2. **防重入保护**
   - 所有涉及转账的函数都使用 `nonReentrant`
   - 确保状态更新在外部调用之前

3. **防重复机制**
   - 用户充值使用 `depositId`
   - Operator 操作使用 `opId`
   - 所有 ID 只能使用一次

4. **多签控制**
   - 关键操作必须通过多签
   - N-of-M 机制确保安全性
   - 自动执行机制提高效率

5. **状态管理**
   - 暂停/恢复机制
   - 权限分级管理
   - 余额一致性保证

### 关键检查点

- ✅ 合约暂停状态检查
- ✅ 金额有效性检查
- ✅ 余额充足性检查
- ✅ 权限验证
- ✅ 重复操作检查
- ✅ 重入攻击防护
- ✅ 地址有效性检查

---

## 流程图说明

本文档使用 Mermaid 语法绘制流程图。如果您的 Markdown 查看器不支持 Mermaid，可以使用以下工具查看：

1. **在线查看器**: https://mermaid.live/
2. **VS Code 插件**: Markdown Preview Mermaid Support
3. **GitHub**: GitHub 原生支持 Mermaid 图表

---

## 相关文档

- [README.md](./README.md) - 合约功能说明
- [DEPLOYMENT.md](./DEPLOYMENT.md) - 部署指南
- [TEST_REPORT.md](./TEST_REPORT.md) - 测试报告
