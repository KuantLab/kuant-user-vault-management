#!/bin/bash

# 提取 ABI 脚本
# 功能：从编译后的 JSON 文件中提取 ABI

echo "提取 UserVault ABI..."

# 创建 abis 目录
mkdir -p abis

# 方法 1: 使用 jq（如果已安装）
if command -v jq &> /dev/null; then
    echo "使用 jq 提取 ABI..."
    jq '.abi' out/UserVault.sol/UserVault.json > abis/UserVault.json
    if [ $? -eq 0 ]; then
        echo "✅ ABI 已提取到 abis/UserVault.json"
        exit 0
    fi
fi

# 方法 2: 使用 Python
if command -v python3 &> /dev/null; then
    echo "使用 Python 提取 ABI..."
    python3 << 'EOF'
import json
import sys

try:
    with open('out/UserVault.sol/UserVault.json', 'r') as f:
        data = json.load(f)
    
    with open('abis/UserVault.json', 'w') as f:
        json.dump(data['abi'], f, indent=2)
    
    print("✅ ABI 已提取到 abis/UserVault.json")
    sys.exit(0)
except Exception as e:
    print(f"❌ 提取失败: {e}")
    sys.exit(1)
EOF
    if [ $? -eq 0 ]; then
        exit 0
    fi
fi

# 方法 3: 使用 node（如果已安装）
if command -v node &> /dev/null; then
    echo "使用 Node.js 提取 ABI..."
    node << 'EOF'
const fs = require('fs');
try {
    const data = JSON.parse(fs.readFileSync('out/UserVault.sol/UserVault.json', 'utf8'));
    fs.writeFileSync('abis/UserVault.json', JSON.stringify(data.abi, null, 2));
    console.log('✅ ABI 已提取到 abis/UserVault.json');
    process.exit(0);
} catch (e) {
    console.error('❌ 提取失败:', e.message);
    process.exit(1);
}
EOF
    if [ $? -eq 0 ]; then
        exit 0
    fi
fi

echo "❌ 无法提取 ABI，请安装 jq、python3 或 node"
exit 1
