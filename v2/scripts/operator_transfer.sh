#!/bin/bash

# Operator 转账脚本 - BSC 测试网
# 功能：Operator 将用户的资金转移到指定地址

echo "=========================================="
echo "UserVault Operator 转账脚本"
echo "=========================================="

# ============ 配置参数 ============
# 合约地址（已部署）
VAULT_CONTRACT="0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E"

# Token 地址
TOKEN_CONTRACT="0x76CeE3E0FDF715F50B15Ca83c0ed8C454c7F88A3"

# Operator 私钥
OPERATOR_PRIVATE_KEY="ae4a4050afb424fd7fb75518ed89dfe4caf300aed49e5b7976036fc4b9da3a97"

# 用户地址（资金从哪个用户账户转出）
USER_ADDRESS="0x22ae03eccb791e547478f50c584c58a3d342796f"

# 接收地址（资金转到哪里）
TO_ADDRESS="0x22ae03eccb791e547478f50c584c58a3d342796f"

# 转账金额（50 个 token）
# 注意：需要根据 token 的 decimals 调整
# 如果是 18 位小数：50 * 10^18 = 50000000000000000000
# 如果是 6 位小数：50 * 10^6 = 50000000
TRANSFER_TOKEN_AMOUNT="50"
TRANSFER_AMOUNT="50000000000000000000"  # 50 * 10^18 (假设 18 位小数)

# BSC 测试网 RPC
RPC_URL="https://data-seed-prebsc-1-s1.binance.org:8545"

# 生成唯一的 opId
OP_ID=$(cast keccak256 $(echo -n "$(date +%s)$RANDOM" | xxd -p))

echo "合约地址: $VAULT_CONTRACT"
echo "用户地址: $USER_ADDRESS"
echo "接收地址: $TO_ADDRESS"
echo "转账金额: $TRANSFER_TOKEN_AMOUNT tokens"
echo "Op ID: $OP_ID"
echo ""

# ============ 步骤 1: 获取 Operator 地址 ============
echo "步骤 1: 获取 Operator 地址..."
OPERATOR_ADDRESS=$(cast wallet address $OPERATOR_PRIVATE_KEY)
echo "Operator 地址: $OPERATOR_ADDRESS"
echo ""

