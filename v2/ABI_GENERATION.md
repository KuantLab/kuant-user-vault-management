# ABI 文件生成指南

## 方法一：使用 Forge 编译后提取（推荐）

### 步骤 1: 编译合约

```bash
cd /Users/quanligao/project/contract/kuant-user-vault-management
forge build
```

### 步骤 2: 提取 ABI

编译成功后，ABI 文件位于：`out/UserVault.sol/UserVault.json`

#### 使用 jq 提取（推荐）

```bash
mkdir -p abis
jq '.abi' out/UserVault.sol/UserVault.json > abis/UserVault.json
```

#### 使用 Python 提取

```bash
mkdir -p abis
python3 << 'EOF'
import json
with open('out/UserVault.sol/UserVault.json', 'r') as f:
    data = json.load(f)
with open('abis/UserVault.json', 'w') as f:
    json.dump(data['abi'], f, indent=2)
print('✅ ABI 已提取到 abis/UserVault.json')
EOF
```

#### 使用 Node.js 提取

```bash
mkdir -p abis
node -e "
const fs = require('fs');
const data = JSON.parse(fs.readFileSync('out/UserVault.sol/UserVault.json', 'utf8'));
fs.writeFileSync('abis/UserVault.json', JSON.stringify(data.abi, null, 2));
console.log('✅ ABI 已提取到 abis/UserVault.json');
"
```

### 步骤 3: 使用生成脚本

```bash
./generate_abi.sh
```

## 方法二：使用 solc 直接生成

```bash
solc --abi src/UserVault.sol --base-path . --include-path lib -o abis/
```

## 方法三：使用 cast 命令

```bash
cast abi src/UserVault.sol > abis/UserVault.json
```

## ABI 文件位置

- **完整编译输出**: `out/UserVault.sol/UserVault.json`（包含 ABI、字节码等）
- **纯 ABI 文件**: `abis/UserVault.json`（仅包含 ABI）

## 验证 ABI

```bash
# 检查 ABI 文件格式
cat abis/UserVault.json | jq '.[0]'  # 查看第一个函数/事件

# 检查函数数量
cat abis/UserVault.json | jq 'length'

# 查看所有函数
cat abis/UserVault.json | jq '.[] | select(.type == "function") | .name'
```

## 使用 ABI

### 在 Web3 应用中使用

```javascript
const abi = require('./abis/UserVault.json');
const contract = new web3.eth.Contract(abi, contractAddress);
```

### 在 ethers.js 中使用

```javascript
const abi = require('./abis/UserVault.json');
const contract = new ethers.Contract(contractAddress, abi, signer);
```

### 在 cast 命令中使用

```bash
cast call <CONTRACT_ADDRESS> "functionName(...)" --abi abis/UserVault.json
```

## 常见问题

### Q1: 编译失败

**A:** 检查合约代码是否有错误，确保所有依赖都已安装。

### Q2: 无法提取 ABI

**A:** 安装 jq、Python 3 或 Node.js 中的任意一个工具。

### Q3: ABI 文件格式错误

**A:** 确保 ABI 是有效的 JSON 数组格式。

## 安装工具

### macOS

```bash
# 安装 jq
brew install jq

# Python 3 通常已预装
# Node.js
brew install node
```

### Ubuntu/Debian

```bash
# 安装 jq
sudo apt-get install jq

# Python 3
sudo apt-get install python3

# Node.js
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs
```
