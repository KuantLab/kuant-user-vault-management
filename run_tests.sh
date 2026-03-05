#!/bin/bash

# 测试运行脚本
cd "$(dirname "$0")"

echo "=========================================="
echo "UserVault 合约测试报告"
echo "=========================================="
echo ""

echo "1. 清理构建缓存..."
forge clean

echo ""
echo "2. 编译合约..."
if forge build 2>&1; then
    echo "✓ 编译成功"
else
    echo "✗ 编译失败"
    exit 1
fi

echo ""
echo "3. 运行测试..."
echo ""

# 运行测试并捕获输出
TEST_OUTPUT=$(forge test -vv 2>&1)
TEST_EXIT_CODE=$?

echo "$TEST_OUTPUT"

echo ""
echo "=========================================="
if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo "✓ 所有测试通过"
else
    echo "✗ 部分测试失败"
fi
echo "=========================================="

exit $TEST_EXIT_CODE
