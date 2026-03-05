// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {UserVault} from "../src/UserVault.sol";

/**
 * @title DeployBSC
 * @notice BSC 测试网部署脚本
 */
contract DeployBSC is Script {
    function run() public returns (UserVault vault) {
        // ============ BSC 测试网部署参数 ============
        
        // Token 合约地址
        address tokenAddress = 0x76CeE3E0FDF715F50B15Ca83c0ed8C454c7F88A3;
        
        // Owner 地址（使用部署钱包地址作为 Owner）
        // 如果需要多个 Owner，可以添加更多地址
        address[] memory owners = new address[](1);
        owners[0] = 0x5ebFeFdE3dcE75EAf436dFc9B02a402714d13C63;
        
        // 最少确认数（1 个 Owner，需要 1 个确认 = 1-of-1）
        uint256 requiredConfirmations = 1;
        
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
        console.log("Deploying UserVault to BSC Testnet");
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
        console.log("BSC Testnet Explorer:");
        console.log("https://testnet.bscscan.com/address/", address(vault));
        console.log("==========================================");
        
        return vault;
    }
}
