#!/bin/bash

# Operator 充值脚本 - BSC 测试网
# 功能：Operator 为用户充值代币到合约

echo "=========================================="
echo "UserVault Operator 充值脚本"
echo "=========================================="

# ============ 配置参数 ============
# 合约地址（已部署）
VAULT_CONTRACT="0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E"

# Token 地址
TOKEN_CONTRACT="0x76CeE3E0FDF715F50B15Ca83c0ed8C454c7F88A3"

# Operator 私钥
OPERATOR_PRIVATE_KEY="ae4a4050afb424fd7fb75518ed89dfe4caf300aed49e5b7976036fc4b9da3a97"

# 用户地址（为哪个用户充值）
USER_ADDRESS="0x22ae03eccb791e547478f50c584c58a3d342796f"

# 充值金额（30 个 token）
# 注意：需要根据 token 的 decimals 调整
# 如果是 18 位小数：30 * 10^18 = 30000000000000000000
# 如果是 6 位小数：30 * 10^6 = 30000000
DEPOSIT_TOKEN_AMOUNT="30"
DEPOSIT_AMOUNT="30000000000000000000"  # 30 * 10^18 (假设 18 位小数)

# BSC 测试网 RPC
RPC_URL="https://data-seed-prebsc-1-s1.binance.org:8545"

# 生成唯一的 opId
OP_ID=$(cast keccak256 $(echo -n "$(date +%s)$RANDOM" | xxd -p))

echo "合约地址: $VAULT_CONTRACT"
echo "用户地址: $USER_ADDRESS"
echo "充值金额: $DEPOSIT_TOKEN_AMOUNT tokens"
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
    echo "❌ 地址 $OPERATOR_ADDRESS 不是 Operator，无法执行充值"
    exit 1
fi

echo "✅ Operator 权限验证通过"
echo ""

