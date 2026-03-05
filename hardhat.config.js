require("@nomicfoundation/hardhat-toolbox");
require('@openzeppelin/hardhat-upgrades');
require('dotenv').config()
const fs = require('fs');

const PRIVATE_KEY = process.env.PRIVATE_KEY || "0x0000000000000000000000000000000000000000000000000000000000000001";

// Build networks config conditionally
const networks = {
  hardhat: {
    chainId: 1337,
    loggingEnabled: true,
    // 不指定accounts，让hardhat使用默认的20个测试账户
  },
};

// Only add BSC network if RPC URL is configured
if (process.env.BSC_RPC_URL) {
  networks.bsc = {
    url: process.env.BSC_RPC_URL,
    accounts: [PRIVATE_KEY],
  };
}

// Only add BSC Testnet if RPC URL is configured
if (process.env.BSC_TESTNET_RPC_URL) {
  networks.bscTestnet = {
    url: process.env.BSC_TESTNET_RPC_URL,
    accounts: [PRIVATE_KEY],
  };
}

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.6.12",

  networks,
  contractSizer: {
    alphaSort: true,
    disambiguatePaths: false,
    runOnCompile: true,
    strict: false,
    only: []
  },
  etherscan:{
    apiKey: {
      bsc: "",
      polygon: ""
    }
  },
  sourcify: {
    enabled: true
  },
};
