#!/bin/bash

# 添加 Operator 脚本 - BSC 测试网
# 功能：通过多签提案添加 Operator

echo "=========================================="
echo "UserVault 添加 Operator 脚本"
echo "=========================================="

# ============ 配置参数 ============
# 合约地址（已部署）
VAULT_CONTRACT="0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E"

# Owner 私钥（部署合约的钱包）
# 注意：这是部署合约时使用的私钥，用于提交多签提案
OWNER_PRIVATE_KEY="6f4058fa7ab22b3c83290a6bca1be7d43ed911d4ffe5f3d1003d413fdfd425c7"

# 要添加的 Operator 地址
OPERATOR_ADDRESS="0x07e3aabd2d4d5dcec107ef9555dc0e5ef24f62b3"

# BSC 测试网 RPC
RPC_URL="https://data-seed-prebsc-1-s1.binance.org:8545"

echo "合约地址: $VAULT_CONTRACT"
echo "Operator 地址: $OPERATOR_ADDRESS"
echo ""

# ============ 步骤 1: 获取 Owner 地址 ============
echo "步骤 1: 获取 Owner 地址..."
OWNER_ADDRESS=$(cast wallet address $OWNER_PRIVATE_KEY)
echo "Owner 地址: $OWNER_ADDRESS"
echo ""

