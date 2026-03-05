#!/bin/bash

# 生成 ABI 文件脚本

echo "=========================================="
echo "生成 UserVault ABI 文件"
echo "=========================================="

# 确保已编译
echo "步骤 1: 编译合约..."
forge build --force > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "❌ 编译失败，请检查合约代码"
    exit 1
fi

echo "✅ 编译成功"
echo ""

# 创建 abis 目录
mkdir -p abis

# 提取 ABI
echo "步骤 2: 提取 ABI..."

# 尝试使用 jq
if command -v jq &> /dev/null; then
    jq '.abi' out/UserVault.sol/UserVault.json > abis/UserVault.json
    if [ $? -eq 0 ]; then
        echo "✅ 使用 jq 提取 ABI 成功"
        echo "   ABI 文件: abis/UserVault.json"
        exit 0
    fi
fi

# 尝试使用 Python
if command -v python3 &> /dev/null; then
    python3 -c "
import json
with open('out/UserVault.sol/UserVault.json', 'r') as f:
    data = json.load(f)
with open('abis/UserVault.json', 'w') as f:
    json.dump(data['abi'], f, indent=2)
print('✅ 使用 Python 提取 ABI 成功')
print('   ABI 文件: abis/UserVault.json')
" 2>/dev/null
    if [ $? -eq 0 ]; then
        exit 0
    fi
fi

# 尝试使用 Node.js
if command -v node &> /dev/null; then
    node -e "
const fs = require('fs');
const data = JSON.parse(fs.readFileSync('out/UserVault.sol/UserVault.json', 'utf8'));
fs.writeFileSync('abis/UserVault.json', JSON.stringify(data.abi, null, 2));
console.log('✅ 使用 Node.js 提取 ABI 成功');
console.log('   ABI 文件: abis/UserVault.json');
" 2>/dev/null
    if [ $? -eq 0 ]; then
        exit 0
    fi
fi

echo "❌ 无法提取 ABI"
echo "   请安装以下工具之一："
echo "   - jq: brew install jq (macOS) 或 apt-get install jq (Linux)"
echo "   - Python 3"
echo "   - Node.js"
echo ""
echo "   或者手动从以下文件提取 ABI："
echo "   out/UserVault.sol/UserVault.json"
exit 1
