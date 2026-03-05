#!/bin/bash

# Operator 充值脚本 - 简化版
# 功能：Operator 为用户充值代币到合约

echo "=========================================="
echo "UserVault Operator 充值脚本"
echo "=========================================="

# ============ 配置参数 ============
VAULT_CONTRACT="0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E"
TOKEN_CONTRACT="0x76CeE3E0FDF715F50B15Ca83c0ed8C454c7F88A3"
OPERATOR_PRIVATE_KEY="ae4a4050afb424fd7fb75518ed89dfe4caf300aed49e5b7976036fc4b9da3a97"
USER_ADDRESS="0x22ae03eccb791e547478f50c584c58a3d342796f"
RPC_URL="https://data-seed-prebsc-1-s1.binance.org:8545"

# 充值金额：30 个 token（假设 18 位小数）
DEPOSIT_AMOUNT="30000000000000000000"  # 30 * 10^18

# 生成唯一的 opId
OP_ID=$(cast keccak256 $(echo -n "$(date +%s)$RANDOM" | xxd -p))

echo "合约地址: $VAULT_CONTRACT"
echo "用户地址: $USER_ADDRESS"
echo "充值金额: 30 tokens"
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

# 检查 Operator Token 余额
OPERATOR_BALANCE=$(cast call $TOKEN_CONTRACT "balanceOf(address)(uint256)" $OPERATOR_ADDRESS --rpc-url $RPC_URL 2>/dev/null)
echo "Operator Token 余额: $OPERATOR_BALANCE wei"
echo ""

# 检查授权额度
ALLOWANCE=$(cast call $TOKEN_CONTRACT "allowance(address,address)(uint256)" $OPERATOR_ADDRESS $VAULT_CONTRACT --rpc-url $RPC_URL 2>/dev/null)
ALLOWANCE_DEC=$(cast --to-dec $ALLOWANCE 2>/dev/null || echo "0")
DEPOSIT_AMOUNT_DEC=$(cast --to-dec $DEPOSIT_AMOUNT 2>/dev/null || echo "0")

# 授权（如果需要）
if [ "$ALLOWANCE_DEC" -lt "$DEPOSIT_AMOUNT_DEC" ]; then
    echo "授权合约使用代币..."
    cast send $TOKEN_CONTRACT \
        "approve(address,uint256)" \
        $VAULT_CONTRACT $DEPOSIT_AMOUNT \
        --private-key $OPERATOR_PRIVATE_KEY \
        --rpc-url $RPC_URL \
        --legacy
    
    echo ""
    echo "等待授权确认..."
    sleep 5
else
    echo "✅ 授权额度充足"
    echo ""
fi

# 执行充值
echo "正在执行充值..."
DEPOSIT_TX=$(cast send $VAULT_CONTRACT \
    "operatorDeposit(address,uint256,bytes32)" \
    $USER_ADDRESS \
    $DEPOSIT_AMOUNT \
    $OP_ID \
    --private-key $OPERATOR_PRIVATE_KEY \
    --rpc-url $RPC_URL \
    --legacy \
    --json \
    2>&1)

if [ $? -ne 0 ]; then
    echo "❌ 充值失败: $DEPOSIT_TX"
    exit 1
fi

# 提取交易哈希
TX_HASH=$(echo "$DEPOSIT_TX" | jq -r '.transactionHash' 2>/dev/null)
if [ -z "$TX_HASH" ] || [ "$TX_HASH" == "null" ]; then
    TX_HASH=$(echo "$DEPOSIT_TX" | grep -oE '0x[a-fA-F0-9]{64}' | head -1)
fi

echo "✅ 充值成功！"
if [ -n "$TX_HASH" ] && [ "$TX_HASH" != "null" ]; then
    echo "交易哈希: $TX_HASH"
    echo "查看: https://testnet.bscscan.com/tx/$TX_HASH"
fi

echo ""
echo "等待确认..."
sleep 5

# 验证
echo "验证充值结果..."
USER_BALANCE=$(cast call $VAULT_CONTRACT "balances(address)(uint256)" $USER_ADDRESS --rpc-url $RPC_URL 2>/dev/null)
echo "用户在合约中的余额: $USER_BALANCE wei"

CONTRACT_BALANCE=$(cast call $TOKEN_CONTRACT "balanceOf(address)(uint256)" $VAULT_CONTRACT --rpc-url $RPC_URL 2>/dev/null)
echo "合约 Token 余额: $CONTRACT_BALANCE wei"

echo ""
echo "=========================================="
echo "充值完成！"
echo "=========================================="
