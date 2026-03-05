#!/bin/bash

# 用户充值脚本 - BSC 测试网
# 功能：用户充值 50 个 token 到 UserVault 合约

echo "=========================================="
echo "UserVault 用户充值脚本"
echo "=========================================="

# ============ 配置参数 ============
# 合约地址（已部署）
VAULT_CONTRACT="0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E"

# Token 地址
TOKEN_CONTRACT="0x76CeE3E0FDF715F50B15Ca83c0ed8C454c7F88A3"

# 用户私钥
USER_PRIVATE_KEY="39b36efe563e1d284dcc5cfe7c5b00207e8fef1bd41d343ee5c1cb0dc805a668"

# 充值金额（50 个 token）
DEPOSIT_TOKEN_AMOUNT="50"

# BSC 测试网 RPC
RPC_URL="https://data-seed-prebsc-1-s1.binance.org:8545"

# 生成唯一的 depositId（使用时间戳 + 随机数）
DEPOSIT_ID=$(cast keccak256 $(echo -n "$(date +%s)$RANDOM" | xxd -p))

# ============ 自动检测 Token Decimals ============
echo "检测 Token 小数位数..."
TOKEN_DECIMALS=$(cast call $TOKEN_CONTRACT "decimals()(uint8)" --rpc-url $RPC_URL 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "⚠️  无法获取 Token decimals，默认使用 18 位小数"
    TOKEN_DECIMALS=18
else
    echo "Token decimals: $TOKEN_DECIMALS"
fi

# 计算充值金额（50 * 10^decimals）
DEPOSIT_AMOUNT=$(python3 -c "print(int($DEPOSIT_TOKEN_AMOUNT * (10 ** $TOKEN_DECIMALS)))" 2>/dev/null || echo "50000000000000000000")
echo "充值金额 (wei): $DEPOSIT_AMOUNT"
echo ""

echo "合约地址: $VAULT_CONTRACT"
echo "Token 地址: $TOKEN_CONTRACT"
echo "充值金额: $DEPOSIT_TOKEN_AMOUNT tokens"
echo "Token Decimals: $TOKEN_DECIMALS"
echo "Deposit ID: $DEPOSIT_ID"
echo ""

# ============ 步骤 1: 检查用户余额 ============
echo "步骤 1: 检查用户 Token 余额..."
USER_ADDRESS=$(cast wallet address $USER_PRIVATE_KEY)
echo "用户地址: $USER_ADDRESS"

USER_BALANCE=$(cast call $TOKEN_CONTRACT "balanceOf(address)(uint256)" $USER_ADDRESS --rpc-url $RPC_URL 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "❌ 无法获取用户余额，请检查 Token 合约地址和网络连接"
    exit 1
fi

# 使用 Python 计算余额（考虑 decimals）
USER_BALANCE_DISPLAY=$(python3 -c "print($USER_BALANCE / (10 ** $TOKEN_DECIMALS))" 2>/dev/null || echo "N/A")
echo "用户 Token 余额: $USER_BALANCE_DISPLAY tokens"
echo ""

# 检查余额是否足够
if [ $(cast --to-dec $USER_BALANCE 2>/dev/null || echo "0") -lt $(cast --to-dec $DEPOSIT_AMOUNT 2>/dev/null || echo "0") ]; then
    echo "❌ 余额不足！需要: $DEPOSIT_TOKEN_AMOUNT tokens"
    echo "   当前余额: $USER_BALANCE_DISPLAY tokens"
    exit 1
fi

# ============ 步骤 2: 检查授权额度 ============
echo "步骤 2: 检查授权额度..."
ALLOWANCE=$(cast call $TOKEN_CONTRACT "allowance(address,address)(uint256)" $USER_ADDRESS $VAULT_CONTRACT --rpc-url $RPC_URL 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "❌ 无法获取授权额度"
    exit 1
fi

ALLOWANCE_DISPLAY=$(python3 -c "print($ALLOWANCE / (10 ** $TOKEN_DECIMALS))" 2>/dev/null || echo "N/A")
echo "当前授权额度: $ALLOWANCE_DISPLAY tokens"
echo ""

# ============ 步骤 3: 授权合约使用代币 ============
if [ $(cast --to-dec $ALLOWANCE 2>/dev/null || echo "0") -lt $(cast --to-dec $DEPOSIT_AMOUNT 2>/dev/null || echo "0") ]; then
    echo "步骤 3: 授权合约使用代币..."
    echo "授权金额: $DEPOSIT_TOKEN_AMOUNT tokens"
    
    # 授权交易
    APPROVE_TX=$(cast send $TOKEN_CONTRACT \
        "approve(address,uint256)" \
        $VAULT_CONTRACT $DEPOSIT_AMOUNT \
        --private-key $USER_PRIVATE_KEY \
        --rpc-url $RPC_URL \
        --legacy \
        --json 2>&1)
    
    if [ $? -ne 0 ]; then
        echo "❌ 授权失败: $APPROVE_TX"
        exit 1
    fi
    
    # 提取交易哈希
    TX_HASH=$(echo $APPROVE_TX | jq -r '.transactionHash' 2>/dev/null || echo "N/A")
    echo "✅ 授权成功！"
    echo "   交易哈希: $TX_HASH"
    echo "   查看: https://testnet.bscscan.com/tx/$TX_HASH"
    echo ""
    
    # 等待交易确认
    echo "等待交易确认..."
    sleep 5
else
    echo "✅ 授权额度充足，跳过授权步骤"
    echo ""
fi

# ============ 步骤 4: 充值到合约 ============
echo "步骤 4: 充值到合约..."
echo "充值金额: $DEPOSIT_TOKEN_AMOUNT tokens"
echo "Deposit ID: $DEPOSIT_ID"
echo ""

# 调用 deposit 函数
# deposit(uint256 amount, bytes32 depositId)
DEPOSIT_TX=$(cast send $VAULT_CONTRACT \
    "deposit(uint256,bytes32)" \
    $DEPOSIT_AMOUNT $DEPOSIT_ID \
    --private-key $USER_PRIVATE_KEY \
    --rpc-url $RPC_URL \
    --legacy \
    --json 2>&1)

if [ $? -ne 0 ]; then
    echo "❌ 充值失败: $DEPOSIT_TX"
    exit 1
fi

# 提取交易哈希
TX_HASH=$(echo $DEPOSIT_TX | jq -r '.transactionHash' 2>/dev/null || echo "N/A")
echo "✅ 充值成功！"
echo "   交易哈希: $TX_HASH"
echo "   查看: https://testnet.bscscan.com/tx/$TX_HASH"
echo ""

# ============ 步骤 5: 验证充值结果 ============
echo "步骤 5: 验证充值结果..."
sleep 3

# 检查用户在合约中的余额
VAULT_BALANCE=$(cast call $VAULT_CONTRACT "balances(address)(uint256)" $USER_ADDRESS --rpc-url $RPC_URL 2>/dev/null)
if [ $? -eq 0 ]; then
    VAULT_BALANCE_DISPLAY=$(python3 -c "print($VAULT_BALANCE / (10 ** $TOKEN_DECIMALS))" 2>/dev/null || echo "N/A")
    echo "✅ 用户在合约中的余额: $VAULT_BALANCE_DISPLAY tokens"
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
echo "充值金额: $DEPOSIT_TOKEN_AMOUNT tokens"
echo "Deposit ID: $DEPOSIT_ID"
echo "交易哈希: $TX_HASH"
echo "=========================================="
