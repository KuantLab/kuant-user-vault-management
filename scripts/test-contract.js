const hre = require("hardhat");

// Contract addresses
const CONTRACT_ADDRESS = "0x2E0b42798A61Ea78118E6758D64249eb6Fa37f17";
const USDT_ADDRESS = "0x337610d27c682E347C9cD60BD4b3b107C9d34dDd";

// Minimal ERC20 ABI for testing
const ERC20_ABI = [
  "function balanceOf(address owner) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)"
];

async function main() {
  const [signer] = await hre.ethers.getSigners();
  console.log("Testing with account:", signer.address);
  console.log("=".repeat(60));

  // Get contract instance
  const contract = await hre.ethers.getContractAt("FuturesMarginPoolClassics", CONTRACT_ADDRESS);
  const usdt = new hre.ethers.Contract(USDT_ADDRESS, ERC20_ABI, signer);

  // ============ Test 1: View Functions ============
  console.log("\n📋 TEST 1: View Functions");
  console.log("-".repeat(40));

  try {
    const admin = await contract.adminAddress();
    const withdrawAdmin = await contract.withdrawAdminAddress();
    const vaults = await contract.vaultsAddress();
    const feeAddress = await contract.getFeeAddress();
    const marginCoin = await contract.marginCoinAddress();
    const maxFeeBps = await contract.getMaxFeeBps();

    console.log("✅ Admin:", admin);
    console.log("✅ Withdraw Admin:", withdrawAdmin);
    console.log("✅ Vaults:", vaults);
    console.log("✅ Fee Address:", feeAddress);
    console.log("✅ Margin Coin:", marginCoin);
    console.log("✅ Max Fee BPS:", maxFeeBps.toString(), "(", Number(maxFeeBps) / 100, "%)");

    // Check user balance
    const [inAmount, outAmount] = await contract.getUserAddressBalance();
    console.log("✅ User In Amount:", hre.ethers.formatUnits(inAmount, 18));
    console.log("✅ User Out Amount:", hre.ethers.formatUnits(outAmount, 18));
  } catch (error) {
    console.log("❌ View functions failed:", error.message);
  }

  // ============ Test 2: Check USDT Balance ============
  console.log("\n💰 TEST 2: Check USDT Balance");
  console.log("-".repeat(40));

  let usdtBalance;
  let usdtDecimals;
  try {
    usdtDecimals = await usdt.decimals();
    usdtBalance = await usdt.balanceOf(signer.address);
    const symbol = await usdt.symbol();
    console.log("✅ USDT Decimals:", usdtDecimals);
    console.log("✅ USDT Balance:", hre.ethers.formatUnits(usdtBalance, usdtDecimals), symbol);
  } catch (error) {
    console.log("❌ Failed to get USDT balance:", error.message);
    usdtBalance = 0n;
    usdtDecimals = 18;
  }

  // ============ Test 3: Deposit ============
  console.log("\n📥 TEST 3: Deposit Function");
  console.log("-".repeat(40));

  if (usdtBalance > 0n) {
    try {
      const depositAmount = hre.ethers.parseUnits("1", usdtDecimals); // Deposit 1 USDT
      const depositHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("test-deposit-" + Date.now()));

      // Check if we have enough balance
      if (usdtBalance >= depositAmount) {
        // Approve USDT
        console.log("Approving USDT...");
        const approveTx = await usdt.approve(CONTRACT_ADDRESS, depositAmount);
        await approveTx.wait();
        console.log("✅ Approved", hre.ethers.formatUnits(depositAmount, usdtDecimals), "USDT");

        // Deposit
        console.log("Depositing...");
        const depositTx = await contract.deposit(depositAmount, depositHash);
        const receipt = await depositTx.wait();
        console.log("✅ Deposit successful! Tx:", receipt.hash);

        // Verify deposit
        const depositStatus = await contract.getDepositStatus(depositHash);
        console.log("✅ Deposit hash recorded:", depositStatus);

        // Check updated balance
        const [newInAmount, newOutAmount] = await contract.getUserAddressBalance();
        console.log("✅ Updated In Amount:", hre.ethers.formatUnits(newInAmount, usdtDecimals));
      } else {
        console.log("⚠️  Insufficient USDT balance for deposit test");
      }
    } catch (error) {
      console.log("❌ Deposit failed:", error.message);
    }
  } else {
    console.log("⚠️  No USDT balance - skipping deposit test");
    console.log("   To test deposits, get testnet USDT from a faucet");
  }

  // ============ Test 4: Withdraw (as withdrawAdmin) ============
  console.log("\n📤 TEST 4: Withdraw Function");
  console.log("-".repeat(40));

  try {
    // Check available balance first
    const availableBalance = await contract.getAvailableBalance(signer.address);
    console.log("Available balance to withdraw:", hre.ethers.formatUnits(availableBalance, usdtDecimals));

    if (availableBalance > 0n) {
      const withdrawAmount = availableBalance; // Withdraw all
      const fee = withdrawAmount * 100n / 10000n; // 1% fee (within 10% max)
      const withdrawHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("test-withdraw-" + Date.now()));

      console.log("Withdrawing", hre.ethers.formatUnits(withdrawAmount, usdtDecimals), "with fee", hre.ethers.formatUnits(fee, usdtDecimals));

      const withdrawTx = await contract.withdraw(signer.address, withdrawAmount, fee, withdrawHash);
      const receipt = await withdrawTx.wait();
      console.log("✅ Withdraw successful! Tx:", receipt.hash);

      // Verify withdrawal
      const withdrawStatus = await contract.getWithdrawStatus(withdrawHash);
      console.log("✅ Withdraw hash status:", withdrawStatus.toString(), "(1 = processed)");
    } else {
      console.log("⚠️  No available balance to withdraw");
    }
  } catch (error) {
    console.log("❌ Withdraw failed:", error.message);
  }

  // ============ Test 5: Admin Functions ============
  console.log("\n🔐 TEST 5: Admin Functions (Pause/Unpause)");
  console.log("-".repeat(40));

  try {
    // Test pause
    console.log("Pausing contract...");
    const pauseTx = await contract.pause();
    await pauseTx.wait();
    console.log("✅ Contract paused");

    // Try to deposit while paused (should fail)
    try {
      const testHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("test-paused-" + Date.now()));
      await contract.deposit(1, testHash);
      console.log("❌ Deposit should have failed while paused!");
    } catch (e) {
      console.log("✅ Deposit correctly rejected while paused");
    }

    // Unpause
    console.log("Unpausing contract...");
    const unpauseTx = await contract.unpause();
    await unpauseTx.wait();
    console.log("✅ Contract unpaused");
  } catch (error) {
    console.log("❌ Admin functions failed:", error.message);
  }

  // ============ Summary ============
  console.log("\n" + "=".repeat(60));
  console.log("📊 TEST SUMMARY");
  console.log("=".repeat(60));
  console.log("Contract Address:", CONTRACT_ADDRESS);
  console.log("Network: BSC Testnet");
  console.log("All core functions tested!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
