# 交易哈希提取问题修复说明

## 问题描述

脚本输出的交易哈希与实际提交的交易哈希不一致：
- **脚本输出**: `0x8541781d7417859172de70b25e2bbfc059ae9c8804d0646b0b8dfa34a971d5e0`
- **实际交易哈希**: `0x493dd301b126f972d7934d692933afa175a6b49e024373ea1cadcf14672de514`

## 问题原因

`cast send` 命令的输出格式可能包含多个哈希值（例如内部交易、日志等），简单的 `grep` 提取可能会获取到错误的哈希。

## 解决方案

已更新脚本，使用以下改进方法：

1. **使用 `--json` 参数**：获取结构化的 JSON 输出
2. **使用 `jq` 解析**：从 JSON 中提取 `transactionHash` 字段
3. **回退机制**：如果 JSON 解析失败，使用改进的文本提取方法

## 修复后的脚本

### add_operator.sh

```bash
# 使用 --json 参数获取结构化输出
SUBMIT_TX=$(cast send $VAULT_CONTRACT \
    "submitProposal(uint8,bytes)" \
    0 \
    $PROPOSAL_DATA \
    --private-key $OWNER_PRIVATE_KEY \
    --rpc-url $RPC_URL \
    --legacy \
    --json \
    2>&1)

# 优先从 JSON 中提取
TX_HASH=$(echo "$SUBMIT_TX" | jq -r '.transactionHash' 2>/dev/null)

# 如果失败，使用文本提取作为回退
if [ -z "$TX_HASH" ] || [ "$TX_HASH" == "null" ]; then
    TX_HASH=$(echo "$SUBMIT_TX" | grep -oE '0x[a-fA-F0-9]{64}' | head -1)
fi
```

## 验证交易

根据您提供的实际交易哈希 `0x493dd301b126f972d7934d692933afa175a6b49e024373ea1cadcf14672de514`，可以在 BSCScan 上查看：

```
https://testnet.bscscan.com/tx/0x493dd301b126f972d7934d692933afa175a6b49e024373ea1cadcf14672de514
```

## 验证 Operator 状态

使用以下命令验证 Operator 是否已成功添加：

```bash
cast call 0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E \
    "operators(address)(bool)" \
    0x07e3aabd2d4d5dcec107ef9555dc0e5ef24f62b3 \
    --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545
```

返回 `true` 表示 Operator 已成功添加。

## 注意事项

1. **需要安装 jq**：如果系统没有安装 `jq`，脚本会回退到文本提取方法
   ```bash
   # macOS
   brew install jq
   
   # Ubuntu/Debian
   sudo apt-get install jq
   ```

2. **网络延迟**：如果 RPC 响应慢，可能需要等待更长时间

3. **交易确认**：交易提交后需要等待区块确认，通常需要几秒钟

## 手动提取交易哈希

如果脚本仍然无法正确提取，可以手动从 `cast send` 的完整输出中查找：

```bash
cast send 0x65E57362a45A7bF1Bf64C8770b5386Ce3f9FC35E \
    "submitProposal(uint8,bytes)" \
    0 \
    $PROPOSAL_DATA \
    --private-key $OWNER_PRIVATE_KEY \
    --rpc-url $RPC_URL \
    --legacy \
    --json | jq -r '.transactionHash'
```

或者查看完整的 JSON 输出：

```bash
cast send ... --json | jq .
```
