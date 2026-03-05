#!/bin/bash

# 获取 ABI 脚本
# 功能：从编译后的文件中提取 ABI

set -e

echo "=========================================="
echo "提取 UserVault ABI"
echo "=========================================="

# 创建 abis 目录
mkdir -p abis

# 检查编译文件是否存在
if [ ! -f "out/UserVault.sol/UserVault.json" ]; then
    echo "编译文件不存在，正在编译..."
    forge build
fi

# 检查文件是否存在
if [ ! -f "out/UserVault.sol/UserVault.json" ]; then
    echo "❌ 编译失败或文件不存在"
    exit 1
fi

echo "✅ 找到编译文件"
echo ""

# 方法 1: 使用 jq
if command -v jq &> /dev/null; then
    echo "使用 jq 提取 ABI..."
    jq '.abi' out/UserVault.sol/UserVault.json > abis/UserVault.json
    echo "✅ ABI 已提取到: abis/UserVault.json"
    exit 0
fi

# 方法 2: 使用 Python
if command -v python3 &> /dev/null; then
    echo "使用 Python 提取 ABI..."
    python3 << 'PYTHON_SCRIPT'
import json
import sys

try:
    with open('out/UserVault.sol/UserVault.json', 'r') as f:
        data = json.load(f)
    
    with open('abis/UserVault.json', 'w') as f:
        json.dump(data['abi'], f, indent=2)
    
    print('✅ ABI 已提取到: abis/UserVault.json')
    sys.exit(0)
except Exception as e:
    print(f'❌ 提取失败: {e}')
    sys.exit(1)
PYTHON_SCRIPT
    
    if [ $? -eq 0 ]; then
        exit 0
    fi
fi

# 方法 3: 使用 Node.js
if command -v node &> /dev/null; then
    echo "使用 Node.js 提取 ABI..."
    node << 'NODE_SCRIPT'
const fs = require('fs');
try {
    const data = JSON.parse(fs.readFileSync('out/UserVault.sol/UserVault.json', 'utf8'));
    fs.writeFileSync('abis/UserVault.json', JSON.stringify(data.abi, null, 2));
    console.log('✅ ABI 已提取到: abis/UserVault.json');
    process.exit(0);
} catch (e) {
    console.error('❌ 提取失败:', e.message);
    process.exit(1);
}
NODE_SCRIPT
    
    if [ $? -eq 0 ]; then
        exit 0
    fi
fi

echo "❌ 无法提取 ABI"
echo ""
echo "请安装以下工具之一："
echo "  - jq: brew install jq (macOS) 或 apt-get install jq (Linux)"
echo "  - Python 3 (通常已预装)"
echo "  - Node.js: brew install node (macOS) 或 apt-get install nodejs (Linux)"
echo ""
echo "或者手动从以下文件提取 'abi' 字段："
echo "  out/UserVault.sol/UserVault.json"
exit 1
