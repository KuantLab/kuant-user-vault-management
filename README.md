# Kuant 用户资金托管合约

## 📚 文档导航

- [README.md](./README.md) - 合约功能说明和使用指南（当前文档）
- [FLOWCHARTS.md](./FLOWCHARTS.md) - **详细流程图**（推荐查看）
- [DEPLOYMENT.md](./DEPLOYMENT.md) - 部署指南
- [TEST_REPORT.md](./TEST_REPORT.md) - 测试报告

## 项目简介

这是一个基于 Solidity ^0.8.x 开发的用户资金托管智能合约，支持 ERC20 代币（如 USDC）的托管管理。合约具备防重复充值机制、多签 Owner 权限控制和 Operator 操作员体系，确保资金安全和操作可追溯。

## 核心功能

### 1. ERC20 资产支持

- **功能说明**：合约仅支持指定的 ERC20 代币（如 USDC）
- **实现方式**：ERC20 地址在构造函数中传入并保存为不可变变量
- **安全机制**：使用 IERC20 接口 + 安全转账函数进行代币交互

### 2. 用户余额管理

- **功能说明**：使用内部账本维护每个用户的代币余额
- **数据结构**：`mapping(address => uint256) balances` - 用户地址到余额的映射
- **一致性保证**：合约 ERC20 实际余额与内部账本逻辑保持一致

### 3. 防重复充值机制

#### 3.1 用户充值防重

- **功能说明**：防止用户重复充值，避免资金重复计算
- **实现方式**：
  - 用户充值需提供唯一的 `depositId`（bytes32 类型）
  - 合约维护 `mapping(bytes32 => bool) usedDepositIds` 记录已使用的充值 ID
  - 每次充值前校验 `depositId` 未使用，成功后立即标记为已使用

#### 3.2 操作员操作防重

- **功能说明**：防止操作员重复执行操作，避免后台重复提交或脚本重放
- **实现方式**：
  - 所有 Operator 操作必须提供唯一的 `opId`（bytes32 类型）
  - 合约维护 `mapping(bytes32 => bool) usedOpIds` 记录已使用的操作 ID
  - 每次操作前校验 `opId` 唯一性

### 4. 用户功能

#### 4.1 deposit（充值）

- **函数签名**：`deposit(uint256 amount, bytes32 depositId)`
- **功能说明**：用户向合约充值 ERC20 代币
- **参数说明**：
  - `amount`：充值金额（必须大于 0）
  - `depositId`：唯一充值 ID（用于防重，不能重复使用）
- **前置条件**：
  - 用户需提前调用 ERC20 代币的 `approve` 函数，授权合约使用代币
  - `depositId` 必须未被使用
  - 合约未暂停
- **返回值**：无
- **事件**：`Deposit(address indexed user, uint256 amount, bytes32 depositId)`

#### 4.2 withdraw（提现）

- **函数签名**：`withdraw(uint256 amount)`
- **功能说明**：用户从合约提取 ERC20 代币
- **参数说明**：
  - `amount`：提现金额（必须大于 0）
- **前置条件**：
  - 用户余额必须大于等于提现金额
  - 合约未暂停
- **返回值**：无
- **安全机制**：使用 `nonReentrant` 防止重入攻击
- **事件**：`Withdraw(address indexed user, uint256 amount)`

### 5. Operator 权限体系

#### 5.1 权限说明

- **功能说明**：Operator 是经过多签授权的操作员，可以代表用户进行充值或转账操作
- **权限范围**：
  - 为用户充值（operatorDeposit）
  - 转移用户资金（operatorTransfer）

#### 5.2 operatorDeposit（操作员充值）

- **函数签名**：`operatorDeposit(address user, uint256 amount, bytes32 opId)`
- **功能说明**：Operator 为用户充值代币
- **参数说明**：
  - `user`：用户地址（不能为零地址）
  - `amount`：充值金额（必须大于 0）
  - `opId`：唯一操作 ID（用于防重）
- **前置条件**：
  - 调用者必须是 Operator
  - `opId` 必须未被使用
  - 合约未暂停
- **返回值**：无
- **事件**：`OperatorDeposit(address indexed operator, address indexed user, uint256 amount, bytes32 opId)`

#### 5.3 operatorTransfer（操作员转账）

- **函数签名**：`operatorTransfer(address user, address to, uint256 amount, bytes32 opId)`
- **功能说明**：Operator 将用户的资金转移到指定地址
- **参数说明**：
  - `user`：用户地址（不能为零地址）
  - `to`：接收地址（不能为零地址）
  - `amount`：转移金额（必须大于 0）
  - `opId`：唯一操作 ID（用于防重）
