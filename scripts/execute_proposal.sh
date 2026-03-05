#!/bin/bash

# 执行提案脚本
# 用法: ./execute_proposal.sh [提案ID]

VAULT_CONTRACT="0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E"
OWNER_PRIVATE_KEY="6f4058fa7ab22b3c83290a6bca1be7d43ed911d4ffe5f3d1003d413fdfd425c7"
RPC_URL="https://data-seed-prebsc-1-s1.binance.org:8545"
PROPOSAL_ID=${1:-1}

echo "执行提案 ID: $PROPOSAL_ID"
echo ""

# 执行提案
cast send $VAULT_CONTRACT \
    "executeProposal(uint256)" \
    $PROPOSAL_ID \
    --private-key $OWNER_PRIVATE_KEY \
    --rpc-url $RPC_URL \
    --legacy

echo ""
echo "等待确认..."
sleep 5

# 验证 Operator
OPERATOR_ADDRESS="0x07e3aabd2d4d5dcec107ef9555dc0e5ef24f62b3"
IS_OPERATOR=$(cast call $VAULT_CONTRACT "operators(address)(bool)" $OPERATOR_ADDRESS --rpc-url $RPC_URL 2>/dev/null)

if [ "$IS_OPERATOR" == "true" ]; then
    echo "✅ Operator 已成功添加！"
else
    echo "⚠️  Operator 状态: $IS_OPERATOR"
fi
