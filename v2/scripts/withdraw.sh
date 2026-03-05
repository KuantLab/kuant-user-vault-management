#!/bin/bash

# 用户提现脚本 - BSC 测试网
# 功能：用户从合约中提现代币

echo "=========================================="
echo "UserVault 用户提现脚本"
echo "=========================================="

# ============ 配置参数 ============
# 合约地址（已部署）
VAULT_CONTRACT="0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E"

# Token 地址
TOKEN_CONTRACT="0x76CeE3E0FDF715F50B15Ca83c0ed8C454c7F88A3"

# 用户私钥
USER_PRIVATE_KEY="39b36efe563e1d284dcc5cfe7c5b00207e8fef1bd41d343ee5c1cb0dc805a668"

# 提现金额（30 个 token）
# 注意：需要根据 token 的 decimals 调整
# 如果是 18 位小数：30 * 10^18 = 30000000000000000000
# 如果是 6 位小数：30 * 10^6 = 30000000
WITHDRAW_TOKEN_AMOUNT="30"
WITHDRAW_AMOUNT="30000000000000000000"  # 30 * 10^18 (假设 18 位小数)

# BSC 测试网 RPC
RPC_URL="https://data-seed-prebsc-1-s1.binance.org:8545"

echo "合约地址: $VAULT_CONTRACT"
echo "提现金额: $WITHDRAW_TOKEN_AMOUNT tokens"
echo ""

# ============ 步骤 1: 获取用户地址 ============
echo "步骤 1: 获取用户地址..."
USER_ADDRESS=$(cast wallet address $USER_PRIVATE_KEY)
echo "用户地址: $USER_ADDRESS"
echo ""

# ============ 步骤 2: 检查用户在合约中的余额 ============
echo "步骤 2: 检查用户在合约中的余额..."
USER_BALANCE=$(cast call $VAULT_CONTRACT "balances(address)(uint256)" $USER_ADDRESS --rpc-url $RPC_URL 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "❌ 无法获取用户余额"
    exit 1
fi

echo "用户在合约中的余额: $USER_BALANCE wei"
echo ""

# 检查余额是否足够
USER_BALANCE_DEC=$(cast --to-dec $USER_BALANCE 2>/dev/null || echo "0")
WITHDRAW_AMOUNT_DEC=$(cast --to-dec $WITHDRAW_AMOUNT 2>/dev/null || echo "0")

if [ "$USER_BALANCE_DEC" -lt "$WITHDRAW_AMOUNT_DEC" ]; then
    echo "❌ 用户余额不足！"
    echo "   需要: $WITHDRAW_TOKEN_AMOUNT tokens ($WITHDRAW_AMOUNT_DEC wei)"
    echo "   当前余额: $USER_BALANCE_DEC wei"
    exit 1
fi

echo "✅ 用户余额充足"
echo ""

# ============ 步骤 3: 检查合约是否暂停 ============
echo "步骤 3: 检查合约状态..."
IS_PAUSED=$(cast call $VAULT_CONTRACT "paused()(bool)" --rpc-url $RPC_URL 2>/dev/null)

if [ "$IS_PAUSED" == "true" ]; then
    echo "❌ 合约已暂停，无法提现"
    exit 1
fi

echo "✅ 合约正常运行"
echo ""

# ============ 步骤 4: 执行提现 ============
echo "步骤 4: 执行提现..."
echo "用户地址: $USER_ADDRESS"
echo "提现金额: $WITHDRAW_TOKEN_AMOUNT tokens ($WITHDRAW_AMOUNT wei)"
echo ""

# 调用 withdraw 函数
# withdraw(uint256 amount)
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
    echo "   交易哈希: $TX_HASH"
    echo "   查看: https://testnet.bscscan.com/tx/$TX_HASH"
else
    echo "   交易: $WITHDRAW_TX"
fi
echo ""

# ============ 步骤 5: 等待交易确认 ============
echo "步骤 5: 等待交易确认..."
sleep 5

# ============ 步骤 6: 验证提现结果 ============
echo "步骤 6: 验证提现结果..."

# 检查用户在合约中的新余额
USER_BALANCE_NEW=$(cast call $VAULT_CONTRACT "balances(address)(uint256)" $USER_ADDRESS --rpc-url $RPC_URL 2>/dev/null)
if [ $? -eq 0 ]; then
    USER_BALANCE_NEW_DEC=$(cast --to-dec $USER_BALANCE_NEW 2>/dev/null || echo "0")
    EXPECTED_BALANCE=$((USER_BALANCE_DEC - WITHDRAW_AMOUNT_DEC))
    
    echo "用户新余额: $USER_BALANCE_NEW_DEC wei"
    echo "预期余额: $EXPECTED_BALANCE wei"
    
    if [ "$USER_BALANCE_NEW_DEC" -eq "$EXPECTED_BALANCE" ]; then
        echo "✅ 用户余额更新正确"
    else
        echo "⚠️  用户余额更新异常"
    fi
fi

# 检查用户钱包的 Token 余额
USER_TOKEN_BALANCE=$(cast call $TOKEN_CONTRACT "balanceOf(address)(uint256)" $USER_ADDRESS --rpc-url $RPC_URL 2>/dev/null)
if [ $? -eq 0 ]; then
    USER_TOKEN_BALANCE_DEC=$(cast --to-dec $USER_TOKEN_BALANCE 2>/dev/null || echo "0")
    echo "用户钱包 Token 余额: $USER_TOKEN_BALANCE_DEC wei"
fi

# 检查合约 Token 余额
CONTRACT_BALANCE=$(cast call $TOKEN_CONTRACT "balanceOf(address)(uint256)" $VAULT_CONTRACT --rpc-url $RPC_URL 2>/dev/null)
if [ $? -eq 0 ]; then
    CONTRACT_BALANCE_DEC=$(cast --to-dec $CONTRACT_BALANCE 2>/dev/null || echo "0")
    echo "合约 Token 余额: $CONTRACT_BALANCE_DEC wei"
fi

echo ""
echo "=========================================="
echo "提现完成！"
echo "=========================================="
echo "合约地址: $VAULT_CONTRACT"
echo "用户地址: $USER_ADDRESS"
echo "提现金额: $WITHDRAW_TOKEN_AMOUNT tokens"
if [ -n "$TX_HASH" ] && [ "$TX_HASH" != "null" ]; then
    echo "交易哈希: $TX_HASH"
fi
echo "=========================================="
