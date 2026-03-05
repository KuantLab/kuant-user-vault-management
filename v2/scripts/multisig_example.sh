#!/bin/bash

# 多签提案完整示例脚本
# 演示：3个Owner，需要2个确认的完整流程

echo "=========================================="
echo "多签提案完整流程示例"
echo "=========================================="

# ============ 配置参数 ============
VAULT_CONTRACT="0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E"
RPC_URL="https://data-seed-prebsc-1-s1.binance.org:8545"

# Owner 私钥（示例，请替换为实际私钥）
OWNER1_KEY="0xOwner1PrivateKey"
OWNER2_KEY="0xOwner2PrivateKey"
OWNER3_KEY="0xOwner3PrivateKey"

# 要添加的 Operator
OPERATOR_ADDRESS="0x07e3aabd2d4d5dcec107ef9555dc0e5ef24f62b3"

echo "合约地址: $VAULT_CONTRACT"
echo "Operator 地址: $OPERATOR_ADDRESS"
echo ""
echo "多签配置: 3个Owner，需要2个确认（2-of-3）"
echo ""

# ============ 步骤 1: Owner1 提交提案 ============
echo "=========================================="
echo "步骤 1: Owner1 提交提案"
echo "=========================================="
echo ""

# 准备提案数据
PROPOSAL_DATA=$(cast abi-encode "f(address)" $OPERATOR_ADDRESS)
echo "提案数据: $PROPOSAL_DATA"
echo ""

echo "Owner1 正在提交提案..."
echo "命令:"
echo "cast send $VAULT_CONTRACT \\"
echo "    \"submitProposal(uint8,bytes)\" \\"
echo "    0 \\"
echo "    $PROPOSAL_DATA \\"
echo "    --private-key \$OWNER1_KEY \\"
echo "    --rpc-url $RPC_URL \\"
echo "    --legacy"
echo ""

# 实际执行（如果私钥已设置）
if [ "$OWNER1_KEY" != "0xOwner1PrivateKey" ]; then
    SUBMIT_TX=$(cast send $VAULT_CONTRACT \
        "submitProposal(uint8,bytes)" \
        0 \
        $PROPOSAL_DATA \
        --private-key $OWNER1_KEY \
        --rpc-url $RPC_URL \
        --legacy \
        --json \
        2>&1)
    
    if [ $? -eq 0 ]; then
        TX_HASH=$(echo "$SUBMIT_TX" | jq -r '.transactionHash' 2>/dev/null)
        echo "✅ 提案提交成功！"
        echo "   交易哈希: $TX_HASH"
        echo ""
        
        # 获取提案 ID
        sleep 3
        PROPOSAL_ID=$(cast call $VAULT_CONTRACT "proposalCounter()(uint256)" --rpc-url $RPC_URL 2>/dev/null)
        echo "   提案 ID: $PROPOSAL_ID"
        echo "   当前确认数: 1/2 (Owner1 已确认)"
    else
        echo "❌ 提交失败: $SUBMIT_TX"
        exit 1
    fi
else
    echo "⚠️  请设置 OWNER1_KEY 后执行"
    PROPOSAL_ID=1  # 示例
fi

echo ""

# ============ 步骤 2: Owner2 确认提案 ============
echo "=========================================="
echo "步骤 2: Owner2 确认提案"
echo "=========================================="
echo ""

echo "Owner2 正在确认提案 ID: $PROPOSAL_ID"
echo "命令:"
echo "cast send $VAULT_CONTRACT \\"
echo "    \"confirmProposal(uint256)\" \\"
echo "    $PROPOSAL_ID \\"
echo "    --private-key \$OWNER2_KEY \\"
echo "    --rpc-url $RPC_URL \\"
echo "    --legacy"
echo ""

echo "说明:"
echo "  - Owner2 确认后，确认数 = 2"
echo "  - 达到 requiredConfirmations (2)"
echo "  - 提案会自动执行"
echo "  - Operator 会被添加"
echo ""

# 实际执行（如果私钥已设置）
if [ "$OWNER2_KEY" != "0xOwner2PrivateKey" ] && [ -n "$PROPOSAL_ID" ]; then
    CONFIRM_TX=$(cast send $VAULT_CONTRACT \
        "confirmProposal(uint256)" \
        $PROPOSAL_ID \
        --private-key $OWNER2_KEY \
        --rpc-url $RPC_URL \
        --legacy \
        --json \
        2>&1)
    
    if [ $? -eq 0 ]; then
        TX_HASH=$(echo "$CONFIRM_TX" | jq -r '.transactionHash' 2>/dev/null)
        echo "✅ 提案确认成功！"
        echo "   交易哈希: $TX_HASH"
        echo "   提案已自动执行"
        echo ""
        
        # 验证 Operator 是否已添加
        sleep 3
        IS_OPERATOR=$(cast call $VAULT_CONTRACT "operators(address)(bool)" $OPERATOR_ADDRESS --rpc-url $RPC_URL 2>/dev/null)
        if [ "$IS_OPERATOR" == "true" ]; then
            echo "✅ Operator 已成功添加！"
        else
            echo "⚠️  Operator 状态: $IS_OPERATOR"
        fi
    else
        echo "❌ 确认失败: $CONFIRM_TX"
    fi
else
    echo "⚠️  请设置 OWNER2_KEY 后执行"
fi

echo ""

# ============ 查询提案状态 ============
echo "=========================================="
echo "查询提案状态"
echo "=========================================="
echo ""

if [ -n "$PROPOSAL_ID" ]; then
    echo "查询提案 ID: $PROPOSAL_ID"
    echo ""
    
    # 获取提案信息
    PROPOSAL_INFO=$(cast call $VAULT_CONTRACT \
        "getProposal(uint256)(uint256,address,uint8,uint256,bool)" \
        $PROPOSAL_ID \
        --rpc-url $RPC_URL \
        2>/dev/null)
    
    if [ -n "$PROPOSAL_INFO" ]; then
        echo "提案信息: $PROPOSAL_INFO"
        echo ""
        echo "格式: (id, proposer, proposalType, confirmations, executed)"
    fi
    
    # 获取确认数
    CONFIRMATIONS=$(cast call $VAULT_CONTRACT \
        "getProposalConfirmations(uint256)(uint256)" \
        $PROPOSAL_ID \
        --rpc-url $RPC_URL \
        2>/dev/null)
    
    echo "当前确认数: $CONFIRMATIONS"
    echo ""
fi

echo "=========================================="
echo "流程说明"
echo "=========================================="
echo ""
echo "1. Owner1 提交提案 → 提案 ID = $PROPOSAL_ID，确认数 = 1"
echo "2. Owner2 确认提案 → 确认数 = 2，达到要求"
echo "3. 自动执行提案 → Operator 已添加"
echo ""
echo "注意: 执行是自动的，无需手动调用 executeProposal()"
echo "=========================================="
