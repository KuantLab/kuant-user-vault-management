#!/bin/bash

# 用户充值脚本 - 简化版（不依赖 Python）
# 功能：用户充值 50 个 token 到 UserVault 合约

echo "=========================================="
echo "UserVault 用户充值脚本"
echo "=========================================="

# ============ 配置参数 ============
VAULT_CONTRACT="0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E"
TOKEN_CONTRACT="0x76CeE3E0FDF715F50B15Ca83c0ed8C454c7F88A3"
USER_PRIVATE_KEY="39b36efe563e1d284dcc5cfe7c5b00207e8fef1bd41d343ee5c1cb0dc805a668"
RPC_URL="https://data-seed-prebsc-1-s1.binance.org:8545"

# 充值金额：50 个 token
# 注意：需要根据 token 的 decimals 调整
# 如果是 18 位小数：50 * 10^18 = 50000000000000000000
# 如果是 6 位小数：50 * 10^6 = 50000000
DEPOSIT_AMOUNT="50000000000000000000"  # 50 * 10^18 (假设 18 位小数)

# 生成唯一的 depositId
DEPOSIT_ID=$(cast keccak256 $(echo -n "$(date +%s)$RANDOM" | xxd -p))

echo "合约地址: $VAULT_CONTRACT"
echo "Token 地址: $TOKEN_CONTRACT"
echo "充值金额: 50 tokens"
echo "Deposit ID: $DEPOSIT_ID"
echo ""

# ============ 步骤 1: 获取用户地址 ============
echo "步骤 1: 获取用户地址..."
USER_ADDRESS=$(cast wallet address $USER_PRIVATE_KEY)
echo "用户地址: $USER_ADDRESS"
echo ""

# ============ 步骤 2: 检查用户余额 ============
echo "步骤 2: 检查用户 Token 余额..."
USER_BALANCE=$(cast call $TOKEN_CONTRACT "balanceOf(address)(uint256)" $USER_ADDRESS --rpc-url $RPC_URL 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "❌ 无法获取用户余额，请检查 Token 合约地址和网络连接"
    exit 1
fi

echo "用户 Token 余额: $USER_BALANCE wei"
echo ""

# 检查余额是否足够（简单比较）
if [ "$USER_BALANCE" == "0x0" ] || [ -z "$USER_BALANCE" ]; then
    echo "❌ 用户余额为 0"
    exit 1
fi

# ============ 步骤 3: 检查并授权 ============
echo "步骤 3: 检查授权额度..."
ALLOWANCE=$(cast call $TOKEN_CONTRACT "allowance(address,address)(uint256)" $USER_ADDRESS $VAULT_CONTRACT --rpc-url $RPC_URL 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "❌ 无法获取授权额度"
    exit 1
fi

echo "当前授权额度: $ALLOWANCE wei"
echo ""

# 将十六进制转换为十进制进行比较
ALLOWANCE_DEC=$(cast --to-dec $ALLOWANCE 2>/dev/null || echo "0")
DEPOSIT_AMOUNT_DEC=$(cast --to-dec $DEPOSIT_AMOUNT 2>/dev/null || echo "0")

# 授权（如果需要）
# 检查授权额度是否足够（使用数值比较）
# 如果授权额度为 0 或小于充值金额，则需要授权
NEED_APPROVE=false
if [ "$ALLOWANCE" == "0x0" ] || [ "$ALLOWANCE" == "0" ] || [ -z "$ALLOWANCE" ]; then
    NEED_APPROVE=true
    echo "授权额度为 0，需要授权"
elif [ "$ALLOWANCE_DEC" -lt "$DEPOSIT_AMOUNT_DEC" ]; then
    NEED_APPROVE=true
    echo "授权额度不足，需要授权"
fi

if [ "$NEED_APPROVE" == "true" ]; then
    echo "授权合约使用代币..."
    echo "授权金额: $DEPOSIT_AMOUNT wei"
    
    APPROVE_TX=$(cast send $TOKEN_CONTRACT \
        "approve(address,uint256)" \
        $VAULT_CONTRACT $DEPOSIT_AMOUNT \
        --private-key $USER_PRIVATE_KEY \
        --rpc-url $RPC_URL \
        --legacy \
        2>&1)
    
    if [ $? -ne 0 ]; then
        echo "❌ 授权失败: $APPROVE_TX"
        exit 1
    fi
    
    # 提取交易哈希
    TX_HASH=$(echo $APPROVE_TX | grep -oE '0x[a-fA-F0-9]{64}' | head -1)
    echo "✅ 授权成功！"
    if [ -n "$TX_HASH" ]; then
        echo "   交易哈希: $TX_HASH"
        echo "   查看: https://testnet.bscscan.com/tx/$TX_HASH"
    else
        echo "   交易: $APPROVE_TX"
    fi
    echo ""
    
    # 等待交易确认
    echo "等待交易确认..."
    sleep 5
else
    echo "✅ 授权额度充足，跳过授权步骤"
    echo ""
fi

# ============ 步骤 4: 充值 ============
echo "步骤 4: 充值到合约..."
echo "充值金额: 50 tokens ($DEPOSIT_AMOUNT wei)"
echo "Deposit ID: $DEPOSIT_ID"
echo ""

# 调用 deposit 函数
DEPOSIT_TX=$(cast send $VAULT_CONTRACT \
    "deposit(uint256,bytes32)" \
    $DEPOSIT_AMOUNT $DEPOSIT_ID \
    --private-key $USER_PRIVATE_KEY \
    --rpc-url $RPC_URL \
    --legacy \
    2>&1)

if [ $? -ne 0 ]; then
    echo "❌ 充值失败: $DEPOSIT_TX"
    exit 1
fi

echo "✅ 充值成功！"
echo "   交易: $DEPOSIT_TX"
echo ""

# 提取交易哈希（如果输出格式包含）
TX_HASH=$(echo $DEPOSIT_TX | grep -oE '0x[a-fA-F0-9]{64}' | head -1)
if [ -n "$TX_HASH" ]; then
    echo "交易哈希: $TX_HASH"
    echo "查看: https://testnet.bscscan.com/tx/$TX_HASH"
    echo ""
fi

# ============ 步骤 5: 验证 ============
echo "步骤 5: 验证充值结果..."
sleep 3

# 检查用户在合约中的余额
VAULT_BALANCE=$(cast call $VAULT_CONTRACT "balances(address)(uint256)" $USER_ADDRESS --rpc-url $RPC_URL 2>/dev/null)
if [ $? -eq 0 ]; then
    echo "✅ 用户在合约中的余额: $VAULT_BALANCE wei"
else
    echo "⚠️  无法获取合约余额，请手动检查"
fi

# 检查 depositId 是否已使用
USED=$(cast call $VAULT_CONTRACT "usedDepositIds(bytes32)(bool)" $DEPOSIT_ID --rpc-url $RPC_URL 2>/dev/null)
if [ $? -eq 0 ]; then
    if [ "$USED" == "true" ]; then
        echo "✅ Deposit ID 已标记为已使用"
    else
        echo "⚠️  Deposit ID 未标记为已使用"
    fi
fi

echo ""
echo "=========================================="
echo "充值完成！"
echo "=========================================="
echo "合约地址: $VAULT_CONTRACT"
echo "用户地址: $USER_ADDRESS"
echo "充值金额: 50 tokens"
echo "Deposit ID: $DEPOSIT_ID"
if [ -n "$TX_HASH" ]; then
    echo "交易哈希: $TX_HASH"
fi
echo "=========================================="
