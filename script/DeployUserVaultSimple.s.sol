// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {UserVault} from "../src/UserVault.sol";

/**
 * @title DeployUserVaultSimple
 * @notice 简化版 UserVault 合约部署脚本
 * @dev 直接在 run() 函数中设置部署参数，适合快速部署
 */
contract DeployUserVaultSimple is Script {
    function run() public returns (UserVault vault) {
        // ============ 部署参数配置 ============
        // 请根据实际情况修改以下参数
        
        // ERC20 代币地址（例如 USDC）
        // 主网 USDC: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
        // Sepolia 测试网: 使用部署的 Mock 代币地址
        address tokenAddress = vm.envOr("TOKEN_ADDRESS", address(0));
        if (tokenAddress == address(0)) {
            // 默认测试地址（请修改为实际地址）
            tokenAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
            console.log("Using default token address:", tokenAddress);
        }
        
        // Owner 地址数组
        // 请替换为实际的 Owner 地址
        address[] memory owners = new address[](3);
        owners[0] = vm.envOr("OWNER_1", address(0x1111111111111111111111111111111111111111));
        owners[1] = vm.envOr("OWNER_2", address(0x2222222222222222222222222222222222222222));
        owners[2] = vm.envOr("OWNER_3", address(0x3333333333333333333333333333333333333333));
        
        // 最少确认数（必须 <= owners.length）
        // 例如：3 个 owners，需要 2 个确认 = 2-of-3 多签
        uint256 requiredConfirmations = vm.envOr("REQUIRED_CONFIRMATIONS", uint256(2));
        
        // ============ 参数验证 ============
        require(tokenAddress != address(0), "Invalid token address");
        require(owners.length > 0, "Owners array cannot be empty");
        require(
            requiredConfirmations > 0 && requiredConfirmations <= owners.length,
            "Invalid required confirmations"
        );
        
        // 验证 owners 中没有重复或零地址
        for (uint256 i = 0; i < owners.length; i++) {
            require(owners[i] != address(0), "Owner cannot be zero address");
            for (uint256 j = i + 1; j < owners.length; j++) {
                require(owners[i] != owners[j], "Duplicate owner address");
            }
        }
        
        // ============ 输出部署信息 ============
        console.log("==========================================");
        console.log("Deploying UserVault Contract");
        console.log("==========================================");
        console.log("Token Address:", tokenAddress);
        console.log("Owners Count:", owners.length);
        console.log("Required Confirmations:", requiredConfirmations);
        console.log("Owners:");
        for (uint256 i = 0; i < owners.length; i++) {
            console.log("  [%d]:", i, owners[i]);
        }
        console.log("==========================================");
        
        // ============ 部署合约 ============
        vm.startBroadcast();
        
        vault = new UserVault(tokenAddress, owners, requiredConfirmations);
        
        vm.stopBroadcast();
        
        // ============ 输出部署结果 ============
        console.log("==========================================");
        console.log("Deployment Successful!");
        console.log("==========================================");
        console.log("Contract Address:", address(vault));
        console.log("Token Address:", address(vault.token()));
        console.log("Required Confirmations:", vault.requiredConfirmations());
        console.log("Owner Count:", vault.getOwnerCount());
        console.log("==========================================");
        
        return vault;
    }
}