- **前置条件**：
  - 调用者必须是 Operator
  - 用户余额必须大于等于转移金额
  - `opId` 必须未被使用
  - 合约未暂停
- **返回值**：无
- **事件**：`OperatorTransfer(address indexed operator, address indexed user, address indexed to, uint256 amount, bytes32 opId)`

### 6. 多签 Owner（核心功能）

#### 6.1 多签模型

- **功能说明**：合约不使用单一 owner，而是使用 N-of-M 多签机制
- **初始化参数**：
  - `owners[]`：Owner 地址数组（至少 1 个，不能有重复或零地址）
  - `requiredConfirmations`：最少确认数（必须大于 0 且小于等于 owners 数量）

#### 6.2 多签控制的操作

以下操作必须通过多签执行：

1. **添加 Operator**：`ProposalType.AddOperator`
2. **移除 Operator**：`ProposalType.RemoveOperator`
3. **暂停合约**：`ProposalType.Pause`
4. **恢复合约**：`ProposalType.Unpause`

#### 6.3 多签执行流程

1. **提交提案**：`submitProposal(ProposalType proposalType, bytes memory data)`
   - 任何 Owner 可以提交提案
   - 提交者自动确认该提案
   - 返回提案 ID

2. **确认提案**：`confirmProposal(uint256 proposalId)`
   - 其他 Owner 可以确认提案
   - 每个 Owner 只能确认一次
   - 当确认数达到 `requiredConfirmations` 时，自动执行提案

3. **执行提案**：`executeProposal(uint256 proposalId)`
   - 当确认数足够时，可以执行提案
   - 每个提案只能执行一次
   - 执行后提案状态标记为已执行

#### 6.4 多签函数说明

**submitProposal**
- **函数签名**：`submitProposal(ProposalType proposalType, bytes memory data) returns (uint256 proposalId)`
- **参数说明**：
  - `proposalType`：提案类型（AddOperator, RemoveOperator, Pause, Unpause）
  - `data`：编码后的参数数据
    - AddOperator/RemoveOperator：`abi.encode(address operator)`
    - Pause/Unpause：`abi.encode()`（空数据）
- **返回值**：提案 ID
- **事件**：`MultiSigSubmitted(uint256 indexed txId)`

**confirmProposal**
- **函数签名**：`confirmProposal(uint256 proposalId)`
- **参数说明**：
  - `proposalId`：提案 ID
- **前置条件**：
  - 调用者必须是 Owner
  - 提案必须存在且未执行
  - 调用者未确认过该提案
- **返回值**：无
- **事件**：`MultiSigConfirmed(address indexed owner, uint256 indexed txId)`

**executeProposal**
- **函数签名**：`executeProposal(uint256 proposalId)`
- **参数说明**：
  - `proposalId`：提案 ID
- **前置条件**：
  - 提案必须存在且未执行
  - 确认数必须达到 `requiredConfirmations`
- **返回值**：无
- **事件**：`MultiSigExecuted(uint256 indexed txId)`

### 7. 安全性要求

- **Solidity 版本**：^0.8.x（内置溢出检查）
- **重入保护**：使用 `nonReentrant` 修饰符防止重入攻击
- **安全转账**：使用安全转账函数处理 ERC20 代币交互
- **执行顺序**：严格遵循 Checks → Effects → Interactions 模式
- **权限控制**：所有权限操作必须通过多签校验

### 8. 事件（Events）

合约定义了以下事件，用于追踪所有重要操作：

- `Deposit(address indexed user, uint256 amount, bytes32 depositId)` - 用户充值
- `Withdraw(address indexed user, uint256 amount)` - 用户提现
- `OperatorDeposit(address indexed operator, address indexed user, uint256 amount, bytes32 opId)` - 操作员充值
- `OperatorTransfer(address indexed operator, address indexed user, address indexed to, uint256 amount, bytes32 opId)` - 操作员转账
- `MultiSigSubmitted(uint256 indexed txId)` - 多签提案提交
- `MultiSigConfirmed(address indexed owner, uint256 indexed txId)` - 多签提案确认
- `MultiSigExecuted(uint256 indexed txId)` - 多签提案执行
- `OperatorAdded(address indexed operator)` - 添加操作员
- `OperatorRemoved(address indexed operator)` - 移除操作员
- `Paused(address indexed account)` - 合约暂停
- `Unpaused(address indexed account)` - 合约恢复

## 合约部署

### 部署参数

部署合约时需要提供以下参数：

1. **token**：ERC20 代币地址（如 USDC 地址）
2. **owners**：Owner 地址数组（至少 1 个）
3. **requiredConfirmations**：最少确认数（必须 <= owners.length）

### 部署示例

