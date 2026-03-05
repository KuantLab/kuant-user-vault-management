# BSC 测试网部署指南

## 部署信息

- **网络**: BSC Testnet (Binance Smart Chain Testnet)
- **Token 地址**: `0x76CeE3E0FDF715F50B15Ca83c0ed8C454c7F88A3`
- **钱包地址**: `0x5ebFeFdE3dcE75EAf436dFc9B02a402714d13C63`
- **Owner 地址**: `0x5ebFeFdE3dcE75EAf436dFc9B02a402714d13C63` (1-of-1 多签)

## 部署前准备

### 1. 检查钱包余额

确保钱包有足够的 BNB 支付 Gas 费（建议至少 0.1 BNB）：

```bash
# 使用 cast 检查余额
cast balance 0x5ebFeFdE3dcE75EAf436dFc9B02a402714d13C63 --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545
```

### 2. 获取测试 BNB

如果余额不足，可以从 BSC 测试网水龙头获取：
- https://testnet.binance.org/faucet-smart
- https://faucet.quicknode.com/binance/bnb-testnet

## 部署方式

### 方式一：使用部署脚本（推荐）

```bash
cd /Users/quanligao/project/contract/kuant-user-vault-management
./deploy_bsc.sh
```

### 方式二：直接使用 Forge 命令

```bash
cd /Users/quanligao/project/contract/kuant-user-vault-management

forge script script/DeployBSC.s.sol:DeployBSC \
    --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 \
    --private-key 6f4058fa7ab22b3c83290a6bca1be7d43ed911d4ffe5f3d1003d413fdfd425c7 \
    --broadcast \
    -vv
```

### 方式三：使用其他 RPC 端点

如果默认 RPC 不可用，可以尝试以下端点：

```bash
# RPC 1
forge script script/DeployBSC.s.sol:DeployBSC \
    --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 \
    --private-key 6f4058fa7ab22b3c83290a6bca1be7d43ed911d4ffe5f3d1003d413fdfd425c7 \
    --broadcast \
    -vv

# RPC 2
forge script script/DeployBSC.s.sol:DeployBSC \
    --rpc-url https://data-seed-prebsc-2-s1.binance.org:8545 \
    --private-key 6f4058fa7ab22b3c83290a6bca1be7d43ed911d4ffe5f3d1003d413fdfd425c7 \
    --broadcast \
    -vv

# RPC 3
forge script script/DeployBSC.s.sol:DeployBSC \
    --rpc-url https://bsc-testnet.public.blastapi.io \
    --private-key 6f4058fa7ab22b3c83290a6bca1be7d43ed911d4ffe5f3d1003d413fdfd425c7 \
    --broadcast \
    -vv

# RPC 4
forge script script/DeployBSC.s.sol:DeployBSC \
    --rpc-url https://bsc-testnet.blockpi.network/v1/rpc/public \
    --private-key 6f4058fa7ab22b3c83290a6bca1be7d43ed911d4ffe5f3d1003d413fdfd425c7 \
    --broadcast \
    -vv
```

## 部署后验证

### 1. 查看部署结果

部署成功后，脚本会输出合约地址，类似：

```
==========================================
Deployment Successful!
==========================================
Contract Address: 0x...
Token Address: 0x76CeE3E0FDF715F50B15Ca83c0ed8C454c7F88A3
Required Confirmations: 1
Owner Count: 1
==========================================
```

### 2. 在 BSCScan 上查看

访问 BSC 测试网浏览器查看合约：
```
https://testnet.bscscan.com/address/<CONTRACT_ADDRESS>
```

### 3. 验证合约状态

使用 cast 命令验证部署：

```bash
# 检查代币地址
cast call <CONTRACT_ADDRESS> "token()" --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545

# 检查 Owner 数量
cast call <CONTRACT_ADDRESS> "getOwnerCount()" --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545

# 检查最少确认数
cast call <CONTRACT_ADDRESS> "requiredConfirmations()" --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545
```

## 常见问题

### Q1: 部署失败，提示 "insufficient funds"

**A:** 钱包余额不足，需要从水龙头获取测试 BNB。

### Q2: 部署失败，提示 "nonce too low"

**A:** 钱包 nonce 不同步，等待一段时间后重试，或使用 `--legacy` 参数。

### Q3: RPC 连接失败

**A:** 尝试使用其他 RPC 端点，或检查网络连接。

### Q4: 如何添加更多 Owner？

**A:** 部署后使用多签功能添加更多 Owner。由于当前是 1-of-1，可以直接执行操作。

## 部署参数说明

- **Token 地址**: `0x76CeE3E0FDF715F50B15Ca83c0ed8C454c7F88A3`
- **Owner**: `0x5ebFeFdE3dcE75EAf436dFc9B02a402714d13C63` (单个 Owner)
- **最少确认数**: 1 (1-of-1 多签)

如果需要修改这些参数，请编辑 `script/DeployBSC.s.sol` 文件。

## 下一步

部署完成后：

1. **记录合约地址** - 保存部署输出的合约地址
2. **验证合约** - 在 BSCScan 上查看合约代码
3. **测试功能** - 测试充值、提现等基本功能
4. **添加 Operator** - 如果需要，使用多签添加 Operator

## 安全提醒

⚠️ **重要**: 
- 私钥已硬编码在部署脚本中，仅用于测试网部署
- 生产环境请使用环境变量或密钥管理工具
- 部署后请妥善保管合约地址和 Owner 私钥
