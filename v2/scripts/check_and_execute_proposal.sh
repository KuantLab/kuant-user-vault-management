#!/bin/bash

# 检查和执行提案脚本
# 功能：检查提案状态，如果未执行则执行

echo "=========================================="
echo "检查并执行提案"
echo "=========================================="

# ============ 配置参数 ============
VAULT_CONTRACT="0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E"
OWNER_PRIVATE_KEY="6f4058fa7ab22b3c83290a6bca1be7d43ed911d4ffe5f3d1003d413fdfd425c7"
RPC_URL="https://data-seed-prebsc-1-s1.binance.org:8545"

# 提案 ID（从 1 开始）
PROPOSAL_ID=${1:-1}

echo "合约地址: $VAULT_CONTRACT"
echo "提案 ID: $PROPOSAL_ID"
echo ""

# ============ 步骤 1: 检查提案计数器 ============
echo "步骤 1: 检查提案总数..."
PROPOSAL_COUNTER=$(cast call $VAULT_CONTRACT "proposalCounter()(uint256)" --rpc-url $RPC_URL 2>/dev/null)
if [ $? -eq 0 ]; then
    echo "提案总数: $PROPOSAL_COUNTER"
else
    echo "⚠️  无法获取提案总数"
fi
echo ""

# ============ 步骤 2: 检查提案状态 ============
echo "步骤 2: 检查提案状态..."
PROPOSAL_INFO=$(cast call $VAULT_CONTRACT "getProposal(uint256)(uint256,address,uint8,uint256,bool)" $PROPOSAL_ID --rpc-url $RPC_URL 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$PROPOSAL_INFO" ]; then
    echo "❌ 无法获取提案信息，提案可能不存在"
    exit 1
fi

# 解析提案信息（格式：id proposer proposalType confirmations executed）
PROPOSAL_EXECUTED=$(echo $PROPOSAL_INFO | awk '{print $5}')
PROPOSAL_CONFIRMATIONS=$(echo $PROPOSAL_INFO | awk '{print $4}')
REQUIRED_CONFIRMATIONS=$(cast call $VAULT_CONTRACT "requiredConfirmations()(uint256)" --rpc-url $RPC_URL 2>/dev/null)

echo "提案信息: $PROPOSAL_INFO"
echo "已执行: $PROPOSAL_EXECUTED"
echo "确认数: $PROPOSAL_CONFIRMATIONS"
echo "需要确认数: $REQUIRED_CONFIRMATIONS"
echo ""

# ============ 步骤 3: 检查是否需要执行 ============
if [ "$PROPOSAL_EXECUTED" == "true" ]; then
    echo "✅ 提案已执行"
    exit 0
fi

if [ "$PROPOSAL_CONFIRMATIONS" -lt "$REQUIRED_CONFIRMATIONS" ]; then
    echo "⚠️  确认数不足，无法执行"
    echo "   当前确认数: $PROPOSAL_CONFIRMATIONS"
    echo "   需要确认数: $REQUIRED_CONFIRMATIONS"
    exit 1
fi

# ============ 步骤 4: 执行提案 ============
echo "步骤 3: 执行提案..."
echo "提案 ID: $PROPOSAL_ID"
echo "确认数: $PROPOSAL_CONFIRMATIONS >= $REQUIRED_CONFIRMATIONS"
echo ""

EXECUTE_TX=$(cast send $VAULT_CONTRACT \
    "executeProposal(uint256)" \
    $PROPOSAL_ID \
    --private-key $OWNER_PRIVATE_KEY \
    --rpc-url $RPC_URL \
    --legacy \
    --json \
    2>&1)

if [ $? -ne 0 ]; then
    echo "❌ 执行提案失败: $EXECUTE_TX"
    exit 1
fi

# 提取交易哈希
TX_HASH=$(echo "$EXECUTE_TX" | jq -r '.transactionHash' 2>/dev/null)
if [ -z "$TX_HASH" ] || [ "$TX_HASH" == "null" ]; then
    TX_HASH=$(echo "$EXECUTE_TX" | grep -oE '0x[a-fA-F0-9]{64}' | head -1)
fi

echo "✅ 提案执行成功！"
if [ -n "$TX_HASH" ] && [ "$TX_HASH" != "null" ]; then
    echo "   交易哈希: $TX_HASH"
    echo "   查看: https://testnet.bscscan.com/tx/$TX_HASH"
fi
echo ""

# ============ 步骤 5: 验证 ============
echo "步骤 4: 等待确认并验证..."
sleep 5

OPERATOR_ADDRESS="0x07e3aabd2d4d5dcec107ef9555dc0e5ef24f62b3"
IS_OPERATOR=$(cast call $VAULT_CONTRACT "operators(address)(bool)" $OPERATOR_ADDRESS --rpc-url $RPC_URL 2>/dev/null)

if [ "$IS_OPERATOR" == "true" ]; then
    echo "✅ Operator 已成功添加！"
else
    echo "⚠️  Operator 状态未更新，请稍后检查"
fi

echo ""
echo "=========================================="
