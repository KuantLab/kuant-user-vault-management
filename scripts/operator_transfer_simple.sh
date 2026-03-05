#!/bin/bash

# Operator 转账脚本 - 简化版
# 功能：Operator 将用户的资金转移到指定地址

echo "=========================================="
echo "UserVault Operator 转账脚本"
echo "=========================================="

# ============ 配置参数 ============
VAULT_CONTRACT="0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E"
TOKEN_CONTRACT="0x76CeE3E0FDF715F50B15Ca83c0ed8C454c7F88A3"
OPERATOR_PRIVATE_KEY="ae4a4050afb424fd7fb75518ed89dfe4caf300aed49e5b7976036fc4b9da3a97"
USER_ADDRESS="0x22ae03eccb791e547478f50c584c58a3d342796f"
TO_ADDRESS="0x22ae03eccb791e547478f50c584c58a3d342796f"
RPC_URL="https://data-seed-prebsc-1-s1.binance.org:8545"

# 转账金额：50 个 token（假设 18 位小数）
TRANSFER_AMOUNT="50000000000000000000"  # 50 * 10^18

# 生成唯一的 opId
OP_ID=$(cast keccak256 $(echo -n "$(date +%s)$RANDOM" | xxd -p))

echo "合约地址: $VAULT_CONTRACT"
echo "用户地址: $USER_ADDRESS"
echo "接收地址: $TO_ADDRESS"
echo "转账金额: 50 tokens"
echo "Op ID: $OP_ID"
echo ""

# 检查 Operator 权限
OPERATOR_ADDRESS=$(cast wallet address $OPERATOR_PRIVATE_KEY)
IS_OPERATOR=$(cast call $VAULT_CONTRACT "operators(address)(bool)" $OPERATOR_ADDRESS --rpc-url $RPC_URL 2>/dev/null)

if [ "$IS_OPERATOR" != "true" ]; then
    echo "❌ 不是 Operator"
    exit 1
fi

echo "✅ Operator 权限验证通过"
echo ""

# 检查用户余额
USER_BALANCE=$(cast call $VAULT_CONTRACT "balances(address)(uint256)" $USER_ADDRESS --rpc-url $RPC_URL 2>/dev/null)
echo "用户在合约中的余额: $USER_BALANCE wei"
echo ""

# 执行转账
echo "正在执行转账..."
TRANSFER_TX=$(cast send $VAULT_CONTRACT \
    "operatorTransfer(address,address,uint256,bytes32)" \
    $USER_ADDRESS \
    $TO_ADDRESS \
    $TRANSFER_AMOUNT \
    $OP_ID \
    --private-key $OPERATOR_PRIVATE_KEY \
    --rpc-url $RPC_URL \
    --legacy \
    --json \
    2>&1)

if [ $? -ne 0 ]; then
    echo "❌ 转账失败: $TRANSFER_TX"
    exit 1
fi

# 提取交易哈希
TX_HASH=$(echo "$TRANSFER_TX" | jq -r '.transactionHash' 2>/dev/null)
if [ -z "$TX_HASH" ] || [ "$TX_HASH" == "null" ]; then
    TX_HASH=$(echo "$TRANSFER_TX" | grep -oE '0x[a-fA-F0-9]{64}' | head -1)
fi

echo "✅ 转账成功！"
if [ -n "$TX_HASH" ] && [ "$TX_HASH" != "null" ]; then
    echo "交易哈希: $TX_HASH"
    echo "查看: https://testnet.bscscan.com/tx/$TX_HASH"
fi

echo ""
echo "等待确认..."
sleep 5

# 验证
echo "验证转账结果..."
USER_BALANCE_NEW=$(cast call $VAULT_CONTRACT "balances(address)(uint256)" $USER_ADDRESS --rpc-url $RPC_URL 2>/dev/null)
echo "用户新余额: $USER_BALANCE_NEW wei"

TO_BALANCE=$(cast call $TOKEN_CONTRACT "balanceOf(address)(uint256)" $TO_ADDRESS --rpc-url $RPC_URL 2>/dev/null)
echo "接收地址 Token 余额: $TO_BALANCE wei"

echo ""
echo "=========================================="
echo "转账完成！"
echo "=========================================="
