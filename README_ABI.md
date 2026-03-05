# UserVault ABI 文件生成指南

## 快速生成

### 方法一：使用脚本（最简单）

```bash
cd /Users/quanligao/project/contract/kuant-user-vault-management
./scripts/get_abi.sh
```

或者：

```bash
./generate_abi.sh
```

### 方法二：手动提取

#### 步骤 1: 编译合约

```bash
forge build
```

#### 步骤 2: 提取 ABI

**使用 jq（推荐）:**

```bash
mkdir -p abis
jq '.abi' out/UserVault.sol/UserVault.json > abis/UserVault.json
```

**使用 Python:**

```bash
mkdir -p abis
python3 << 'EOF'
import json
with open('out/UserVault.sol/UserVault.json', 'r') as f:
    data = json.load(f)
with open('abis/UserVault.json', 'w') as f:
    json.dump(data['abi'], f, indent=2)
print('✅ ABI 已生成')
EOF
```

**使用 Node.js:**

```bash
mkdir -p abis
node -e "
const fs = require('fs');
const data = JSON.parse(fs.readFileSync('out/UserVault.sol/UserVault.json', 'utf8'));
fs.writeFileSync('abis/UserVault.json', JSON.stringify(data.abi, null, 2));
console.log('✅ ABI 已生成');
"
```

## ABI 文件位置

- **完整编译输出**: `out/UserVault.sol/UserVault.json`
- **纯 ABI 文件**: `abis/UserVault.json`（生成后）

## 验证 ABI

```bash
# 检查文件是否存在
ls -lh abis/UserVault.json

# 查看 ABI 结构
cat abis/UserVault.json | jq '.[0]'

# 统计函数数量
cat abis/UserVault.json | jq '[.[] | select(.type == "function")] | length'

# 列出所有函数名
cat abis/UserVault.json | jq -r '.[] | select(.type == "function") | .name'
```

## 使用 ABI

### 在 Web3.js 中使用

```javascript
const abi = require('./abis/UserVault.json');
const contract = new web3.eth.Contract(abi, '0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E');
```

### 在 ethers.js 中使用

```javascript
const abi = require('./abis/UserVault.json');
const contract = new ethers.Contract(
    '0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E',
    abi,
    signer
);
```

### 在 cast 命令中使用

```bash
cast call 0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E \
    "balances(address)(uint256)" \
    0x22ae03eccb791e547478f50c584c58a3d342796f \
    --abi abis/UserVault.json \
    --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545
```

## 安装工具

### macOS

```bash
# 安装 jq
brew install jq
```

### Ubuntu/Debian

```bash
# 安装 jq
sudo apt-get install jq
```

## 常见问题

### Q1: 编译失败

**A:** 确保合约代码没有错误，所有依赖都已安装。

### Q2: 找不到编译文件

**A:** 运行 `forge build` 先编译合约。

### Q3: 提取工具未安装

**A:** 安装 jq、Python 3 或 Node.js 中的任意一个。