# ============ 步骤 2: 检查 Operator 权限 ============
echo "步骤 2: 检查 Operator 权限..."
IS_OPERATOR=$(cast call $VAULT_CONTRACT "operators(address)(bool)" $OPERATOR_ADDRESS --rpc-url $RPC_URL 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "❌ 无法检查 Operator 权限"
    exit 1
fi

if [ "$IS_OPERATOR" != "true" ]; then
    echo "❌ 地址 $OPERATOR_ADDRESS 不是 Operator，无法执行转账"
    exit 1
fi

echo "✅ Operator 权限验证通过"
echo ""

# ============ 步骤 3: 检查用户余额 ============
echo "步骤 3: 检查用户在合约中的余额..."
USER_BALANCE=$(cast call $VAULT_CONTRACT "balances(address)(uint256)" $USER_ADDRESS --rpc-url $RPC_URL 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "❌ 无法获取用户余额"
    exit 1
fi

echo "用户在合约中的余额: $USER_BALANCE wei"
echo ""

# 检查余额是否足够
USER_BALANCE_DEC=$(cast --to-dec $USER_BALANCE 2>/dev/null || echo "0")
TRANSFER_AMOUNT_DEC=$(cast --to-dec $TRANSFER_AMOUNT 2>/dev/null || echo "0")

if [ "$USER_BALANCE_DEC" -lt "$TRANSFER_AMOUNT_DEC" ]; then
    echo "❌ 用户余额不足！"
    echo "   需要: $TRANSFER_TOKEN_AMOUNT tokens ($TRANSFER_AMOUNT_DEC wei)"
    echo "   当前余额: $USER_BALANCE_DEC wei"
    exit 1
fi

echo "✅ 用户余额充足"
echo ""

# ============ 步骤 4: 检查 opId 是否已使用 ============
echo "步骤 4: 检查 opId 是否已使用..."
OP_ID_USED=$(cast call $VAULT_CONTRACT "usedOpIds(bytes32)(bool)" $OP_ID --rpc-url $RPC_URL 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "⚠️  无法检查 opId，继续执行..."
elif [ "$OP_ID_USED" == "true" ]; then
    echo "⚠️  Op ID 已使用，生成新的 Op ID..."
    OP_ID=$(cast keccak256 $(echo -n "$(date +%s)$RANDOM$RANDOM" | xxd -p))
    echo "新的 Op ID: $OP_ID"
fi

echo ""

# ============ 步骤 5: 检查合约是否暂停 ============
echo "步骤 5: 检查合约状态..."
IS_PAUSED=$(cast call $VAULT_CONTRACT "paused()(bool)" --rpc-url $RPC_URL 2>/dev/null)

if [ "$IS_PAUSED" == "true" ]; then
    echo "❌ 合约已暂停，无法执行转账"
    exit 1
fi

echo "✅ 合约正常运行"
echo ""

# ============ 步骤 6: 执行转账 ============
echo "步骤 6: 执行转账..."
echo "从用户: $USER_ADDRESS"
echo "转到: $TO_ADDRESS"
echo "金额: $TRANSFER_TOKEN_AMOUNT tokens ($TRANSFER_AMOUNT wei)"
echo "Op ID: $OP_ID"
echo ""

# 调用 operatorTransfer 函数
# operatorTransfer(address user, address to, uint256 amount, bytes32 opId)
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
    echo "   交易哈希: $TX_HASH"
    echo "   查看: https://testnet.bscscan.com/tx/$TX_HASH"
else
    echo "   交易: $TRANSFER_TX"
fi
echo ""

# ============ 步骤 7: 等待交易确认 ============
echo "步骤 7: 等待交易确认..."
sleep 5

# ============ 步骤 8: 验证转账结果 ============
echo "步骤 8: 验证转账结果..."

# 检查用户余额
USER_BALANCE_NEW=$(cast call $VAULT_CONTRACT "balances(address)(uint256)" $USER_ADDRESS --rpc-url $RPC_URL 2>/dev/null)
if [ $? -eq 0 ]; then
    USER_BALANCE_NEW_DEC=$(cast --to-dec $USER_BALANCE_NEW 2>/dev/null || echo "0")
    EXPECTED_BALANCE=$((USER_BALANCE_DEC - TRANSFER_AMOUNT_DEC))
    
    echo "用户新余额: $USER_BALANCE_NEW_DEC wei"
    echo "预期余额: $EXPECTED_BALANCE wei"
    
    if [ "$USER_BALANCE_NEW_DEC" -eq "$EXPECTED_BALANCE" ]; then
        echo "✅ 用户余额更新正确"
    else
        echo "⚠️  用户余额更新异常"
    fi
fi

# 检查接收地址的 Token 余额
TO_BALANCE=$(cast call $TOKEN_CONTRACT "balanceOf(address)(uint256)" $TO_ADDRESS --rpc-url $RPC_URL 2>/dev/null)
if [ $? -eq 0 ]; then
    echo "接收地址 Token 余额: $TO_BALANCE wei"
fi

# 检查 opId 是否已标记为已使用
OP_ID_USED_NEW=$(cast call $VAULT_CONTRACT "usedOpIds(bytes32)(bool)" $OP_ID --rpc-url $RPC_URL 2>/dev/null)
if [ "$OP_ID_USED_NEW" == "true" ]; then
    echo "✅ Op ID 已标记为已使用"
fi

echo ""
echo "=========================================="
echo "转账完成！"
echo "=========================================="
echo "合约地址: $VAULT_CONTRACT"
echo "Operator 地址: $OPERATOR_ADDRESS"
echo "用户地址: $USER_ADDRESS"
echo "接收地址: $TO_ADDRESS"
echo "转账金额: $TRANSFER_TOKEN_AMOUNT tokens"
echo "Op ID: $OP_ID"
if [ -n "$TX_HASH" ] && [ "$TX_HASH" != "null" ]; then
    echo "交易哈希: $TX_HASH"
fi
echo "=========================================="
