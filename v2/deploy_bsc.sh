#!/bin/bash

# BSC 测试网部署脚本
# 使用前请确保：
# 1. 钱包有足够的 BNB 支付 Gas 费
# 2. 网络连接正常
##### bsc-testnet
# [Success] Hash: 0xed5d018b199aec8f031ee78b559c3bd52907225caff3d12fa962e42e1b979afa
# Contract Address: 0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E
# Block: 86074634
# Paid: 0.0003458063 BNB (3458063 gas * 0.1 gwei)

echo "=========================================="
echo "部署 UserVault 到 BSC 测试网"
echo "=========================================="

# 部署参数
TOKEN_ADDRESS="0x76CeE3E0FDF715F50B15Ca83c0ed8C454c7F88A3"
PRIVATE_KEY="6f4058fa7ab22b3c83290a6bca1be7d43ed911d4ffe5f3d1003d413fdfd425c7"
WALLET_ADDRESS="0x5ebFeFdE3dcE75EAf436dFc9B02a402714d13C63"

# BSC 测试网 RPC URL（尝试多个）
RPC_URLS=(
    "https://data-seed-prebsc-1-s1.binance.org:8545"
    "https://data-seed-prebsc-2-s1.binance.org:8545"
    "https://bsc-testnet.public.blastapi.io"
    "https://bsc-testnet.blockpi.network/v1/rpc/public"
)

echo "Token 地址: $TOKEN_ADDRESS"
echo "钱包地址: $WALLET_ADDRESS"
echo ""

# 尝试部署
for RPC_URL in "${RPC_URLS[@]}"; do
    echo "尝试使用 RPC: $RPC_URL"
    echo "----------------------------------------"
    
    forge script script/DeployBSC.s.sol:DeployBSC \
        --rpc-url "$RPC_URL" \
        --private-key "$PRIVATE_KEY" \
        --broadcast \
        -vv
    
    if [ $? -eq 0 ]; then
        echo "=========================================="
        echo "部署成功！"
        echo "=========================================="
        exit 0
    else
        echo "RPC $RPC_URL 失败，尝试下一个..."
        echo ""
    fi
done

echo "=========================================="
echo "所有 RPC 都失败，请检查网络连接"
echo "=========================================="
exit 1
