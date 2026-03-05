const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);
  console.log("Account balance:", (await hre.ethers.provider.getBalance(deployer.address)).toString());

  // Deployment parameters
  const withdrawAdmin = deployer.address;
  const admin = deployer.address;
  const vaults = deployer.address;
  const feeAddress = deployer.address;
  const marginCoinAddress = "0x337610d27c682E347C9cD60BD4b3b107C9d34dDd"; // BSC Testnet USDT

  console.log("\nDeployment parameters:");
  console.log("  withdrawAdmin:", withdrawAdmin);
  console.log("  admin:", admin);
  console.log("  vaults:", vaults);
  console.log("  feeAddress:", feeAddress);
  console.log("  marginCoinAddress:", marginCoinAddress);

  // Deploy
  const FuturesMarginPoolClassics = await hre.ethers.getContractFactory("FuturesMarginPoolClassics");
  const contract = await FuturesMarginPoolClassics.deploy(
    withdrawAdmin,
    admin,
    vaults,
    feeAddress,
    marginCoinAddress
  );

  await contract.waitForDeployment();
  const contractAddress = await contract.getAddress();

  console.log("\nFuturesMarginPoolClassics deployed to:", contractAddress);
  console.log("\nVerify with:");
  console.log(`npx hardhat verify --network bscTestnet ${contractAddress} ${withdrawAdmin} ${admin} ${vaults} ${feeAddress} ${marginCoinAddress}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
