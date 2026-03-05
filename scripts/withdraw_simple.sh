#!/bin/bash

# 用户提现脚本 - 简化版
# 功能：用户从合约中提现代币

echo "=========================================="
echo "UserVault 用户提现脚本"
echo "=========================================="

# ============ 配置参数 ============
VAULT_CONTRACT="0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E"
TOKEN_CONTRACT="0x76CeE3E0FDF715F50B15Ca83c0ed8C454c7F88A3"
USER_PRIVATE_KEY="39b36efe563e1d284dcc5cfe7c5b00207e8fef1bd41d343ee5c1cb0dc805a668"
RPC_URL="https://data-seed-prebsc-1-s1.binance.org:8545"

# 提现金额：30 个 token（假设 18 位小数）
WITHDRAW_AMOUNT="30000000000000000000"  # 30 * 10^18

echo "合约地址: $VAULT_CONTRACT"
echo "提现金额: 30 tokens"
echo ""

# 获取用户地址
USER_ADDRESS=$(cast wallet address $USER_PRIVATE_KEY)
echo "用户地址: $USER_ADDRESS"
echo ""

# 检查用户余额
USER_BALANCE=$(cast call $VAULT_CONTRACT "balances(address)(uint256)" $USER_ADDRESS --rpc-url $RPC_URL 2>/dev/null)
echo "用户在合约中的余额: $USER_BALANCE wei"
echo ""

# 检查合约状态
IS_PAUSED=$(cast call $VAULT_CONTRACT "paused()(bool)" --rpc-url $RPC_URL 2>/dev/null)
if [ "$IS_PAUSED" == "true" ]; then
    echo "❌ 合约已暂停"
    exit 1
fi

# 执行提现
echo "正在执行提现..."
WITHDRAW_TX=$(cast send $VAULT_CONTRACT \
    "withdraw(uint256)" \
    $WITHDRAW_AMOUNT \
    --private-key $USER_PRIVATE_KEY \
    --rpc-url $RPC_URL \
    --legacy \
    --json \
    2>&1)

if [ $? -ne 0 ]; then
    echo "❌ 提现失败: $WITHDRAW_TX"
    exit 1
fi

# 提取交易哈希
TX_HASH=$(echo "$WITHDRAW_TX" | jq -r '.transactionHash' 2>/dev/null)
if [ -z "$TX_HASH" ] || [ "$TX_HASH" == "null" ]; then
    TX_HASH=$(echo "$WITHDRAW_TX" | grep -oE '0x[a-fA-F0-9]{64}' | head -1)
fi

echo "✅ 提现成功！"
if [ -n "$TX_HASH" ] && [ "$TX_HASH" != "null" ]; then
    echo "交易哈希: $TX_HASH"
    echo "查看: https://testnet.bscscan.com/tx/$TX_HASH"
fi

echo ""
echo "等待确认..."
sleep 5

# 验证
echo "验证提现结果..."
USER_BALANCE_NEW=$(cast call $VAULT_CONTRACT "balances(address)(uint256)" $USER_ADDRESS --rpc-url $RPC_URL 2>/dev/null)
echo "用户在合约中的新余额: $USER_BALANCE_NEW wei"

USER_TOKEN_BALANCE=$(cast call $TOKEN_CONTRACT "balanceOf(address)(uint256)" $USER_ADDRESS --rpc-url $RPC_URL 2>/dev/null)
echo "用户钱包 Token 余额: $USER_TOKEN_BALANCE wei"

echo ""
echo "=========================================="
echo "提现完成！"
echo "=========================================="
