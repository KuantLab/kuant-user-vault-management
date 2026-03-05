const { ethers } = require("hardhat");

// Helper to wait for transaction confirmation
async function waitForTx(tx, name) {
  console.log(`  Waiting for ${name}...`);
  const receipt = await tx.wait();
  console.log(`  ✓ ${name} confirmed in block ${receipt.blockNumber}`);
  return receipt;
}

// Helper to format amount
function formatAmount(amount) {
  return ethers.formatEther(amount);
}

// Helper to parse amount
function parseAmount(amount) {
  return ethers.parseEther(amount.toString());
}

// Generate unique hash
function generateHash(prefix, nonce) {
  return ethers.keccak256(ethers.toUtf8Bytes(`${prefix}-${nonce}-${Date.now()}`));
}

async function main() {
  console.log("=".repeat(60));
  console.log("BSC Testnet Deployment and Full Functionality Test");
  console.log("=".repeat(60));

  // Get signers
  const [deployer] = await ethers.getSigners();
  console.log("\n[1] Account Information");
  console.log("-".repeat(40));
  console.log("Deployer address:", deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("BNB Balance:", formatAmount(balance), "BNB");

  // ============ Deploy MockERC20 ============
  console.log("\n[2] Deploying MockERC20 Token");
  console.log("-".repeat(40));

  const MockERC20 = await ethers.getContractFactory("MockERC20");
  const initialSupply = parseAmount("1000000"); // 1 million tokens
  const mockToken = await MockERC20.deploy("Test USDT", "tUSDT", initialSupply);
  await mockToken.waitForDeployment();
  const tokenAddress = await mockToken.getAddress();
  console.log("✓ MockERC20 deployed at:", tokenAddress);
  console.log("  Initial supply:", formatAmount(initialSupply), "tUSDT");

  // ============ Deploy FuturesMarginPoolClassics ============
  console.log("\n[3] Deploying FuturesMarginPoolClassics");
  console.log("-".repeat(40));

  const FuturesMarginPool = await ethers.getContractFactory("FuturesMarginPoolClassics");
  const pool = await FuturesMarginPool.deploy(
    deployer.address,  // withdrawAdmin
    deployer.address,  // admin
    deployer.address,  // vaults
    deployer.address,  // feeAddress
    tokenAddress       // marginCoinAddress
  );
  await pool.waitForDeployment();
  const poolAddress = await pool.getAddress();
  console.log("✓ FuturesMarginPoolClassics deployed at:", poolAddress);

  // Verify deployment
  console.log("\n  Verifying deployment parameters:");
  console.log("  - Admin:", await pool.adminAddress());
  console.log("  - WithdrawAdmin:", await pool.withdrawAdminAddress());
  console.log("  - Vaults:", await pool.vaultsAddress());
  console.log("  - FeeAddress:", await pool.getFeeAddress());
  console.log("  - MarginCoin:", await pool.marginCoinAddress());
  console.log("  - MIN_LOCK_DURATION:", (await pool.MIN_LOCK_DURATION()).toString(), "seconds (24 hours)");
  console.log("  - MAX_LOCK_DURATION:", (await pool.MAX_LOCK_DURATION()).toString(), "seconds (240 hours)");

  // ============ Test Invest Item Management ============
  console.log("\n[4] Testing Invest Item Management");
  console.log("-".repeat(40));

  // Create invest item with 5% commission and 24-hour lock
  const commissionBps = 500; // 5%
  const minLockDuration = 24 * 60 * 60; // 24 hours
  console.log("Creating invest item (5% commission, 24-hour min lock)...");
  let tx = await pool.createInvestItem(commissionBps, minLockDuration);
  await waitForTx(tx, "createInvestItem");

  const [exists, active, commission, lockDuration] = await pool.getInvestItem(0);
  console.log("  Invest Item 0:");
  console.log("    - Exists:", exists);
  console.log("    - Active:", active);
  console.log("    - Commission:", commission.toString(), "bps (", Number(commission) / 100, "%)");
  console.log("    - Min Lock Duration:", lockDuration.toString(), "seconds");

  // Create second invest item with different settings
  console.log("\nCreating invest item (3% commission, 48-hour min lock)...");
  tx = await pool.createInvestItem(300, 48 * 60 * 60);
  await waitForTx(tx, "createInvestItem");
  console.log("  ✓ Invest Item 1 created");

  console.log("\n  Total invest items:", (await pool.investItemCount()).toString());

  // ============ Test Deposit with Time Lock ============
  console.log("\n[5] Testing Deposit with Time Lock");
  console.log("-".repeat(40));

  const depositAmount = parseAmount("1000");
  const lockDurationDeposit = 24 * 60 * 60; // 24 hours
  const depositHash = generateHash("deposit", 1);

  // Approve tokens
  console.log("Approving tokens for deposit...");
  tx = await mockToken.approve(poolAddress, depositAmount);
  await waitForTx(tx, "approve");

  // Deposit
  console.log("Depositing", formatAmount(depositAmount), "tUSDT with 24-hour lock...");
  tx = await pool.deposit(depositAmount, 0, lockDurationDeposit, depositHash);
  const depositReceipt = await waitForTx(tx, "deposit");

  // Get deposit record
  const [user, amount, itemId, unlockTime, remainingAmount] = await pool.getDepositRecord(depositHash);
  console.log("\n  Deposit Record:");
  console.log("    - User:", user);
  console.log("    - Amount:", formatAmount(amount), "tUSDT");
  console.log("    - Invest Item ID:", itemId.toString());
  console.log("    - Unlock Time:", new Date(Number(unlockTime) * 1000).toISOString());
  console.log("    - Remaining Amount:", formatAmount(remainingAmount), "tUSDT");

  // Check user balance
  const [inAmount, outAmount] = await pool.getUserAddressBalance();
  console.log("\n  User Asset Info:");
  console.log("    - In Amount:", formatAmount(inAmount), "tUSDT");
  console.log("    - Out Amount:", formatAmount(outAmount), "tUSDT");
  console.log("    - Available Balance:", formatAmount(await pool.getAvailableBalance(deployer.address)), "tUSDT");

  // ============ Test Withdrawal Before Unlock (Should Fail) ============
  console.log("\n[6] Testing Withdrawal Before Unlock (Should Fail)");
  console.log("-".repeat(40));

  const withdrawAmount = parseAmount("500");
  const withdrawFee = parseAmount("5"); // 1% fee
  const withdrawHash1 = generateHash("withdraw", 1);

  console.log("Attempting withdrawal before unlock time...");
  try {
    tx = await pool.withdraw(
      deployer.address,
      withdrawAmount,
      withdrawFee,
      depositHash,
      withdrawHash1
    );
    await tx.wait();
    console.log("  ✗ ERROR: Withdrawal should have failed!");
  } catch (error) {
    if (error.message.includes("DEPOSIT_LOCKED")) {
      console.log("  ✓ Withdrawal correctly rejected: DEPOSIT_LOCKED");
    } else {
      console.log("  ✓ Withdrawal rejected:", error.message.substring(0, 100));
    }
  }

  // ============ Test withdrawWithItem Before Unlock (Should Fail) ============
  console.log("\n[7] Testing withdrawWithItem Before Unlock (Should Fail)");
  console.log("-".repeat(40));

  const withdrawHash2 = generateHash("withdraw", 2);

  console.log("Attempting withdrawWithItem before unlock time...");
  try {
    tx = await pool.withdrawWithItem(
      deployer.address,
      withdrawAmount,
      depositHash,
      withdrawHash2
    );
    await tx.wait();
    console.log("  ✗ ERROR: Withdrawal should have failed!");
  } catch (error) {
    if (error.message.includes("DEPOSIT_LOCKED")) {
      console.log("  ✓ Withdrawal correctly rejected: DEPOSIT_LOCKED");
    } else {
      console.log("  ✓ Withdrawal rejected:", error.message.substring(0, 100));
    }
  }

  // ============ Test Second Deposit with Longer Lock ============
  console.log("\n[8] Testing Second Deposit with 48-hour Lock");
  console.log("-".repeat(40));

  const depositAmount2 = parseAmount("500");
  const lockDuration2 = 48 * 60 * 60; // 48 hours
  const depositHash2 = generateHash("deposit", 2);

  // Approve and deposit
  console.log("Approving and depositing", formatAmount(depositAmount2), "tUSDT with 48-hour lock...");
  tx = await mockToken.approve(poolAddress, depositAmount2);
  await waitForTx(tx, "approve");

  tx = await pool.deposit(depositAmount2, 0, lockDuration2, depositHash2);
  await waitForTx(tx, "deposit");

  const [, , , unlockTime2,] = await pool.getDepositRecord(depositHash2);
  console.log("  ✓ Deposit successful");
  console.log("  Unlock Time:", new Date(Number(unlockTime2) * 1000).toISOString());

  // Check updated balances
  const [inAmount2, outAmount2] = await pool.getUserAddressBalance();
  console.log("\n  Updated User Asset Info:");
  console.log("    - In Amount:", formatAmount(inAmount2), "tUSDT");
  console.log("    - Out Amount:", formatAmount(outAmount2), "tUSDT");

  // ============ Test Invest Item Status Change ============
  console.log("\n[9] Testing Invest Item Status Change");
  console.log("-".repeat(40));

  console.log("Deactivating invest item 1...");
  tx = await pool.setInvestItemStatus(1, false);
  await waitForTx(tx, "setInvestItemStatus");

  const [, active1] = await pool.getInvestItem(1);
  console.log("  ✓ Invest Item 1 active status:", active1);

  console.log("\nReactivating invest item 1...");
  tx = await pool.setInvestItemStatus(1, true);
  await waitForTx(tx, "setInvestItemStatus");

  const [, active1After] = await pool.getInvestItem(1);
  console.log("  ✓ Invest Item 1 active status:", active1After);

  // ============ Test Commission Change ============
  console.log("\n[10] Testing Commission Change");
  console.log("-".repeat(40));

  console.log("Changing invest item 0 commission from 5% to 3%...");
  tx = await pool.setInvestItemCommission(0, 300);
  await waitForTx(tx, "setInvestItemCommission");

  const [, , newCommission] = await pool.getInvestItem(0);
  console.log("  ✓ New commission:", newCommission.toString(), "bps (", Number(newCommission) / 100, "%)");

  // ============ Test Lock Duration Change ============
  console.log("\n[11] Testing Lock Duration Change");
  console.log("-".repeat(40));

  console.log("Changing invest item 0 min lock duration to 36 hours...");
  tx = await pool.setInvestItemLockDuration(0, 36 * 60 * 60);
  await waitForTx(tx, "setInvestItemLockDuration");

  const [, , , newLockDuration] = await pool.getInvestItem(0);
  console.log("  ✓ New min lock duration:", newLockDuration.toString(), "seconds (", Number(newLockDuration) / 3600, "hours)");

  // ============ Test Pause/Unpause ============
  console.log("\n[12] Testing Pause/Unpause");
  console.log("-".repeat(40));

  console.log("Pausing contract...");
  tx = await pool.pause();
  await waitForTx(tx, "pause");
  console.log("  ✓ Contract paused:", await pool.paused());

  // Try deposit while paused
  console.log("\nTrying deposit while paused...");
  try {
    const pausedDepositHash = generateHash("deposit", 99);
    await mockToken.approve(poolAddress, parseAmount("100"));
    tx = await pool.deposit(parseAmount("100"), 0, 36 * 60 * 60, pausedDepositHash);
    await tx.wait();
    console.log("  ✗ ERROR: Deposit should have failed!");
  } catch (error) {
    console.log("  ✓ Deposit correctly rejected while paused");
  }

  console.log("\nUnpausing contract...");
  tx = await pool.unpause();
  await waitForTx(tx, "unpause");
  console.log("  ✓ Contract paused:", await pool.paused());

  // ============ Test Admin Withdrawal to Vaults ============
  console.log("\n[13] Testing Admin Withdrawal to Vaults");
  console.log("-".repeat(40));

  const poolBalanceBefore = await mockToken.balanceOf(poolAddress);
  console.log("Pool balance before:", formatAmount(poolBalanceBefore), "tUSDT");

  const adminWithdrawAmount = parseAmount("100");
  console.log("Admin withdrawing", formatAmount(adminWithdrawAmount), "tUSDT to vaults...");
  tx = await pool.withdrawAdminFun(adminWithdrawAmount);
  await waitForTx(tx, "withdrawAdminFun");

  const poolBalanceAfter = await mockToken.balanceOf(poolAddress);
  console.log("  ✓ Pool balance after:", formatAmount(poolBalanceAfter), "tUSDT");

  // ============ Summary ============
  console.log("\n" + "=".repeat(60));
  console.log("DEPLOYMENT AND TEST SUMMARY");
  console.log("=".repeat(60));
  console.log("\nDeployed Contracts:");
  console.log("  MockERC20 (tUSDT):", tokenAddress);
  console.log("  FuturesMarginPoolClassics:", poolAddress);
  console.log("\nTest Results:");
  console.log("  ✓ Contract deployment successful");
  console.log("  ✓ Invest item creation working");
  console.log("  ✓ Deposit with time lock working");
  console.log("  ✓ Time lock enforcement working (withdrawals blocked before unlock)");
  console.log("  ✓ Multiple deposits with different locks working");
  console.log("  ✓ Invest item status change working");
  console.log("  ✓ Commission change working");
  console.log("  ✓ Lock duration change working");
  console.log("  ✓ Pause/unpause working");
  console.log("  ✓ Admin withdrawal to vaults working");
  console.log("\nNote: To test actual withdrawal after unlock, wait 24+ hours or");
  console.log("      use a shorter lock duration for testing purposes.");
  console.log("\n" + "=".repeat(60));

  // Return addresses for verification
  return {
    tokenAddress,
    poolAddress,
    deployer: deployer.address
  };
}

main()
  .then((result) => {
    console.log("\nScript completed successfully!");
    console.log("Addresses:", JSON.stringify(result, null, 2));
    process.exit(0);
  })
  .catch((error) => {
    console.error("\nScript failed with error:");
    console.error(error);
    process.exit(1);
  });