```solidity
// 示例：部署合约
address usdcAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC 主网地址
address[] memory owners = [0xOwner1, 0xOwner2, 0xOwner3];
uint256 requiredConfirmations = 2; // 3-of-3 多签，需要 2 个确认

UserVault vault = new UserVault(usdcAddress, owners, requiredConfirmations);
```

## 使用示例

### 用户充值

```solidity
// 1. 用户先授权合约使用代币
IERC20(usdcAddress).approve(vaultAddress, 1000 * 10**6); // 授权 1000 USDC

// 2. 用户充值
bytes32 depositId = keccak256(abi.encodePacked("unique-deposit-id-123"));
vault.deposit(1000 * 10**6, depositId);
```

### 用户提现

```solidity
// 用户提现 500 USDC
vault.withdraw(500 * 10**6);
```

### 操作员为用户充值

```solidity
// Operator 为用户充值
bytes32 opId = keccak256(abi.encodePacked("operator-deposit-456"));
vault.operatorDeposit(userAddress, 2000 * 10**6, opId);
```

### 多签添加 Operator

```solidity
// 1. Owner1 提交提案
bytes memory data = abi.encode(operatorAddress);
uint256 proposalId = vault.submitProposal(ProposalType.AddOperator, data);

// 2. Owner2 确认提案
vault.confirmProposal(proposalId);

// 3. 如果达到确认数，提案自动执行
// 或者手动执行
vault.executeProposal(proposalId);
```

## 查询函数

合约提供以下查询函数：

- `balances(address user) returns (uint256)` - 查询用户余额
- `usedDepositIds(bytes32 depositId) returns (bool)` - 查询充值 ID 是否已使用
- `usedOpIds(bytes32 opId) returns (bool)` - 查询操作 ID 是否已使用
- `operators(address operator) returns (bool)` - 查询地址是否为 Operator
- `isOwner(address account) returns (bool)` - 查询地址是否为 Owner
- `getOwnerCount() returns (uint256)` - 获取 Owner 数量
- `getOwners() returns (address[])` - 获取所有 Owner 地址
- `getProposalConfirmations(uint256 proposalId) returns (uint256)` - 获取提案确认数
- `hasConfirmed(uint256 proposalId, address owner) returns (bool)` - 查询 Owner 是否已确认提案
- `getContractBalance() returns (uint256)` - 获取合约 ERC20 余额
- `getUserBalance(address user) returns (uint256)` - 获取用户余额

## 项目结构

```
kuant-user-vault-management/
├── src/
│   ├── UserVault.sol          # 主合约文件
│   └── Counter.sol            # 示例合约（可删除）
├── test/
│   └── Counter.t.sol          # 测试文件
├── script/
│   └── Counter.s.sol         # 部署脚本
├── lib/
│   └── forge-std/            # Foundry 标准库
├── foundry.toml              # Foundry 配置文件
└── README.md                 # 本文件
```

## 开发命令

### 编译合约

```shell
forge build
```

### 运行测试

```shell
forge test
```

### 格式化代码

```shell
forge fmt
```

### 部署合约

```shell
forge script script/Deploy.s.sol:DeployScript --rpc-url <your_rpc_url> --private-key <your_private_key> --broadcast
```

## 注意事项

1. **充值 ID 唯一性**：用户充值时必须确保 `depositId` 的唯一性，建议使用时间戳 + 随机数生成
2. **操作 ID 唯一性**：Operator 操作时必须确保 `opId` 的唯一性，建议使用 UUID 或时间戳 + 随机数
3. **授权额度**：用户充值前必须调用 ERC20 代币的 `approve` 函数，授权额度必须大于等于充值金额
4. **多签确认**：多签提案需要达到 `requiredConfirmations` 个确认才能执行
5. **合约暂停**：当合约暂停时，所有用户和 Operator 操作都会被阻止，只有多签可以恢复合约

## 安全建议

1. **审计**：在生产环境部署前，建议进行专业的安全审计
2. **测试**：充分测试所有功能，特别是边界情况和异常情况
3. **多签配置**：合理设置多签的 Owner 数量和确认数，平衡安全性和便利性
4. **监控**：部署后持续监控合约事件，及时发现异常操作
5. **升级机制**：考虑是否需要实现合约升级机制（当前版本不支持）

## 项目改进方向

1. **合约升级**：考虑实现代理模式，支持合约升级
2. **紧急提取**：实现紧急提取功能，允许多签在紧急情况下提取资金
3. **费率机制**：考虑添加手续费机制，支持运营成本
4. **批量操作**：支持批量充值和提现，提高效率
5. **更多代币支持**：考虑支持多种 ERC20 代币
6. **时间锁**：为多签操作添加时间锁，增加安全性

## 许可证

MIT License
