// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {UserVault} from "../src/UserVault.sol";

/**
 * @title DeployUserVault
 * @notice UserVault 合约部署脚本
 * @dev 支持从环境变量或命令行参数读取部署配置
 */
contract DeployUserVault is Script {
    // 部署参数
    address public tokenAddress;
    address[] public owners;
    uint256 public requiredConfirmations;
    
    function setUp() public {
        // 从环境变量读取配置（如果存在）
        // 可以通过 .env 文件设置，或使用命令行参数覆盖
        
        // Token 地址（例如 USDC）
        // 主网 USDC: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
        // 测试网可以使用 Mock 代币地址
        string memory tokenEnv = vm.envOr("TOKEN_ADDRESS", string(""));
        if (bytes(tokenEnv).length > 0) {
            tokenAddress = vm.parseAddress(tokenEnv);
        }
        
        // Owners 地址（逗号分隔）
        // 例如: OWNERS=0x123...,0x456...,0x789...
        string memory ownersEnv = vm.envOr("OWNERS", string(""));
        if (bytes(ownersEnv).length > 0) {
            owners = _parseAddressArray(ownersEnv);
        }
        
        // 最少确认数
        string memory confirmationsEnv = vm.envOr("REQUIRED_CONFIRMATIONS", string(""));
        if (bytes(confirmationsEnv).length > 0) {
            requiredConfirmations = vm.parseUint(confirmationsEnv);
        }
    }
    
    /**
     * @notice 使用自定义参数部署（用于命令行参数）
     * @param _tokenAddress ERC20 代币地址
     * @param _owners Owner 地址数组
     * @param _requiredConfirmations 最少确认数
     */
    function deploy(
        address _tokenAddress,
        address[] memory _owners,
        uint256 _requiredConfirmations
    ) public returns (UserVault vault) {
        tokenAddress = _tokenAddress;
        owners = _owners;
        requiredConfirmations = _requiredConfirmations;
        return run();
    }
    
    function run() public returns (UserVault vault) {
        // 如果环境变量未设置，使用默认值（仅用于测试）
        // 生产环境应该通过环境变量或命令行参数提供
        if (tokenAddress == address(0)) {
            console.log("Warning: TOKEN_ADDRESS not set, using default test address");
            // 这里可以设置一个默认的测试地址，或者直接 revert
            revert("TOKEN_ADDRESS must be set via environment variable or --sig");
        }
        
        if (owners.length == 0) {
            console.log("Warning: OWNERS not set, using default test owners");
            // 这里可以设置默认的测试 owners，或者直接 revert
            revert("OWNERS must be set via environment variable or --sig");
        }
        
        if (requiredConfirmations == 0) {
            console.log("Warning: REQUIRED_CONFIRMATIONS not set, using default value");
            // 默认使用 owners.length / 2 + 1（超过半数）
            requiredConfirmations = owners.length / 2 + 1;
        }
        
        // 验证参数
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
        
        // 开始广播交易
        vm.startBroadcast();
        
        // 部署合约
        vault = new UserVault(tokenAddress, owners, requiredConfirmations);
        
        // 停止广播
        vm.stopBroadcast();
        
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
    
    /**
     * @notice 解析逗号分隔的地址字符串
     * @param addressesStr 逗号分隔的地址字符串
     * @return addresses 地址数组
     */
    function _parseAddressArray(string memory addressesStr) internal view returns (address[] memory addresses) {
        // 计算地址数量
        uint256 count = 1;
        bytes memory strBytes = bytes(addressesStr);
        for (uint256 i = 0; i < strBytes.length; i++) {
            if (strBytes[i] == bytes1(",")) {
                count++;
            }
        }
        
        addresses = new address[](count);
        uint256 currentIndex = 0;
        uint256 startIndex = 0;
        
        for (uint256 i = 0; i <= strBytes.length; i++) {
            if (i == strBytes.length || strBytes[i] == bytes1(",")) {
                // 提取地址字符串
                bytes memory addrBytes = new bytes(i - startIndex);
                for (uint256 j = 0; j < addrBytes.length; j++) {
                    addrBytes[j] = strBytes[startIndex + j];
                }
                
                // 转换为地址（去除前后空格）
                string memory addrStr = _trimString(string(addrBytes));
                addresses[currentIndex] = vm.parseAddress(addrStr);
                
                currentIndex++;
                startIndex = i + 1;
            }
        }
    }
    
    /**
     * @notice 去除字符串前后空格
     * @param str 输入字符串
     * @return trimmed 去除空格后的字符串
     */
    function _trimString(string memory str) internal pure returns (string memory trimmed) {
        bytes memory strBytes = bytes(str);
        uint256 start = 0;
        uint256 end = strBytes.length;
        
        // 跳过前导空格
        while (start < end && strBytes[start] == bytes1(" ")) {
            start++;
        }
        
        // 跳过后导空格
        while (end > start && strBytes[end - 1] == bytes1(" ")) {
            end--;
        }
        
        // 提取有效部分
        bytes memory cleanBytes = new bytes(end - start);
        for (uint256 i = 0; i < cleanBytes.length; i++) {
            cleanBytes[i] = strBytes[start + i];
        }
        
        return string(cleanBytes);
    }
}