# ============ 步骤 2: 检查 Operator 是否已存在 ============
echo "步骤 2: 检查 Operator 状态..."
IS_OPERATOR=$(cast call $VAULT_CONTRACT "operators(address)(bool)" $OPERATOR_ADDRESS --rpc-url $RPC_URL 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "❌ 无法检查 Operator 状态"
    exit 1
fi

if [ "$IS_OPERATOR" == "true" ]; then
    echo "⚠️  Operator 已经存在，无需重复添加"
    exit 0
fi

echo "Operator 当前状态: 未添加"
echo ""

# ============ 步骤 3: 检查 Owner 权限 ============
echo "步骤 3: 检查 Owner 权限..."
IS_OWNER=$(cast call $VAULT_CONTRACT "isOwner(address)(bool)" $OWNER_ADDRESS --rpc-url $RPC_URL 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "❌ 无法检查 Owner 权限"
    exit 1
fi

if [ "$IS_OWNER" != "true" ]; then
    echo "❌ 地址 $OWNER_ADDRESS 不是 Owner，无法提交提案"
    exit 1
fi

echo "✅ Owner 权限验证通过"
echo ""

# ============ 步骤 4: 准备提案数据 ============
echo "步骤 4: 准备提案数据..."
# ProposalType.AddOperator = 0
# data 需要编码 operator 地址
PROPOSAL_DATA=$(cast abi-encode "f(address)" $OPERATOR_ADDRESS)

echo "提案类型: AddOperator (0)"
echo "提案数据: $PROPOSAL_DATA"
echo ""

# ============ 步骤 5: 提交提案 ============
echo "步骤 5: 提交多签提案..."
echo "注意: 由于是 1-of-1 多签，提案提交后会自动确认并执行"
echo ""

# 提交提案
# submitProposal(ProposalType proposalType, bytes memory data)
echo "正在提交提案..."
SUBMIT_TX=$(cast send $VAULT_CONTRACT \
    "submitProposal(uint8,bytes)" \
    0 \
    $PROPOSAL_DATA \
    --private-key $OWNER_PRIVATE_KEY \
    --rpc-url $RPC_URL \
    --legacy \
    --json \
    2>&1)

EXIT_CODE=$?

# 检查是否成功
if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ 提交提案失败: $SUBMIT_TX"
    exit 1
fi

# 尝试从 JSON 输出中提取交易哈希
TX_HASH=$(echo "$SUBMIT_TX" | jq -r '.transactionHash' 2>/dev/null)

# 如果 JSON 解析失败，尝试从文本中提取
if [ -z "$TX_HASH" ] || [ "$TX_HASH" == "null" ]; then
    # 尝试从输出中提取所有可能的哈希
    TX_HASH=$(echo "$SUBMIT_TX" | grep -oE '0x[a-fA-F0-9]{64}' | head -1)
fi

# 如果还是找不到，尝试从 receipt 中获取
if [ -z "$TX_HASH" ]; then
    # 有时候 cast send 会直接输出哈希
    TX_HASH=$(echo "$SUBMIT_TX" | grep -i "transactionHash\|hash" | grep -oE '0x[a-fA-F0-9]{64}' | head -1)
fi

echo "✅ 提案提交成功！"
if [ -n "$TX_HASH" ] && [ "$TX_HASH" != "null" ]; then
    echo "   交易哈希: $TX_HASH"
    echo "   查看: https://testnet.bscscan.com/tx/$TX_HASH"
else
    echo "   ⚠️  无法提取交易哈希，请查看完整输出:"
    echo "$SUBMIT_TX" | head -20
    echo ""
    echo "   请手动从输出中查找交易哈希"
fi
echo ""

# ============ 步骤 6: 等待交易确认 ============
echo "步骤 6: 等待交易确认..."
sleep 5

# ============ 步骤 7: 获取提案 ID 并执行 ============
echo "步骤 7: 获取提案 ID 并执行..."
PROPOSAL_COUNTER=$(cast call $VAULT_CONTRACT "proposalCounter()(uint256)" --rpc-url $RPC_URL 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$PROPOSAL_COUNTER" ]; then
    LATEST_PROPOSAL_ID=$PROPOSAL_COUNTER
    echo "最新提案 ID: $LATEST_PROPOSAL_ID"
    
    # 检查提案是否已执行
    PROPOSAL_INFO=$(cast call $VAULT_CONTRACT "getProposal(uint256)(uint256,address,uint8,uint256,bool)" $LATEST_PROPOSAL_ID --rpc-url $RPC_URL 2>/dev/null)
    PROPOSAL_EXECUTED=$(echo $PROPOSAL_INFO | awk '{print $5}' 2>/dev/null)
    
    if [ "$PROPOSAL_EXECUTED" != "true" ]; then
        echo "提案未执行，正在执行..."
        
        EXECUTE_TX=$(cast send $VAULT_CONTRACT \
            "executeProposal(uint256)" \
            $LATEST_PROPOSAL_ID \
            --private-key $OWNER_PRIVATE_KEY \
            --rpc-url $RPC_URL \
            --legacy \
            --json \
            2>&1)
        
        if [ $? -eq 0 ]; then
            EXECUTE_TX_HASH=$(echo "$EXECUTE_TX" | jq -r '.transactionHash' 2>/dev/null)
            if [ -z "$EXECUTE_TX_HASH" ] || [ "$EXECUTE_TX_HASH" == "null" ]; then
                EXECUTE_TX_HASH=$(echo "$EXECUTE_TX" | grep -oE '0x[a-fA-F0-9]{64}' | head -1)
            fi
            
            echo "✅ 提案执行成功！"
            if [ -n "$EXECUTE_TX_HASH" ] && [ "$EXECUTE_TX_HASH" != "null" ]; then
                echo "   执行交易哈希: $EXECUTE_TX_HASH"
                echo "   查看: https://testnet.bscscan.com/tx/$EXECUTE_TX_HASH"
            fi
            echo ""
            sleep 3
        else
            echo "⚠️  执行提案失败: $EXECUTE_TX"
        fi
    else
        echo "✅ 提案已执行"
    fi
else
    echo "⚠️  无法获取提案 ID"
fi

# ============ 步骤 8: 验证 Operator 是否已添加 ============
echo "步骤 8: 验证 Operator 是否已添加..."
IS_OPERATOR_NEW=$(cast call $VAULT_CONTRACT "operators(address)(bool)" $OPERATOR_ADDRESS --rpc-url $RPC_URL 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "⚠️  无法验证 Operator 状态，请手动检查"
else
    if [ "$IS_OPERATOR_NEW" == "true" ]; then
        echo "✅ Operator 已成功添加！"
    else
        echo "⚠️  Operator 状态未更新"
        echo "   请稍后手动检查或使用以下命令执行提案:"
        echo "   ./scripts/execute_proposal.sh $LATEST_PROPOSAL_ID"
    fi
fi

echo ""
echo "=========================================="
echo "添加 Operator 完成！"
echo "=========================================="
echo "合约地址: $VAULT_CONTRACT"
echo "Operator 地址: $OPERATOR_ADDRESS"
if [ -n "$TX_HASH" ]; then
    echo "交易哈希: $TX_HASH"
fi
echo "=========================================="
echo ""
echo "验证命令:"
echo "cast call $VAULT_CONTRACT \"operators(address)(bool)\" $OPERATOR_ADDRESS --rpc-url $RPC_URL"
echo "=========================================="
