#!/bin/bash

# 添加 Operator 脚本 - 简化版（直接使用 cast 命令）
# 功能：通过多签提案添加 Operator

echo "=========================================="
echo "UserVault 添加 Operator 脚本"
echo "=========================================="

# ============ 配置参数 ============
VAULT_CONTRACT="0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E"
OWNER_PRIVATE_KEY="6f4058fa7ab22b3c83290a6bca1be7d43ed911d4ffe5f3d1003d413fdfd425c7"
OPERATOR_ADDRESS="0x07e3aabd2d4d5dcec107ef9555dc0e5ef24f62b3"
RPC_URL="https://data-seed-prebsc-1-s1.binance.org:8545"

echo "合约地址: $VAULT_CONTRACT"
echo "Operator 地址: $OPERATOR_ADDRESS"
echo ""

# 检查 Operator 是否已存在
echo "检查 Operator 状态..."
IS_OPERATOR=$(cast call $VAULT_CONTRACT "operators(address)(bool)" $OPERATOR_ADDRESS --rpc-url $RPC_URL 2>/dev/null)

if [ "$IS_OPERATOR" == "true" ]; then
    echo "⚠️  Operator 已经存在"
    exit 0
fi

# 准备提案数据（编码 operator 地址）
PROPOSAL_DATA=$(cast abi-encode "f(address)" $OPERATOR_ADDRESS)

echo "提交多签提案（AddOperator）..."
echo "提案数据: $PROPOSAL_DATA"
echo ""

# 提交提案（ProposalType.AddOperator = 0）
echo "正在提交提案..."
SUBMIT_OUTPUT=$(cast send $VAULT_CONTRACT \
    "submitProposal(uint8,bytes)" \
    0 \
    $PROPOSAL_DATA \
    --private-key $OWNER_PRIVATE_KEY \
    --rpc-url $RPC_URL \
    --legacy \
    --json \
    2>&1)

# 提取交易哈希
TX_HASH=$(echo "$SUBMIT_OUTPUT" | jq -r '.transactionHash' 2>/dev/null)

if [ -z "$TX_HASH" ] || [ "$TX_HASH" == "null" ]; then
    TX_HASH=$(echo "$SUBMIT_OUTPUT" | grep -oE '0x[a-fA-F0-9]{64}' | head -1)
fi

if [ -n "$TX_HASH" ] && [ "$TX_HASH" != "null" ]; then
    echo "✅ 提案提交成功！"
    echo "交易哈希: $TX_HASH"
    echo "查看: https://testnet.bscscan.com/tx/$TX_HASH"
else
    echo "⚠️  无法提取交易哈希，输出:"
    echo "$SUBMIT_OUTPUT"
fi

echo ""
echo "等待交易确认..."
sleep 5

# 获取提案 ID 并执行
echo "获取提案 ID..."
PROPOSAL_COUNTER=$(cast call $VAULT_CONTRACT "proposalCounter()(uint256)" --rpc-url $RPC_URL 2>/dev/null)

if [ -n "$PROPOSAL_COUNTER" ]; then
    echo "提案 ID: $PROPOSAL_COUNTER"
    echo "执行提案..."
    
    cast send $VAULT_CONTRACT \
        "executeProposal(uint256)" \
        $PROPOSAL_COUNTER \
        --private-key $OWNER_PRIVATE_KEY \
        --rpc-url $RPC_URL \
        --legacy
    
    echo ""
    echo "等待执行确认..."
    sleep 5
fi

# 验证
echo "验证 Operator 状态..."
IS_OPERATOR_NEW=$(cast call $VAULT_CONTRACT "operators(address)(bool)" $OPERATOR_ADDRESS --rpc-url $RPC_URL 2>/dev/null)

if [ "$IS_OPERATOR_NEW" == "true" ]; then
    echo "✅ Operator 已成功添加！"
else
    echo "⚠️  Operator 状态: $IS_OPERATOR_NEW"
    if [ -n "$PROPOSAL_COUNTER" ]; then
        echo "   如果仍未添加，请手动执行:"
        echo "   ./scripts/execute_proposal.sh $PROPOSAL_COUNTER"
    fi
fi
