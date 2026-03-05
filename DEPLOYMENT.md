# UserVault 合约部署指南

## 部署前准备

### 1. 环境要求

- Foundry 已安装并配置
- 部署账户有足够的 ETH 支付 Gas 费
- 已准备好 ERC20 代币地址和 Owner 地址列表

### 2. 配置参数

部署需要以下参数：

- **TOKEN_ADDRESS**: ERC20 代币地址（如 USDC）
- **OWNERS**: Owner 地址数组（至少 1 个）
- **REQUIRED_CONFIRMATIONS**: 最少确认数（必须 <= owners.length）

## 部署方式

### 方式一：使用简化部署脚本（推荐）

简化部署脚本 `DeployUserVaultSimple.s.sol` 适合快速部署，参数直接在脚本中配置。

#### 步骤 1：修改部署参数

编辑 `script/DeployUserVaultSimple.s.sol`，修改以下参数：

```solidity
// 1. 设置 ERC20 代币地址
address tokenAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC 主网

// 2. 设置 Owner 地址
address[] memory owners = new address[](3);
owners[0] = 0x1111111111111111111111111111111111111111; // Owner 1
owners[1] = 0x2222222222222222222222222222222222222222; // Owner 2
owners[2] = 0x3333333333333333333333333333333333333333; // Owner 3

// 3. 设置最少确认数
uint256 requiredConfirmations = 2; // 2-of-3 多签
```

#### 步骤 2：执行部署

**本地测试网（Anvil）:**

```bash
# 启动本地节点
anvil

# 在另一个终端部署
forge script script/DeployUserVaultSimple.s.sol:DeployUserVaultSimple \
    --rpc-url http://localhost:8545 \
    --private-key <your_private_key> \
    --broadcast
```

**Sepolia 测试网:**

```bash
forge script script/DeployUserVaultSimple.s.sol:DeployUserVaultSimple \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY
```

**主网:**

```bash
forge script script/DeployUserVaultSimple.s.sol:DeployUserVaultSimple \
    --rpc-url $MAINNET_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --slow
```

### 方式二：使用环境变量部署

使用完整版部署脚本 `DeployUserVault.s.sol`，通过环境变量配置参数。

#### 步骤 1：创建 .env 文件

```bash
# .env 文件
TOKEN_ADDRESS=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
OWNERS=0x1111111111111111111111111111111111111111,0x2222222222222222222222222222222222222222,0x3333333333333333333333333333333333333333
REQUIRED_CONFIRMATIONS=2
```

#### 步骤 2：执行部署

```bash
# 加载环境变量并部署
source .env
forge script script/DeployUserVault.s.sol:DeployUserVault \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast
```

### 方式三：使用命令行参数

使用 `deploy()` 函数直接传递参数（需要修改脚本支持）。

## 部署示例

### 示例 1：3-of-3 多签部署

```solidity
address[] memory owners = new address[](3);
owners[0] = 0xOwner1;
owners[1] = 0xOwner2;
owners[2] = 0xOwner3;
uint256 requiredConfirmations = 2; // 需要 2 个确认
```

### 示例 2：5-of-5 多签部署

```solidity
address[] memory owners = new address[](5);
owners[0] = 0xOwner1;
owners[1] = 0xOwner2;
owners[2] = 0xOwner3;
owners[3] = 0xOwner4;
owners[4] = 0xOwner5;
uint256 requiredConfirmations = 3; // 需要 3 个确认
```

## 部署后验证

### 1. 检查合约地址

部署成功后，脚本会输出合约地址：

```
Contract Address: 0x...
```

### 2. 验证合约状态

使用 cast 命令验证部署：

```bash
# 检查代币地址
cast call <CONTRACT_ADDRESS> "token()" --rpc-url $RPC_URL

# 检查 Owner 数量
cast call <CONTRACT_ADDRESS> "getOwnerCount()" --rpc-url $RPC_URL

# 检查最少确认数
cast call <CONTRACT_ADDRESS> "requiredConfirmations()" --rpc-url $RPC_URL
```

### 3. 在区块浏览器验证

如果使用了 `--verify` 参数，合约代码会在 Etherscan 上自动验证。

访问：`https://etherscan.io/address/<CONTRACT_ADDRESS>`

## 常见问题

### Q1: 部署失败，提示 "Invalid token address"

**A:** 检查 TOKEN_ADDRESS 是否正确，确保是有效的 ERC20 代币地址。

### Q2: 部署失败，提示 "Owners array cannot be empty"

**A:** 确保至少设置了一个 Owner 地址。

### Q3: 部署失败，提示 "Invalid required confirmations"

**A:** 确保 `requiredConfirmations` 大于 0 且小于等于 `owners.length`。

### Q4: 部署失败，提示 "Duplicate owner address"

**A:** 检查 Owner 地址列表中是否有重复的地址。

### Q5: 如何修改部署参数？

**A:** 编辑 `DeployUserVaultSimple.s.sol` 文件中的参数，或使用环境变量。

## 安全建议

1. **私钥安全**
   - 永远不要将私钥提交到代码仓库
   - 使用环境变量或密钥管理工具
   - 生产环境使用硬件钱包或多签钱包

2. **参数验证**
   - 部署前仔细检查所有参数
   - 确认 Owner 地址正确
   - 确认多签配置合理

3. **测试部署**
   - 先在测试网部署并测试
   - 验证所有功能正常
   - 再进行主网部署

4. **合约验证**
   - 使用 `--verify` 参数在 Etherscan 上验证合约
   - 方便用户查看和审计合约代码

## 部署脚本说明

### DeployUserVaultSimple.s.sol

简化版部署脚本，适合快速部署：
- 参数直接在脚本中配置
- 支持环境变量覆盖
- 适合大多数部署场景

### DeployUserVault.s.sol

完整版部署脚本，支持：
- 环境变量配置
- 命令行参数
- 更灵活的配置方式

## 下一步

部署完成后，建议：

1. **添加第一个 Operator**
   - 使用多签提交添加 Operator 提案
   - 等待足够的确认
   - 执行提案

2. **测试基本功能**
   - 测试用户充值
   - 测试用户提现
   - 测试 Operator 功能

3. **监控合约**
   - 设置事件监控
   - 定期检查合约状态
   - 关注异常交易

## 相关文档

- [README.md](./README.md) - 合约功能说明
- [TEST_REPORT.md](./TEST_REPORT.md) - 测试报告