# ============ 步骤 3: 检查 Operator Token 余额 ============
echo "步骤 3: 检查 Operator Token 余额..."
OPERATOR_BALANCE=$(cast call $TOKEN_CONTRACT "balanceOf(address)(uint256)" $OPERATOR_ADDRESS --rpc-url $RPC_URL 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "❌ 无法获取 Operator Token 余额"
    exit 1
fi

echo "Operator Token 余额: $OPERATOR_BALANCE wei"
echo ""

# 检查余额是否足够
OPERATOR_BALANCE_DEC=$(cast --to-dec $OPERATOR_BALANCE 2>/dev/null || echo "0")
DEPOSIT_AMOUNT_DEC=$(cast --to-dec $DEPOSIT_AMOUNT 2>/dev/null || echo "0")

if [ "$OPERATOR_BALANCE_DEC" -lt "$DEPOSIT_AMOUNT_DEC" ]; then
    echo "❌ Operator Token 余额不足！"
    echo "   需要: $DEPOSIT_TOKEN_AMOUNT tokens ($DEPOSIT_AMOUNT_DEC wei)"
    echo "   当前余额: $OPERATOR_BALANCE_DEC wei"
    exit 1
fi

echo "✅ Operator Token 余额充足"
echo ""

# ============ 步骤 4: 检查授权额度 ============
echo "步骤 4: 检查授权额度..."
ALLOWANCE=$(cast call $TOKEN_CONTRACT "allowance(address,address)(uint256)" $OPERATOR_ADDRESS $VAULT_CONTRACT --rpc-url $RPC_URL 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "❌ 无法获取授权额度"
    exit 1
fi

echo "当前授权额度: $ALLOWANCE wei"
echo ""

# 将十六进制转换为十进制进行比较
ALLOWANCE_DEC=$(cast --to-dec $ALLOWANCE 2>/dev/null || echo "0")

# 授权（如果需要）
if [ "$ALLOWANCE" == "0x0" ] || [ "$ALLOWANCE" == "0" ] || [ -z "$ALLOWANCE" ] || [ "$ALLOWANCE_DEC" -lt "$DEPOSIT_AMOUNT_DEC" ]; then
    echo "步骤 5: 授权合约使用代币..."
    echo "授权金额: $DEPOSIT_TOKEN_AMOUNT tokens ($DEPOSIT_AMOUNT wei)"
    
    APPROVE_TX=$(cast send $TOKEN_CONTRACT \
        "approve(address,uint256)" \
        $VAULT_CONTRACT $DEPOSIT_AMOUNT \
        --private-key $OPERATOR_PRIVATE_KEY \
        --rpc-url $RPC_URL \
        --legacy \
        --json \
        2>&1)
    
    if [ $? -ne 0 ]; then
        echo "❌ 授权失败: $APPROVE_TX"
        exit 1
    fi
    
    # 提取交易哈希
    TX_HASH=$(echo "$APPROVE_TX" | jq -r '.transactionHash' 2>/dev/null)
    if [ -z "$TX_HASH" ] || [ "$TX_HASH" == "null" ]; then
        TX_HASH=$(echo "$APPROVE_TX" | grep -oE '0x[a-fA-F0-9]{64}' | head -1)
    fi
    
    echo "✅ 授权成功！"
    if [ -n "$TX_HASH" ] && [ "$TX_HASH" != "null" ]; then
        echo "   交易哈希: $TX_HASH"
        echo "   查看: https://testnet.bscscan.com/tx/$TX_HASH"
    fi
    echo ""
    
    # 等待交易确认
    echo "等待交易确认..."
    sleep 5
else
    echo "✅ 授权额度充足，跳过授权步骤"
    echo ""
fi

# ============ 步骤 6: 检查 opId 是否已使用 ============
echo "步骤 6: 检查 opId 是否已使用..."
OP_ID_USED=$(cast call $VAULT_CONTRACT "usedOpIds(bytes32)(bool)" $OP_ID --rpc-url $RPC_URL 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "⚠️  无法检查 opId，继续执行..."
elif [ "$OP_ID_USED" == "true" ]; then
    echo "⚠️  Op ID 已使用，生成新的 Op ID..."
    OP_ID=$(cast keccak256 $(echo -n "$(date +%s)$RANDOM$RANDOM" | xxd -p))
    echo "新的 Op ID: $OP_ID"
fi

echo ""

# ============ 步骤 7: 检查合约是否暂停 ============
echo "步骤 7: 检查合约状态..."
IS_PAUSED=$(cast call $VAULT_CONTRACT "paused()(bool)" --rpc-url $RPC_URL 2>/dev/null)

if [ "$IS_PAUSED" == "true" ]; then
    echo "❌ 合约已暂停，无法执行充值"
    exit 1
fi

echo "✅ 合约正常运行"
echo ""

# ============ 步骤 8: 执行充值 ============
echo "步骤 8: 执行充值..."
echo "为用户: $USER_ADDRESS"
echo "充值金额: $DEPOSIT_TOKEN_AMOUNT tokens ($DEPOSIT_AMOUNT wei)"
echo "Op ID: $OP_ID"
echo ""

# 调用 operatorDeposit 函数
# operatorDeposit(address user, uint256 amount, bytes32 opId)
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
    echo "   交易哈希: $TX_HASH"
    echo "   查看: https://testnet.bscscan.com/tx/$TX_HASH"
else
    echo "   交易: $DEPOSIT_TX"
fi
echo ""

# ============ 步骤 9: 等待交易确认 ============
echo "步骤 9: 等待交易确认..."
sleep 5

# ============ 步骤 10: 验证充值结果 ============
echo "步骤 10: 验证充值结果..."

# 检查用户在合约中的余额
USER_BALANCE=$(cast call $VAULT_CONTRACT "balances(address)(uint256)" $USER_ADDRESS --rpc-url $RPC_URL 2>/dev/null)
if [ $? -eq 0 ]; then
    USER_BALANCE_DEC=$(cast --to-dec $USER_BALANCE 2>/dev/null || echo "0")
    echo "用户在合约中的余额: $USER_BALANCE_DEC wei"
fi

# 检查合约 Token 余额
CONTRACT_BALANCE=$(cast call $TOKEN_CONTRACT "balanceOf(address)(uint256)" $VAULT_CONTRACT --rpc-url $RPC_URL 2>/dev/null)
if [ $? -eq 0 ]; then
    CONTRACT_BALANCE_DEC=$(cast --to-dec $CONTRACT_BALANCE 2>/dev/null || echo "0")
    echo "合约 Token 余额: $CONTRACT_BALANCE_DEC wei"
fi

# 检查 opId 是否已标记为已使用
OP_ID_USED_NEW=$(cast call $VAULT_CONTRACT "usedOpIds(bytes32)(bool)" $OP_ID --rpc-url $RPC_URL 2>/dev/null)
if [ "$OP_ID_USED_NEW" == "true" ]; then
    echo "✅ Op ID 已标记为已使用"
fi

echo ""
echo "=========================================="
echo "充值完成！"
echo "=========================================="
echo "合约地址: $VAULT_CONTRACT"
echo "Operator 地址: $OPERATOR_ADDRESS"
echo "用户地址: $USER_ADDRESS"
echo "充值金额: $DEPOSIT_TOKEN_AMOUNT tokens"
echo "Op ID: $OP_ID"
if [ -n "$TX_HASH" ] && [ "$TX_HASH" != "null" ]; then
    echo "交易哈希: $TX_HASH"
fi
echo "=========================================="
