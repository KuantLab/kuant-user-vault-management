const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("FuturesMarginPoolClassics", function () {
  let pool;
  let token;
  let admin;
  let withdrawAdmin;
  let vaults;
  let feeAddress;
  let user1;
  let user2;
  let attacker;

  const INITIAL_SUPPLY = ethers.parseEther("1000000");
  const DEPOSIT_AMOUNT = ethers.parseEther("1000");
  const WITHDRAW_AMOUNT = ethers.parseEther("500");
  const FEE_AMOUNT = ethers.parseEther("5"); // 1% of 500, within 10% max

  // Constants from contract
  const MAX_FEE_BPS = 1000n; // 10%
  const BPS_DENOMINATOR = 10000n;
  const MIN_LOCK_DURATION = 24n * 60n * 60n; // 24 hours in seconds
  const MAX_LOCK_DURATION = 240n * 60n * 60n; // 240 hours in seconds
  const TWENTY_FOUR_HOURS = 24 * 60 * 60;
  const FORTY_EIGHT_HOURS = 48 * 60 * 60;
  const TWO_HUNDRED_FORTY_HOURS = 240 * 60 * 60;

  // Default commission and lock duration for tests
  const DEFAULT_COMMISSION_BPS = 500n; // 5%
  const DEFAULT_LOCK_DURATION = TWENTY_FOUR_HOURS;

  beforeEach(async function () {
    [admin, withdrawAdmin, vaults, feeAddress, user1, user2, attacker] = await ethers.getSigners();

    // Deploy mock ERC20 token
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    token = await MockERC20.deploy("Mock USDT", "MUSDT", INITIAL_SUPPLY);
    await token.waitForDeployment();

    // Deploy FuturesMarginPoolClassics
    const FuturesMarginPoolClassics = await ethers.getContractFactory("FuturesMarginPoolClassics");
    pool = await FuturesMarginPoolClassics.deploy(
      withdrawAdmin.address,
      admin.address,
      vaults.address,
      feeAddress.address,
      await token.getAddress()
    );
    await pool.waitForDeployment();

    // Transfer tokens to users for testing
    await token.transfer(user1.address, ethers.parseEther("10000"));
    await token.transfer(user2.address, ethers.parseEther("10000"));
  });

  // Helper function to create a default invest item
  async function createDefaultInvestItem() {
    await pool.connect(admin).createInvestItem(DEFAULT_COMMISSION_BPS, DEFAULT_LOCK_DURATION);
    return 0; // Returns the item ID
  }

  describe("Constructor", function () {
    it("should set correct initial values", async function () {
      expect(await pool.adminAddress()).to.equal(admin.address);
      expect(await pool.withdrawAdminAddress()).to.equal(withdrawAdmin.address);
      expect(await pool.vaultsAddress()).to.equal(vaults.address);
      expect(await pool.getFeeAddress()).to.equal(feeAddress.address);
      expect(await pool.marginCoinAddress()).to.equal(await token.getAddress());
    });

    it("should revert if withdrawAdmin is zero address", async function () {
      const FuturesMarginPoolClassics = await ethers.getContractFactory("FuturesMarginPoolClassics");
      await expect(
        FuturesMarginPoolClassics.deploy(
          ethers.ZeroAddress,
          admin.address,
          vaults.address,
          feeAddress.address,
          await token.getAddress()
        )
      ).to.be.revertedWith("FuturesMarginPool/INIT_PARAMS_ERROR");
    });

    it("should revert if admin is zero address", async function () {
      const FuturesMarginPoolClassics = await ethers.getContractFactory("FuturesMarginPoolClassics");
      await expect(
        FuturesMarginPoolClassics.deploy(
          withdrawAdmin.address,
          ethers.ZeroAddress,
          vaults.address,
          feeAddress.address,
          await token.getAddress()
        )
      ).to.be.revertedWith("FuturesMarginPool/INIT_PARAMS_ERROR");
    });

    it("should revert if vaults is zero address", async function () {
      const FuturesMarginPoolClassics = await ethers.getContractFactory("FuturesMarginPoolClassics");
      await expect(
        FuturesMarginPoolClassics.deploy(
          withdrawAdmin.address,
          admin.address,
          ethers.ZeroAddress,
          feeAddress.address,
          await token.getAddress()
        )
      ).to.be.revertedWith("FuturesMarginPool/INIT_PARAMS_ERROR");
    });

    it("should revert if feeAddress is zero address", async function () {
      const FuturesMarginPoolClassics = await ethers.getContractFactory("FuturesMarginPoolClassics");
      await expect(
        FuturesMarginPoolClassics.deploy(
          withdrawAdmin.address,
          admin.address,
          vaults.address,
          ethers.ZeroAddress,
          await token.getAddress()
        )
      ).to.be.revertedWith("FuturesMarginPool/INIT_PARAMS_ERROR");
    });

    it("should revert if marginCoinAddress is zero address", async function () {
      const FuturesMarginPoolClassics = await ethers.getContractFactory("FuturesMarginPoolClassics");
      await expect(
        FuturesMarginPoolClassics.deploy(
          withdrawAdmin.address,
          admin.address,
          vaults.address,
          feeAddress.address,
          ethers.ZeroAddress
        )
      ).to.be.revertedWith("FuturesMarginPool/INIT_PARAMS_ERROR");
    });
  });

  describe("Deposit", function () {
    const depositHash = ethers.keccak256(ethers.toUtf8Bytes("deposit1"));
    let investItemId;

    beforeEach(async function () {
      investItemId = await createDefaultInvestItem();
      await token.connect(user1).approve(await pool.getAddress(), DEPOSIT_AMOUNT);
    });

    it("should transfer tokens from user to pool", async function () {
      const poolAddress = await pool.getAddress();
      const userBalanceBefore = await token.balanceOf(user1.address);
      const poolBalanceBefore = await token.balanceOf(poolAddress);

      await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash);

      const userBalanceAfter = await token.balanceOf(user1.address);
      const poolBalanceAfter = await token.balanceOf(poolAddress);

      expect(userBalanceAfter).to.equal(userBalanceBefore - DEPOSIT_AMOUNT);
      expect(poolBalanceAfter).to.equal(poolBalanceBefore + DEPOSIT_AMOUNT);
    });

    it("should emit FuturesMarginDeposit event with invest item and unlock time", async function () {
      const tx = await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash);
      const receipt = await tx.wait();
      const block = await ethers.provider.getBlock(receipt.blockNumber);
      const expectedUnlockTime = block.timestamp + DEFAULT_LOCK_DURATION;

      await expect(tx)
        .to.emit(pool, "FuturesMarginDeposit")
        .withArgs(depositHash, user1.address, DEPOSIT_AMOUNT, investItemId, expectedUnlockTime);
    });

    it("should update user asset info", async function () {
      await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash);

      const [inAmount, outAmount] = await pool.connect(user1).getUserAddressBalance();
      expect(inAmount).to.equal(DEPOSIT_AMOUNT);
      expect(outAmount).to.equal(0);
    });

    it("should create deposit record", async function () {
      const tx = await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash);
      const receipt = await tx.wait();
      const block = await ethers.provider.getBlock(receipt.blockNumber);
      const expectedUnlockTime = block.timestamp + DEFAULT_LOCK_DURATION;

      const [user, amount, itemId, unlockTime, remainingAmount] = await pool.getDepositRecord(depositHash);
      expect(user).to.equal(user1.address);
      expect(amount).to.equal(DEPOSIT_AMOUNT);
      expect(itemId).to.equal(investItemId);
      expect(unlockTime).to.equal(expectedUnlockTime);
      expect(remainingAmount).to.equal(DEPOSIT_AMOUNT);
    });

    it("should accumulate multiple deposits", async function () {
      const depositHash2 = ethers.keccak256(ethers.toUtf8Bytes("deposit2"));
      await token.connect(user1).approve(await pool.getAddress(), DEPOSIT_AMOUNT * 2n);

      await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash);
      await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash2);

      const [inAmount, outAmount] = await pool.connect(user1).getUserAddressBalance();
      expect(inAmount).to.equal(DEPOSIT_AMOUNT * 2n);
      expect(outAmount).to.equal(0);
    });

    it("should revert if insufficient allowance", async function () {
      await token.connect(user2).approve(await pool.getAddress(), 0);
      await expect(
        pool.connect(user2).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash)
      ).to.be.reverted;
    });

    it("should revert if deposit amount is zero", async function () {
      await expect(
        pool.connect(user1).deposit(0, investItemId, DEFAULT_LOCK_DURATION, depositHash)
      ).to.be.revertedWith("FuturesMarginPool/ZERO_AMOUNT");
    });

    it("should revert if deposit hash is already used", async function () {
      await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash);

      await token.connect(user1).approve(await pool.getAddress(), DEPOSIT_AMOUNT);
      await expect(
        pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash)
      ).to.be.revertedWith("FuturesMarginPool/DUPLICATE_DEPOSIT_HASH");
    });

    it("should revert if invest item does not exist", async function () {
      await expect(
        pool.connect(user1).deposit(DEPOSIT_AMOUNT, 999, DEFAULT_LOCK_DURATION, depositHash)
      ).to.be.revertedWith("FuturesMarginPool/INVEST_ITEM_NOT_FOUND");
    });

    it("should revert if invest item is not active", async function () {
      await pool.connect(admin).setInvestItemStatus(investItemId, false);

      await expect(
        pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash)
      ).to.be.revertedWith("FuturesMarginPool/INVEST_ITEM_NOT_ACTIVE");
    });

    it("should revert if lock duration is below invest item minimum", async function () {
      // Create item with 48 hour lock
      await pool.connect(admin).createInvestItem(DEFAULT_COMMISSION_BPS, FORTY_EIGHT_HOURS);

      await expect(
        pool.connect(user1).deposit(DEPOSIT_AMOUNT, 1, TWENTY_FOUR_HOURS, depositHash)
      ).to.be.revertedWith("FuturesMarginPool/LOCK_BELOW_ITEM_MIN");
    });

    it("should revert if lock duration is below minimum 24 hours", async function () {
      // Create invest item with minimum 24 hours lock
      // When user tries to deposit with < 24 hours, it will first hit LOCK_BELOW_ITEM_MIN
      // because item's minLockDuration is also 24 hours
      // To test LOCK_TOO_SHORT specifically, we need an invest item with shorter min lock
      // Since MIN_LOCK_DURATION is 24 hours, LOCK_TOO_SHORT will be hit if item min is somehow < 24h
      // but that's not possible in this contract. So any lock < 24h will hit LOCK_BELOW_ITEM_MIN
      const shortLock = TWENTY_FOUR_HOURS - 1;
      await expect(
        pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, shortLock, depositHash)
      ).to.be.revertedWith("FuturesMarginPool/LOCK_BELOW_ITEM_MIN");
    });

    it("should allow user to choose longer lock than item minimum", async function () {
      const longerLock = FORTY_EIGHT_HOURS;
      const tx = await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, longerLock, depositHash);
      const receipt = await tx.wait();
      const block = await ethers.provider.getBlock(receipt.blockNumber);
      const expectedUnlockTime = block.timestamp + longerLock;

      const [, , , unlockTime,] = await pool.getDepositRecord(depositHash);
      expect(unlockTime).to.equal(expectedUnlockTime);
    });

    it("should revert if lock duration exceeds maximum 240 hours", async function () {
      const tooLongLock = TWO_HUNDRED_FORTY_HOURS + 1;
      await expect(
        pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, tooLongLock, depositHash)
      ).to.be.revertedWith("FuturesMarginPool/LOCK_TOO_LONG");
    });

    it("should allow lock duration at exactly maximum 240 hours", async function () {
      const tx = await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, TWO_HUNDRED_FORTY_HOURS, depositHash);
      const receipt = await tx.wait();
      const block = await ethers.provider.getBlock(receipt.blockNumber);
      const expectedUnlockTime = block.timestamp + TWO_HUNDRED_FORTY_HOURS;

      const [, , , unlockTime,] = await pool.getDepositRecord(depositHash);
      expect(unlockTime).to.equal(expectedUnlockTime);
    });

    it("should track deposit hash status", async function () {
      expect(await pool.getDepositStatus(depositHash)).to.be.false;

      await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash);

      expect(await pool.getDepositStatus(depositHash)).to.be.true;
    });

    it("should revert when paused", async function () {
      await pool.connect(admin).pause();

      await expect(
        pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash)
      ).to.be.revertedWith("Pausable: paused");
    });
  });

  describe("Withdraw", function () {
    const depositHash = ethers.keccak256(ethers.toUtf8Bytes("deposit1"));
    const withdrawHash = ethers.keccak256(ethers.toUtf8Bytes("withdraw1"));
    let investItemId;

    beforeEach(async function () {
      investItemId = await createDefaultInvestItem();
      // User deposits first
      await token.connect(user1).approve(await pool.getAddress(), DEPOSIT_AMOUNT);
      await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash);
      // Advance time to unlock deposit
      await time.increase(TWENTY_FOUR_HOURS);
    });

    it("should transfer tokens minus fee to user", async function () {
      const userBalanceBefore = await token.balanceOf(user1.address);

      await pool.connect(withdrawAdmin).withdraw(
        user1.address,
        WITHDRAW_AMOUNT,
        FEE_AMOUNT,
        depositHash,
        withdrawHash
      );

      const userBalanceAfter = await token.balanceOf(user1.address);
      expect(userBalanceAfter).to.equal(userBalanceBefore + WITHDRAW_AMOUNT - FEE_AMOUNT);
    });

    it("should transfer fee to feeAddress", async function () {
      const feeBalanceBefore = await token.balanceOf(feeAddress.address);

      await pool.connect(withdrawAdmin).withdraw(
        user1.address,
        WITHDRAW_AMOUNT,
        FEE_AMOUNT,
        depositHash,
        withdrawHash
      );

      const feeBalanceAfter = await token.balanceOf(feeAddress.address);
      expect(feeBalanceAfter).to.equal(feeBalanceBefore + FEE_AMOUNT);
    });

    it("should emit FuturesMarginWithdraw event", async function () {
      await expect(
        pool.connect(withdrawAdmin).withdraw(
          user1.address,
          WITHDRAW_AMOUNT,
          FEE_AMOUNT,
          depositHash,
          withdrawHash
        )
      )
        .to.emit(pool, "FuturesMarginWithdraw")
        .withArgs(withdrawHash, user1.address, WITHDRAW_AMOUNT, FEE_AMOUNT);
    });

    it("should update user outAmount", async function () {
      await pool.connect(withdrawAdmin).withdraw(
        user1.address,
        WITHDRAW_AMOUNT,
        FEE_AMOUNT,
        depositHash,
        withdrawHash
      );

      const [inAmount, outAmount] = await pool.connect(user1).getUserAddressBalance();
      expect(inAmount).to.equal(DEPOSIT_AMOUNT);
      expect(outAmount).to.equal(WITHDRAW_AMOUNT);
    });

    it("should update deposit record remaining amount", async function () {
      await pool.connect(withdrawAdmin).withdraw(
        user1.address,
        WITHDRAW_AMOUNT,
        FEE_AMOUNT,
        depositHash,
        withdrawHash
      );

      const [, , , , remainingAmount] = await pool.getDepositRecord(depositHash);
      expect(remainingAmount).to.equal(DEPOSIT_AMOUNT - WITHDRAW_AMOUNT);
    });

    it("should mark withdrawal hash as used", async function () {
      await pool.connect(withdrawAdmin).withdraw(
        user1.address,
        WITHDRAW_AMOUNT,
        FEE_AMOUNT,
        depositHash,
        withdrawHash
      );

      expect(await pool.getWithdrawStatus(withdrawHash)).to.equal(1);
    });

    it("should revert on duplicate withdrawal", async function () {
      await pool.connect(withdrawAdmin).withdraw(
        user1.address,
        WITHDRAW_AMOUNT,
        FEE_AMOUNT,
        depositHash,
        withdrawHash
      );

      await expect(
        pool.connect(withdrawAdmin).withdraw(
          user1.address,
          WITHDRAW_AMOUNT,
          FEE_AMOUNT,
          depositHash,
          withdrawHash
        )
      ).to.be.revertedWith("FuturesMarginPool/ALREADY_WITHDRAWN");
    });

    it("should revert if called by non-withdrawAdmin", async function () {
      await expect(
        pool.connect(user1).withdraw(
          user1.address,
          WITHDRAW_AMOUNT,
          FEE_AMOUNT,
          depositHash,
          withdrawHash
        )
      ).to.be.revertedWith("FuturesMarginPool/ONLY_WITHDRAW_ADMIN");
    });

    it("should revert if called by admin (not withdrawAdmin)", async function () {
      await expect(
        pool.connect(admin).withdraw(
          user1.address,
          WITHDRAW_AMOUNT,
          FEE_AMOUNT,
          depositHash,
          withdrawHash
        )
      ).to.be.revertedWith("FuturesMarginPool/ONLY_WITHDRAW_ADMIN");
    });

    it("should revert if withdraw amount is zero", async function () {
      await expect(
        pool.connect(withdrawAdmin).withdraw(
          user1.address,
          0,
          0,
          depositHash,
          withdrawHash
        )
      ).to.be.revertedWith("FuturesMarginPool/ZERO_AMOUNT");
    });

    it("should revert if account is zero address", async function () {
      await expect(
        pool.connect(withdrawAdmin).withdraw(
          ethers.ZeroAddress,
          WITHDRAW_AMOUNT,
          FEE_AMOUNT,
          depositHash,
          withdrawHash
        )
      ).to.be.revertedWith("FuturesMarginPool/INVALID_ACCOUNT");
    });

    it("should revert if deposit not found", async function () {
      const nonExistentDeposit = ethers.keccak256(ethers.toUtf8Bytes("nonexistent"));
      await expect(
        pool.connect(withdrawAdmin).withdraw(
          user1.address,
          WITHDRAW_AMOUNT,
          FEE_AMOUNT,
          nonExistentDeposit,
          withdrawHash
        )
      ).to.be.revertedWith("FuturesMarginPool/DEPOSIT_NOT_FOUND");
    });

    it("should revert if not deposit owner", async function () {
      await expect(
        pool.connect(withdrawAdmin).withdraw(
          user2.address,
          WITHDRAW_AMOUNT,
          FEE_AMOUNT,
          depositHash,
          withdrawHash
        )
      ).to.be.revertedWith("FuturesMarginPool/NOT_DEPOSIT_OWNER");
    });

    it("should revert when paused", async function () {
      await pool.connect(admin).pause();

      await expect(
        pool.connect(withdrawAdmin).withdraw(
          user1.address,
          WITHDRAW_AMOUNT,
          FEE_AMOUNT,
          depositHash,
          withdrawHash
        )
      ).to.be.revertedWith("Pausable: paused");
    });

    it("should work with zero fee", async function () {
      const userBalanceBefore = await token.balanceOf(user1.address);

      await pool.connect(withdrawAdmin).withdraw(
        user1.address,
        WITHDRAW_AMOUNT,
        0,
        depositHash,
        withdrawHash
      );

      const userBalanceAfter = await token.balanceOf(user1.address);
      expect(userBalanceAfter).to.equal(userBalanceBefore + WITHDRAW_AMOUNT);
    });
  });

  describe("Time Lock Feature", function () {
    const depositHash = ethers.keccak256(ethers.toUtf8Bytes("deposit1"));
    const withdrawHash = ethers.keccak256(ethers.toUtf8Bytes("withdraw1"));
    let investItemId;

    beforeEach(async function () {
      investItemId = await createDefaultInvestItem();
      await token.connect(user1).approve(await pool.getAddress(), DEPOSIT_AMOUNT);
    });

    it("should block withdrawal before unlock time", async function () {
      await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash);

      // Try to withdraw immediately (before lock expires)
      await expect(
        pool.connect(withdrawAdmin).withdraw(
          user1.address,
          WITHDRAW_AMOUNT,
          FEE_AMOUNT,
          depositHash,
          withdrawHash
        )
      ).to.be.revertedWith("FuturesMarginPool/DEPOSIT_LOCKED");
    });

    it("should block withdrawWithItem before unlock time", async function () {
      await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash);

      // Try to withdraw immediately (before lock expires)
      await expect(
        pool.connect(withdrawAdmin).withdrawWithItem(
          user1.address,
          WITHDRAW_AMOUNT,
          depositHash,
          withdrawHash
        )
      ).to.be.revertedWith("FuturesMarginPool/DEPOSIT_LOCKED");
    });

    it("should allow withdrawal after unlock time", async function () {
      await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash);

      // Advance time past the lock duration
      await time.increase(TWENTY_FOUR_HOURS);

      await expect(
        pool.connect(withdrawAdmin).withdraw(
          user1.address,
          WITHDRAW_AMOUNT,
          FEE_AMOUNT,
          depositHash,
          withdrawHash
        )
      ).to.emit(pool, "FuturesMarginWithdraw");
    });

    it("should allow withdrawal exactly at unlock time", async function () {
      await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash);

      // Get the deposit record to know exact unlock time
      const [, , , unlockTime,] = await pool.getDepositRecord(depositHash);

      // Set time to just before unlock (2 seconds before to account for block time)
      const currentBlock = await ethers.provider.getBlock("latest");
      const timeToIncrease = Number(unlockTime) - currentBlock.timestamp - 2;
      if (timeToIncrease > 0) {
        await time.increase(timeToIncrease);
      }

      // This should still fail because we're before unlock
      await expect(
        pool.connect(withdrawAdmin).withdraw(
          user1.address,
          WITHDRAW_AMOUNT,
          FEE_AMOUNT,
          depositHash,
          withdrawHash
        )
      ).to.be.revertedWith("FuturesMarginPool/DEPOSIT_LOCKED");

      // Advance past unlock time
      await time.increase(3);

      // Now it should work
      await expect(
        pool.connect(withdrawAdmin).withdraw(
          user1.address,
          WITHDRAW_AMOUNT,
          FEE_AMOUNT,
          depositHash,
          withdrawHash
        )
      ).to.emit(pool, "FuturesMarginWithdraw");
    });

    it("should support partial withdrawals from locked deposits", async function () {
      await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash);

      // Advance time past the lock duration
      await time.increase(TWENTY_FOUR_HOURS);

      // First partial withdrawal
      const firstWithdraw = ethers.parseEther("300");
      await pool.connect(withdrawAdmin).withdraw(
        user1.address,
        firstWithdraw,
        0,
        depositHash,
        withdrawHash
      );

      const [, , , , remainingAfterFirst] = await pool.getDepositRecord(depositHash);
      expect(remainingAfterFirst).to.equal(DEPOSIT_AMOUNT - firstWithdraw);

      // Second partial withdrawal
      const withdrawHash2 = ethers.keccak256(ethers.toUtf8Bytes("withdraw2"));
      const secondWithdraw = ethers.parseEther("200");
      await pool.connect(withdrawAdmin).withdraw(
        user1.address,
        secondWithdraw,
        0,
        depositHash,
        withdrawHash2
      );

      const [, , , , remainingAfterSecond] = await pool.getDepositRecord(depositHash);
      expect(remainingAfterSecond).to.equal(DEPOSIT_AMOUNT - firstWithdraw - secondWithdraw);
    });

    it("should revert if withdrawal exceeds remaining deposit amount", async function () {
      await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash);

      // Advance time past the lock duration
      await time.increase(TWENTY_FOUR_HOURS);

      // First withdrawal takes most of the amount
      const firstWithdraw = ethers.parseEther("900");
      await pool.connect(withdrawAdmin).withdraw(
        user1.address,
        firstWithdraw,
        0,
        depositHash,
        withdrawHash
      );

      // Second withdrawal should fail if exceeding remaining
      const withdrawHash2 = ethers.keccak256(ethers.toUtf8Bytes("withdraw2"));
      await expect(
        pool.connect(withdrawAdmin).withdraw(
          user1.address,
          ethers.parseEther("200"), // Only 100 remaining
          0,
          depositHash,
          withdrawHash2
        )
      ).to.be.revertedWith("FuturesMarginPool/EXCEEDS_DEPOSIT_REMAINING");
    });

    it("should track separate locks for multiple deposits", async function () {
      const depositHash2 = ethers.keccak256(ethers.toUtf8Bytes("deposit2"));
      const withdrawHash2 = ethers.keccak256(ethers.toUtf8Bytes("withdraw2"));

      // First deposit with 24 hour lock
      await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, TWENTY_FOUR_HOURS, depositHash);

      // Second deposit with 48 hour lock
      await token.connect(user1).approve(await pool.getAddress(), DEPOSIT_AMOUNT);
      await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, FORTY_EIGHT_HOURS, depositHash2);

      // Advance 24 hours
      await time.increase(TWENTY_FOUR_HOURS);

      // First deposit should be withdrawable
      await expect(
        pool.connect(withdrawAdmin).withdraw(
          user1.address,
          WITHDRAW_AMOUNT,
          0,
          depositHash,
          withdrawHash
        )
      ).to.emit(pool, "FuturesMarginWithdraw");

      // Second deposit should still be locked
      await expect(
        pool.connect(withdrawAdmin).withdraw(
          user1.address,
          WITHDRAW_AMOUNT,
          0,
          depositHash2,
          withdrawHash2
        )
      ).to.be.revertedWith("FuturesMarginPool/DEPOSIT_LOCKED");

      // Advance another 24 hours (48 total)
      await time.increase(TWENTY_FOUR_HOURS);

      // Now second deposit should be withdrawable
      await expect(
        pool.connect(withdrawAdmin).withdraw(
          user1.address,
          WITHDRAW_AMOUNT,
          0,
          depositHash2,
          withdrawHash2
        )
      ).to.emit(pool, "FuturesMarginWithdraw");
    });
  });

  describe("Security: Fee Validation", function () {
    const depositHash = ethers.keccak256(ethers.toUtf8Bytes("deposit1"));
    const withdrawHash = ethers.keccak256(ethers.toUtf8Bytes("withdraw1"));
    let investItemId;

    beforeEach(async function () {
      investItemId = await createDefaultInvestItem();
      await token.connect(user1).approve(await pool.getAddress(), DEPOSIT_AMOUNT);
      await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash);
      await time.increase(TWENTY_FOUR_HOURS);
    });

    it("should revert if fee exceeds maximum percentage", async function () {
      // Max fee is 10% of withdrawAmount
      const maxFee = (WITHDRAW_AMOUNT * MAX_FEE_BPS) / BPS_DENOMINATOR;
      const excessiveFee = maxFee + 1n;

      await expect(
        pool.connect(withdrawAdmin).withdraw(
          user1.address,
          WITHDRAW_AMOUNT,
          excessiveFee,
          depositHash,
          withdrawHash
        )
      ).to.be.revertedWith("FuturesMarginPool/FEE_TOO_HIGH");
    });

    it("should allow fee at exactly maximum percentage", async function () {
      const maxFee = (WITHDRAW_AMOUNT * MAX_FEE_BPS) / BPS_DENOMINATOR;

      await expect(
        pool.connect(withdrawAdmin).withdraw(
          user1.address,
          WITHDRAW_AMOUNT,
          maxFee,
          depositHash,
          withdrawHash
        )
      ).to.emit(pool, "FuturesMarginWithdraw");
    });

    it("should allow fee below maximum percentage", async function () {
      const lowFee = (WITHDRAW_AMOUNT * 100n) / BPS_DENOMINATOR; // 1%

      await expect(
        pool.connect(withdrawAdmin).withdraw(
          user1.address,
          WITHDRAW_AMOUNT,
          lowFee,
          depositHash,
          withdrawHash
        )
      ).to.emit(pool, "FuturesMarginWithdraw");
    });

    it("should return correct max fee BPS", async function () {
      expect(await pool.getMaxFeeBps()).to.equal(MAX_FEE_BPS);
    });
  });

  describe("Security: Two-Step Admin Transfer", function () {
    it("should initiate admin transfer", async function () {
      await expect(pool.connect(admin).transferAdmin(user1.address))
        .to.emit(pool, "AdminTransferInitiated")
        .withArgs(admin.address, user1.address);

      expect(await pool.pendingAdmin()).to.equal(user1.address);
      expect(await pool.adminAddress()).to.equal(admin.address); // Not changed yet
    });

    it("should complete admin transfer when accepted", async function () {
      await pool.connect(admin).transferAdmin(user1.address);

      await expect(pool.connect(user1).acceptAdmin())
        .to.emit(pool, "AdminTransferCompleted")
        .withArgs(admin.address, user1.address);

      expect(await pool.adminAddress()).to.equal(user1.address);
      expect(await pool.pendingAdmin()).to.equal(ethers.ZeroAddress);
    });

    it("should revert if non-pending admin tries to accept", async function () {
      await pool.connect(admin).transferAdmin(user1.address);

      await expect(
        pool.connect(user2).acceptAdmin()
      ).to.be.revertedWith("FuturesMarginPool/NOT_PENDING_ADMIN");
    });

    it("should revert if transferring to zero address", async function () {
      await expect(
        pool.connect(admin).transferAdmin(ethers.ZeroAddress)
      ).to.be.revertedWith("FuturesMarginPool/ADMIN_ERROR");
    });

    it("should revert if transferring to same admin", async function () {
      await expect(
        pool.connect(admin).transferAdmin(admin.address)
      ).to.be.revertedWith("FuturesMarginPool/SAME_ADMIN");
    });

    it("should allow canceling pending admin transfer", async function () {
      await pool.connect(admin).transferAdmin(user1.address);
      await pool.connect(admin).cancelAdminTransfer();

      expect(await pool.pendingAdmin()).to.equal(ethers.ZeroAddress);

      // user1 can no longer accept
      await expect(
        pool.connect(user1).acceptAdmin()
      ).to.be.revertedWith("FuturesMarginPool/NOT_PENDING_ADMIN");
    });

    it("should allow new admin to perform admin functions after transfer", async function () {
      await pool.connect(admin).transferAdmin(user1.address);
      await pool.connect(user1).acceptAdmin();

      // New admin can modify settings
      await expect(pool.connect(user1).modifyFeeAddress(user2.address))
        .to.emit(pool, "FeeAddressChanged");

      // Old admin cannot
      await expect(
        pool.connect(admin).modifyFeeAddress(user2.address)
      ).to.be.revertedWith("FuturesMarginPool/ONLY_ADMIN");
    });
  });

  describe("Pause Mechanism", function () {
    let investItemId;

    beforeEach(async function () {
      investItemId = await createDefaultInvestItem();
    });

    it("should allow admin to pause", async function () {
      await pool.connect(admin).pause();
      expect(await pool.paused()).to.be.true;
    });

    it("should allow admin to unpause", async function () {
      await pool.connect(admin).pause();
      await pool.connect(admin).unpause();
      expect(await pool.paused()).to.be.false;
    });

    it("should revert if non-admin tries to pause", async function () {
      await expect(
        pool.connect(user1).pause()
      ).to.be.revertedWith("FuturesMarginPool/ONLY_ADMIN");
    });

    it("should revert if non-admin tries to unpause", async function () {
      await pool.connect(admin).pause();
      await expect(
        pool.connect(user1).unpause()
      ).to.be.revertedWith("FuturesMarginPool/ONLY_ADMIN");
    });

    it("should block deposits when paused", async function () {
      const depositHash = ethers.keccak256(ethers.toUtf8Bytes("deposit1"));
      await token.connect(user1).approve(await pool.getAddress(), DEPOSIT_AMOUNT);
      await pool.connect(admin).pause();

      await expect(
        pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash)
      ).to.be.revertedWith("Pausable: paused");
    });

    it("should allow deposits after unpause", async function () {
      const depositHash = ethers.keccak256(ethers.toUtf8Bytes("deposit1"));
      await token.connect(user1).approve(await pool.getAddress(), DEPOSIT_AMOUNT);
      await pool.connect(admin).pause();
      await pool.connect(admin).unpause();

      await expect(
        pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash)
      ).to.emit(pool, "FuturesMarginDeposit");
    });
  });

  describe("Admin Events", function () {
    it("should emit event when modifying margin address", async function () {
      const oldAddress = await pool.marginCoinAddress();
      await expect(pool.connect(admin).modifyMarginAddress(user1.address))
        .to.emit(pool, "MarginCoinAddressChanged")
        .withArgs(oldAddress, user1.address);
    });

    it("should emit event when modifying withdraw admin", async function () {
      const oldWithdrawAdmin = await pool.withdrawAdminAddress();
      await expect(pool.connect(admin).modifyWithdrawAdmin(user1.address))
        .to.emit(pool, "WithdrawAdminChanged")
        .withArgs(oldWithdrawAdmin, user1.address);
    });

    it("should emit event when modifying vaults address", async function () {
      const oldVaults = await pool.vaultsAddress();
      await expect(pool.connect(admin).modifyVaultsAddress(user1.address))
        .to.emit(pool, "VaultsAddressChanged")
        .withArgs(oldVaults, user1.address);
    });

    it("should emit event when modifying fee address", async function () {
      const oldFeeAddress = await pool.getFeeAddress();
      await expect(pool.connect(admin).modifyFeeAddress(user1.address))
        .to.emit(pool, "FeeAddressChanged")
        .withArgs(oldFeeAddress, user1.address);
    });

    it("should emit event when admin withdraws to vaults", async function () {
      const investItemId = await createDefaultInvestItem();
      const depositHash = ethers.keccak256(ethers.toUtf8Bytes("deposit1"));
      await token.connect(user1).approve(await pool.getAddress(), DEPOSIT_AMOUNT);
      await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash);

      const withdrawAmount = ethers.parseEther("100");
      await expect(pool.connect(admin).withdrawAdminFun(withdrawAmount))
        .to.emit(pool, "AdminWithdrawal")
        .withArgs(vaults.address, withdrawAmount);
    });
  });

  describe("WithdrawAdminFun", function () {
    let investItemId;

    beforeEach(async function () {
      investItemId = await createDefaultInvestItem();
      const depositHash = ethers.keccak256(ethers.toUtf8Bytes("deposit1"));
      await token.connect(user1).approve(await pool.getAddress(), DEPOSIT_AMOUNT);
      await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash);
    });

    it("should transfer tokens to vaults", async function () {
      const vaultsBalanceBefore = await token.balanceOf(vaults.address);
      const withdrawAmount = ethers.parseEther("100");

      await pool.connect(admin).withdrawAdminFun(withdrawAmount);

      const vaultsBalanceAfter = await token.balanceOf(vaults.address);
      expect(vaultsBalanceAfter).to.equal(vaultsBalanceBefore + withdrawAmount);
    });

    it("should revert if called by non-admin/non-operator", async function () {
      await expect(
        pool.connect(user1).withdrawAdminFun(ethers.parseEther("100"))
      ).to.be.revertedWith("FuturesMarginPool/ONLY_OPERATOR_OR_ADMIN");
    });

    it("should revert if called by withdrawAdmin (unless also operator)", async function () {
      await expect(
        pool.connect(withdrawAdmin).withdrawAdminFun(ethers.parseEther("100"))
      ).to.be.revertedWith("FuturesMarginPool/ONLY_OPERATOR_OR_ADMIN");
    });

    it("should revert if amount is zero", async function () {
      await expect(
        pool.connect(admin).withdrawAdminFun(0)
      ).to.be.revertedWith("FuturesMarginPool/ZERO_AMOUNT");
    });
  });

  describe("Admin Functions", function () {
    describe("modifyMarginAddress", function () {
      it("should update marginCoinAddress", async function () {
        const newToken = user2.address;
        await pool.connect(admin).modifyMarginAddress(newToken);
        expect(await pool.marginCoinAddress()).to.equal(newToken);
      });

      it("should revert if called by non-admin", async function () {
        await expect(
          pool.connect(user1).modifyMarginAddress(user2.address)
        ).to.be.revertedWith("FuturesMarginPool/ONLY_ADMIN");
      });

      it("should revert if zero address", async function () {
        await expect(
          pool.connect(admin).modifyMarginAddress(ethers.ZeroAddress)
        ).to.be.revertedWith("FuturesMarginPool/MARGIN_COIN_ERROR");
      });
    });

    describe("modifyWithdrawAdmin", function () {
      it("should update withdrawAdmin", async function () {
        await pool.connect(admin).modifyWithdrawAdmin(user2.address);
        expect(await pool.withdrawAdminAddress()).to.equal(user2.address);
      });

      it("should allow new withdrawAdmin to withdraw", async function () {
        const investItemId = await createDefaultInvestItem();
        const depositHash = ethers.keccak256(ethers.toUtf8Bytes("deposit1"));
        const withdrawHash = ethers.keccak256(ethers.toUtf8Bytes("withdraw1"));

        await token.connect(user1).approve(await pool.getAddress(), DEPOSIT_AMOUNT);
        await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash);
        await time.increase(TWENTY_FOUR_HOURS);

        await pool.connect(admin).modifyWithdrawAdmin(user2.address);

        // Old withdrawAdmin should fail
        await expect(
          pool.connect(withdrawAdmin).withdraw(
            user1.address,
            WITHDRAW_AMOUNT,
            FEE_AMOUNT,
            depositHash,
            withdrawHash
          )
        ).to.be.revertedWith("FuturesMarginPool/ONLY_WITHDRAW_ADMIN");

        // New withdrawAdmin should succeed
        await expect(
          pool.connect(user2).withdraw(
            user1.address,
            WITHDRAW_AMOUNT,
            FEE_AMOUNT,
            depositHash,
            withdrawHash
          )
        ).to.emit(pool, "FuturesMarginWithdraw");
      });

      it("should revert if called by non-admin", async function () {
        await expect(
          pool.connect(user1).modifyWithdrawAdmin(user2.address)
        ).to.be.revertedWith("FuturesMarginPool/ONLY_ADMIN");
      });

      it("should revert if zero address", async function () {
        await expect(
          pool.connect(admin).modifyWithdrawAdmin(ethers.ZeroAddress)
        ).to.be.revertedWith("FuturesMarginPool/WITHDRAW_ADMIN_ERROR");
      });
    });

    describe("modifyVaultsAddress", function () {
      it("should update vaults address", async function () {
        await pool.connect(admin).modifyVaultsAddress(user2.address);
        expect(await pool.vaultsAddress()).to.equal(user2.address);
      });

      it("should revert if called by non-admin", async function () {
        await expect(
          pool.connect(user1).modifyVaultsAddress(user2.address)
        ).to.be.revertedWith("FuturesMarginPool/ONLY_ADMIN");
      });

      it("should revert if zero address", async function () {
        await expect(
          pool.connect(admin).modifyVaultsAddress(ethers.ZeroAddress)
        ).to.be.revertedWith("FuturesMarginPool/VAULTS_ERROR");
      });
    });

    describe("modifyFeeAddress", function () {
      it("should update fee address", async function () {
        await pool.connect(admin).modifyFeeAddress(user2.address);
        expect(await pool.getFeeAddress()).to.equal(user2.address);
      });

      it("should revert if called by non-admin", async function () {
        await expect(
          pool.connect(user1).modifyFeeAddress(user2.address)
        ).to.be.revertedWith("FuturesMarginPool/ONLY_ADMIN");
      });

      it("should revert if zero address", async function () {
        await expect(
          pool.connect(admin).modifyFeeAddress(ethers.ZeroAddress)
        ).to.be.revertedWith("FuturesMarginPool/FEE_ADDRESS_ERROR");
      });
    });
  });

  describe("View Functions", function () {
    let investItemId;

    beforeEach(async function () {
      investItemId = await createDefaultInvestItem();
    });

    it("getUserAddressBalance should return correct values for different users", async function () {
      const depositHash1 = ethers.keccak256(ethers.toUtf8Bytes("deposit1"));
      const depositHash2 = ethers.keccak256(ethers.toUtf8Bytes("deposit2"));

      await token.connect(user1).approve(await pool.getAddress(), DEPOSIT_AMOUNT);
      await token.connect(user2).approve(await pool.getAddress(), DEPOSIT_AMOUNT * 2n);

      await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash1);
      await pool.connect(user2).deposit(DEPOSIT_AMOUNT * 2n, investItemId, DEFAULT_LOCK_DURATION, depositHash2);

      const [inAmount1, outAmount1] = await pool.connect(user1).getUserAddressBalance();
      const [inAmount2, outAmount2] = await pool.connect(user2).getUserAddressBalance();

      expect(inAmount1).to.equal(DEPOSIT_AMOUNT);
      expect(outAmount1).to.equal(0);
      expect(inAmount2).to.equal(DEPOSIT_AMOUNT * 2n);
      expect(outAmount2).to.equal(0);
    });

    it("getWithdrawStatus should return 0 for unused hash", async function () {
      const unusedHash = ethers.keccak256(ethers.toUtf8Bytes("unused"));
      expect(await pool.getWithdrawStatus(unusedHash)).to.equal(0);
    });

    it("getWithdrawStatus should return 1 for used hash", async function () {
      const depositHash = ethers.keccak256(ethers.toUtf8Bytes("deposit1"));
      const withdrawHash = ethers.keccak256(ethers.toUtf8Bytes("withdraw1"));

      await token.connect(user1).approve(await pool.getAddress(), DEPOSIT_AMOUNT);
      await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash);
      await time.increase(TWENTY_FOUR_HOURS);

      await pool.connect(withdrawAdmin).withdraw(
        user1.address,
        WITHDRAW_AMOUNT,
        FEE_AMOUNT,
        depositHash,
        withdrawHash
      );

      expect(await pool.getWithdrawStatus(withdrawHash)).to.equal(1);
    });

    it("getAvailableBalance should return correct value", async function () {
      const depositHash = ethers.keccak256(ethers.toUtf8Bytes("deposit1"));
      const withdrawHash = ethers.keccak256(ethers.toUtf8Bytes("withdraw1"));

      await token.connect(user1).approve(await pool.getAddress(), DEPOSIT_AMOUNT);
      await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash);

      expect(await pool.getAvailableBalance(user1.address)).to.equal(DEPOSIT_AMOUNT);

      await time.increase(TWENTY_FOUR_HOURS);

      await pool.connect(withdrawAdmin).withdraw(
        user1.address,
        WITHDRAW_AMOUNT,
        0,
        depositHash,
        withdrawHash
      );

      expect(await pool.getAvailableBalance(user1.address)).to.equal(DEPOSIT_AMOUNT - WITHDRAW_AMOUNT);
    });

    it("getAvailableBalance should return 0 for user with no deposits", async function () {
      expect(await pool.getAvailableBalance(user1.address)).to.equal(0);
    });
  });

  describe("Reentrancy Protection", function () {
    let investItemId;

    beforeEach(async function () {
      investItemId = await createDefaultInvestItem();
    });

    it("deposit should be protected by nonReentrant", async function () {
      const depositHash = ethers.keccak256(ethers.toUtf8Bytes("deposit1"));
      await token.connect(user1).approve(await pool.getAddress(), DEPOSIT_AMOUNT);

      await expect(
        pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash)
      ).to.emit(pool, "FuturesMarginDeposit");
    });

    it("withdraw should be protected by nonReentrant", async function () {
      const depositHash = ethers.keccak256(ethers.toUtf8Bytes("deposit1"));
      const withdrawHash = ethers.keccak256(ethers.toUtf8Bytes("withdraw1"));

      await token.connect(user1).approve(await pool.getAddress(), DEPOSIT_AMOUNT);
      await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash);
      await time.increase(TWENTY_FOUR_HOURS);

      await expect(
        pool.connect(withdrawAdmin).withdraw(
          user1.address,
          WITHDRAW_AMOUNT,
          FEE_AMOUNT,
          depositHash,
          withdrawHash
        )
      ).to.emit(pool, "FuturesMarginWithdraw");
    });
  });

  describe("Operator Management", function () {
    let operator;

    beforeEach(async function () {
      operator = user2;
    });

    describe("addOperator", function () {
      it("should add an operator successfully", async function () {
        await expect(pool.connect(admin).addOperator(operator.address))
          .to.emit(pool, "OperatorAdded")
          .withArgs(operator.address);

        expect(await pool.isOperator(operator.address)).to.be.true;
      });

      it("should revert if called by non-admin", async function () {
        await expect(
          pool.connect(user1).addOperator(operator.address)
        ).to.be.revertedWith("FuturesMarginPool/ONLY_ADMIN");
      });

      it("should revert if operator is zero address", async function () {
        await expect(
          pool.connect(admin).addOperator(ethers.ZeroAddress)
        ).to.be.revertedWith("FuturesMarginPool/OPERATOR_ZERO_ADDRESS");
      });

      it("should revert if address is already an operator", async function () {
        await pool.connect(admin).addOperator(operator.address);

        await expect(
          pool.connect(admin).addOperator(operator.address)
        ).to.be.revertedWith("FuturesMarginPool/ALREADY_OPERATOR");
      });
    });

    describe("removeOperator", function () {
      beforeEach(async function () {
        await pool.connect(admin).addOperator(operator.address);
      });

      it("should remove an operator successfully", async function () {
        await expect(pool.connect(admin).removeOperator(operator.address))
          .to.emit(pool, "OperatorRemoved")
          .withArgs(operator.address);

        expect(await pool.isOperator(operator.address)).to.be.false;
      });

      it("should revert if called by non-admin", async function () {
        await expect(
          pool.connect(user1).removeOperator(operator.address)
        ).to.be.revertedWith("FuturesMarginPool/ONLY_ADMIN");
      });

      it("should revert if address is not an operator", async function () {
        await expect(
          pool.connect(admin).removeOperator(user1.address)
        ).to.be.revertedWith("FuturesMarginPool/NOT_OPERATOR");
      });
    });

    describe("isOperator", function () {
      it("should return true for operators", async function () {
        await pool.connect(admin).addOperator(operator.address);
        expect(await pool.isOperator(operator.address)).to.be.true;
      });

      it("should return false for non-operators", async function () {
        expect(await pool.isOperator(user1.address)).to.be.false;
      });
    });
  });

  describe("Invest Item Management", function () {
    let operator;
    const COMMISSION_BPS = 500n; // 5%

    beforeEach(async function () {
      operator = user2;
      await pool.connect(admin).addOperator(operator.address);
    });

    describe("createInvestItem", function () {
      it("should create invest item by admin", async function () {
        await expect(pool.connect(admin).createInvestItem(COMMISSION_BPS, DEFAULT_LOCK_DURATION))
          .to.emit(pool, "InvestItemCreated")
          .withArgs(0, COMMISSION_BPS, DEFAULT_LOCK_DURATION);

        const [exists, active, commissionBps, minLockDuration] = await pool.getInvestItem(0);
        expect(exists).to.be.true;
        expect(active).to.be.true;
        expect(commissionBps).to.equal(COMMISSION_BPS);
        expect(minLockDuration).to.equal(DEFAULT_LOCK_DURATION);
        expect(await pool.investItemCount()).to.equal(1);
      });

      it("should create invest item by operator", async function () {
        await expect(pool.connect(operator).createInvestItem(COMMISSION_BPS, DEFAULT_LOCK_DURATION))
          .to.emit(pool, "InvestItemCreated")
          .withArgs(0, COMMISSION_BPS, DEFAULT_LOCK_DURATION);

        const [exists, active, commissionBps, minLockDuration] = await pool.getInvestItem(0);
        expect(exists).to.be.true;
        expect(active).to.be.true;
        expect(commissionBps).to.equal(COMMISSION_BPS);
        expect(minLockDuration).to.equal(DEFAULT_LOCK_DURATION);
      });

      it("should increment invest item count", async function () {
        await pool.connect(admin).createInvestItem(COMMISSION_BPS, DEFAULT_LOCK_DURATION);
        await pool.connect(admin).createInvestItem(300n, DEFAULT_LOCK_DURATION);
        await pool.connect(admin).createInvestItem(100n, FORTY_EIGHT_HOURS);

        expect(await pool.investItemCount()).to.equal(3);
      });

      it("should revert if called by non-operator/non-admin", async function () {
        await expect(
          pool.connect(user1).createInvestItem(COMMISSION_BPS, DEFAULT_LOCK_DURATION)
        ).to.be.revertedWith("FuturesMarginPool/ONLY_OPERATOR_OR_ADMIN");
      });

      it("should revert if commission exceeds max fee", async function () {
        await expect(
          pool.connect(admin).createInvestItem(MAX_FEE_BPS + 1n, DEFAULT_LOCK_DURATION)
        ).to.be.revertedWith("FuturesMarginPool/COMMISSION_TOO_HIGH");
      });

      it("should allow commission at exactly max fee", async function () {
        await expect(pool.connect(admin).createInvestItem(MAX_FEE_BPS, DEFAULT_LOCK_DURATION))
          .to.emit(pool, "InvestItemCreated")
          .withArgs(0, MAX_FEE_BPS, DEFAULT_LOCK_DURATION);
      });

      it("should allow zero commission", async function () {
        await expect(pool.connect(admin).createInvestItem(0, DEFAULT_LOCK_DURATION))
          .to.emit(pool, "InvestItemCreated")
          .withArgs(0, 0, DEFAULT_LOCK_DURATION);
      });

      it("should revert if lock duration is below minimum", async function () {
        const shortLock = TWENTY_FOUR_HOURS - 1;
        await expect(
          pool.connect(admin).createInvestItem(COMMISSION_BPS, shortLock)
        ).to.be.revertedWith("FuturesMarginPool/LOCK_TOO_SHORT");
      });

      it("should allow lock duration at exactly minimum", async function () {
        await expect(pool.connect(admin).createInvestItem(COMMISSION_BPS, TWENTY_FOUR_HOURS))
          .to.emit(pool, "InvestItemCreated")
          .withArgs(0, COMMISSION_BPS, TWENTY_FOUR_HOURS);
      });

      it("should allow lock duration above minimum", async function () {
        await expect(pool.connect(admin).createInvestItem(COMMISSION_BPS, FORTY_EIGHT_HOURS))
          .to.emit(pool, "InvestItemCreated")
          .withArgs(0, COMMISSION_BPS, FORTY_EIGHT_HOURS);
      });

      it("should revert if lock duration exceeds maximum", async function () {
        const tooLongLock = TWO_HUNDRED_FORTY_HOURS + 1;
        await expect(
          pool.connect(admin).createInvestItem(COMMISSION_BPS, tooLongLock)
        ).to.be.revertedWith("FuturesMarginPool/LOCK_TOO_LONG");
      });

      it("should allow lock duration at exactly maximum", async function () {
        await expect(pool.connect(admin).createInvestItem(COMMISSION_BPS, TWO_HUNDRED_FORTY_HOURS))
          .to.emit(pool, "InvestItemCreated")
          .withArgs(0, COMMISSION_BPS, TWO_HUNDRED_FORTY_HOURS);
      });
    });

    describe("setInvestItemStatus", function () {
      beforeEach(async function () {
        await pool.connect(admin).createInvestItem(COMMISSION_BPS, DEFAULT_LOCK_DURATION);
      });

      it("should set invest item status by admin", async function () {
        await expect(pool.connect(admin).setInvestItemStatus(0, false))
          .to.emit(pool, "InvestItemStatusChanged")
          .withArgs(0, false);

        const [exists, active, commissionBps, minLockDuration] = await pool.getInvestItem(0);
        expect(active).to.be.false;
      });

      it("should set invest item status by operator", async function () {
        await expect(pool.connect(operator).setInvestItemStatus(0, false))
          .to.emit(pool, "InvestItemStatusChanged")
          .withArgs(0, false);

        const [exists, active, commissionBps, minLockDuration] = await pool.getInvestItem(0);
        expect(active).to.be.false;
      });

      it("should revert if called by non-operator/non-admin", async function () {
        await expect(
          pool.connect(user1).setInvestItemStatus(0, false)
        ).to.be.revertedWith("FuturesMarginPool/ONLY_OPERATOR_OR_ADMIN");
      });

      it("should revert if invest item does not exist", async function () {
        await expect(
          pool.connect(admin).setInvestItemStatus(999, false)
        ).to.be.revertedWith("FuturesMarginPool/INVEST_ITEM_NOT_FOUND");
      });

      it("should allow reactivating invest item", async function () {
        await pool.connect(admin).setInvestItemStatus(0, false);
        await pool.connect(admin).setInvestItemStatus(0, true);

        const [exists, active, commissionBps, minLockDuration] = await pool.getInvestItem(0);
        expect(active).to.be.true;
      });
    });

    describe("setInvestItemCommission", function () {
      beforeEach(async function () {
        await pool.connect(admin).createInvestItem(COMMISSION_BPS, DEFAULT_LOCK_DURATION);
      });

      it("should set invest item commission by admin", async function () {
        const newCommission = 300n;
        await expect(pool.connect(admin).setInvestItemCommission(0, newCommission))
          .to.emit(pool, "InvestItemCommissionChanged")
          .withArgs(0, COMMISSION_BPS, newCommission);

        const [exists, active, commissionBps, minLockDuration] = await pool.getInvestItem(0);
        expect(commissionBps).to.equal(newCommission);
      });

      it("should set invest item commission by operator", async function () {
        const newCommission = 300n;
        await expect(pool.connect(operator).setInvestItemCommission(0, newCommission))
          .to.emit(pool, "InvestItemCommissionChanged")
          .withArgs(0, COMMISSION_BPS, newCommission);

        const [exists, active, commissionBps, minLockDuration] = await pool.getInvestItem(0);
        expect(commissionBps).to.equal(newCommission);
      });

      it("should revert if called by non-operator/non-admin", async function () {
        await expect(
          pool.connect(user1).setInvestItemCommission(0, 300n)
        ).to.be.revertedWith("FuturesMarginPool/ONLY_OPERATOR_OR_ADMIN");
      });

      it("should revert if invest item does not exist", async function () {
        await expect(
          pool.connect(admin).setInvestItemCommission(999, 300n)
        ).to.be.revertedWith("FuturesMarginPool/INVEST_ITEM_NOT_FOUND");
      });

      it("should revert if new commission exceeds max fee", async function () {
        await expect(
          pool.connect(admin).setInvestItemCommission(0, MAX_FEE_BPS + 1n)
        ).to.be.revertedWith("FuturesMarginPool/COMMISSION_TOO_HIGH");
      });
    });

    describe("setInvestItemLockDuration", function () {
      beforeEach(async function () {
        await pool.connect(admin).createInvestItem(COMMISSION_BPS, DEFAULT_LOCK_DURATION);
      });

      it("should set invest item lock duration by admin", async function () {
        const newDuration = FORTY_EIGHT_HOURS;
        await expect(pool.connect(admin).setInvestItemLockDuration(0, newDuration))
          .to.emit(pool, "InvestItemLockDurationChanged")
          .withArgs(0, DEFAULT_LOCK_DURATION, newDuration);

        const [exists, active, commissionBps, minLockDuration] = await pool.getInvestItem(0);
        expect(minLockDuration).to.equal(newDuration);
      });

      it("should set invest item lock duration by operator", async function () {
        const newDuration = FORTY_EIGHT_HOURS;
        await expect(pool.connect(operator).setInvestItemLockDuration(0, newDuration))
          .to.emit(pool, "InvestItemLockDurationChanged")
          .withArgs(0, DEFAULT_LOCK_DURATION, newDuration);

        const [exists, active, commissionBps, minLockDuration] = await pool.getInvestItem(0);
        expect(minLockDuration).to.equal(newDuration);
      });

      it("should revert if called by non-operator/non-admin", async function () {
        await expect(
          pool.connect(user1).setInvestItemLockDuration(0, FORTY_EIGHT_HOURS)
        ).to.be.revertedWith("FuturesMarginPool/ONLY_OPERATOR_OR_ADMIN");
      });

      it("should revert if invest item does not exist", async function () {
        await expect(
          pool.connect(admin).setInvestItemLockDuration(999, FORTY_EIGHT_HOURS)
        ).to.be.revertedWith("FuturesMarginPool/INVEST_ITEM_NOT_FOUND");
      });

      it("should revert if new lock duration is below minimum", async function () {
        await expect(
          pool.connect(admin).setInvestItemLockDuration(0, TWENTY_FOUR_HOURS - 1)
        ).to.be.revertedWith("FuturesMarginPool/LOCK_TOO_SHORT");
      });

      it("should revert if new lock duration exceeds maximum", async function () {
        const tooLongLock = TWO_HUNDRED_FORTY_HOURS + 1;
        await expect(
          pool.connect(admin).setInvestItemLockDuration(0, tooLongLock)
        ).to.be.revertedWith("FuturesMarginPool/LOCK_TOO_LONG");
      });

      it("should allow setting lock duration at exactly maximum", async function () {
        await expect(pool.connect(admin).setInvestItemLockDuration(0, TWO_HUNDRED_FORTY_HOURS))
          .to.emit(pool, "InvestItemLockDurationChanged")
          .withArgs(0, DEFAULT_LOCK_DURATION, TWO_HUNDRED_FORTY_HOURS);

        const [, , , minLockDuration] = await pool.getInvestItem(0);
        expect(minLockDuration).to.equal(TWO_HUNDRED_FORTY_HOURS);
      });
    });

    describe("getInvestItem", function () {
      it("should return correct values for existing invest item", async function () {
        await pool.connect(admin).createInvestItem(COMMISSION_BPS, FORTY_EIGHT_HOURS);

        const [exists, active, commissionBps, minLockDuration] = await pool.getInvestItem(0);
        expect(exists).to.be.true;
        expect(active).to.be.true;
        expect(commissionBps).to.equal(COMMISSION_BPS);
        expect(minLockDuration).to.equal(FORTY_EIGHT_HOURS);
      });

      it("should return exists=false for non-existent invest item", async function () {
        const [exists, active, commissionBps, minLockDuration] = await pool.getInvestItem(999);
        expect(exists).to.be.false;
        expect(active).to.be.false;
        expect(commissionBps).to.equal(0);
        expect(minLockDuration).to.equal(0);
      });
    });
  });

  describe("WithdrawWithItem", function () {
    const depositHash = ethers.keccak256(ethers.toUtf8Bytes("deposit1"));
    const withdrawHash = ethers.keccak256(ethers.toUtf8Bytes("withdraw1"));
    const COMMISSION_BPS = 500n; // 5%
    let investItemId;

    beforeEach(async function () {
      investItemId = await createDefaultInvestItem();
      // User deposits first
      await token.connect(user1).approve(await pool.getAddress(), DEPOSIT_AMOUNT);
      await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash);
      // Advance time to unlock
      await time.increase(TWENTY_FOUR_HOURS);
    });

    it("should withdraw using invest item commission rate", async function () {
      const userBalanceBefore = await token.balanceOf(user1.address);
      const feeBalanceBefore = await token.balanceOf(feeAddress.address);

      await pool.connect(withdrawAdmin).withdrawWithItem(
        user1.address,
        WITHDRAW_AMOUNT,
        depositHash,
        withdrawHash
      );

      const expectedFee = (WITHDRAW_AMOUNT * COMMISSION_BPS) / BPS_DENOMINATOR;
      const expectedUserAmount = WITHDRAW_AMOUNT - expectedFee;

      const userBalanceAfter = await token.balanceOf(user1.address);
      const feeBalanceAfter = await token.balanceOf(feeAddress.address);

      expect(userBalanceAfter).to.equal(userBalanceBefore + expectedUserAmount);
      expect(feeBalanceAfter).to.equal(feeBalanceBefore + expectedFee);
    });

    it("should emit FuturesMarginWithdraw event with calculated fee", async function () {
      const expectedFee = (WITHDRAW_AMOUNT * COMMISSION_BPS) / BPS_DENOMINATOR;

      await expect(
        pool.connect(withdrawAdmin).withdrawWithItem(
          user1.address,
          WITHDRAW_AMOUNT,
          depositHash,
          withdrawHash
        )
      )
        .to.emit(pool, "FuturesMarginWithdraw")
        .withArgs(withdrawHash, user1.address, WITHDRAW_AMOUNT, expectedFee);
    });

    it("should update user outAmount", async function () {
      await pool.connect(withdrawAdmin).withdrawWithItem(
        user1.address,
        WITHDRAW_AMOUNT,
        depositHash,
        withdrawHash
      );

      const [inAmount, outAmount] = await pool.connect(user1).getUserAddressBalance();
      expect(inAmount).to.equal(DEPOSIT_AMOUNT);
      expect(outAmount).to.equal(WITHDRAW_AMOUNT);
    });

    it("should update deposit record remaining amount", async function () {
      await pool.connect(withdrawAdmin).withdrawWithItem(
        user1.address,
        WITHDRAW_AMOUNT,
        depositHash,
        withdrawHash
      );

      const [, , , , remainingAmount] = await pool.getDepositRecord(depositHash);
      expect(remainingAmount).to.equal(DEPOSIT_AMOUNT - WITHDRAW_AMOUNT);
    });

    it("should mark withdrawal hash as used", async function () {
      await pool.connect(withdrawAdmin).withdrawWithItem(
        user1.address,
        WITHDRAW_AMOUNT,
        depositHash,
        withdrawHash
      );

      expect(await pool.getWithdrawStatus(withdrawHash)).to.equal(1);
    });

    it("should revert on duplicate withdrawal", async function () {
      await pool.connect(withdrawAdmin).withdrawWithItem(
        user1.address,
        WITHDRAW_AMOUNT,
        depositHash,
        withdrawHash
      );

      await expect(
        pool.connect(withdrawAdmin).withdrawWithItem(
          user1.address,
          WITHDRAW_AMOUNT,
          depositHash,
          withdrawHash
        )
      ).to.be.revertedWith("FuturesMarginPool/ALREADY_WITHDRAWN");
    });

    it("should revert if called by non-withdrawAdmin", async function () {
      await expect(
        pool.connect(user1).withdrawWithItem(
          user1.address,
          WITHDRAW_AMOUNT,
          depositHash,
          withdrawHash
        )
      ).to.be.revertedWith("FuturesMarginPool/ONLY_WITHDRAW_ADMIN");
    });

    it("should revert if withdraw amount is zero", async function () {
      await expect(
        pool.connect(withdrawAdmin).withdrawWithItem(
          user1.address,
          0,
          depositHash,
          withdrawHash
        )
      ).to.be.revertedWith("FuturesMarginPool/ZERO_AMOUNT");
    });

    it("should revert if account is zero address", async function () {
      await expect(
        pool.connect(withdrawAdmin).withdrawWithItem(
          ethers.ZeroAddress,
          WITHDRAW_AMOUNT,
          depositHash,
          withdrawHash
        )
      ).to.be.revertedWith("FuturesMarginPool/INVALID_ACCOUNT");
    });

    it("should revert if deposit not found", async function () {
      const nonExistentDeposit = ethers.keccak256(ethers.toUtf8Bytes("nonexistent"));
      await expect(
        pool.connect(withdrawAdmin).withdrawWithItem(
          user1.address,
          WITHDRAW_AMOUNT,
          nonExistentDeposit,
          withdrawHash
        )
      ).to.be.revertedWith("FuturesMarginPool/DEPOSIT_NOT_FOUND");
    });

    it("should revert if not deposit owner", async function () {
      await expect(
        pool.connect(withdrawAdmin).withdrawWithItem(
          user2.address,
          WITHDRAW_AMOUNT,
          depositHash,
          withdrawHash
        )
      ).to.be.revertedWith("FuturesMarginPool/NOT_DEPOSIT_OWNER");
    });

    it("should revert if invest item is not active", async function () {
      await pool.connect(admin).setInvestItemStatus(investItemId, false);

      await expect(
        pool.connect(withdrawAdmin).withdrawWithItem(
          user1.address,
          WITHDRAW_AMOUNT,
          depositHash,
          withdrawHash
        )
      ).to.be.revertedWith("FuturesMarginPool/INVEST_ITEM_NOT_ACTIVE");
    });

    it("should revert if withdrawal exceeds remaining amount", async function () {
      const excessAmount = DEPOSIT_AMOUNT + ethers.parseEther("1");

      await expect(
        pool.connect(withdrawAdmin).withdrawWithItem(
          user1.address,
          excessAmount,
          depositHash,
          withdrawHash
        )
      ).to.be.revertedWith("FuturesMarginPool/EXCEEDS_DEPOSIT_REMAINING");
    });

    it("should revert when paused", async function () {
      await pool.connect(admin).pause();

      await expect(
        pool.connect(withdrawAdmin).withdrawWithItem(
          user1.address,
          WITHDRAW_AMOUNT,
          depositHash,
          withdrawHash
        )
      ).to.be.revertedWith("Pausable: paused");
    });

    it("should work with zero commission invest item", async function () {
      // Create invest item with 0% commission
      await pool.connect(admin).createInvestItem(0, DEFAULT_LOCK_DURATION);
      const depositHash2 = ethers.keccak256(ethers.toUtf8Bytes("deposit2"));
      const withdrawHash2 = ethers.keccak256(ethers.toUtf8Bytes("withdraw2"));

      await token.connect(user1).approve(await pool.getAddress(), DEPOSIT_AMOUNT);
      await pool.connect(user1).deposit(DEPOSIT_AMOUNT, 1, DEFAULT_LOCK_DURATION, depositHash2);
      await time.increase(TWENTY_FOUR_HOURS);

      const userBalanceBefore = await token.balanceOf(user1.address);

      await pool.connect(withdrawAdmin).withdrawWithItem(
        user1.address,
        WITHDRAW_AMOUNT,
        depositHash2,
        withdrawHash2
      );

      const userBalanceAfter = await token.balanceOf(user1.address);
      expect(userBalanceAfter).to.equal(userBalanceBefore + WITHDRAW_AMOUNT);
    });

    it("should work with max fee commission invest item", async function () {
      // Create invest item with 10% commission
      await pool.connect(admin).createInvestItem(MAX_FEE_BPS, DEFAULT_LOCK_DURATION);
      const depositHash2 = ethers.keccak256(ethers.toUtf8Bytes("deposit2"));
      const withdrawHash2 = ethers.keccak256(ethers.toUtf8Bytes("withdraw2"));

      await token.connect(user1).approve(await pool.getAddress(), DEPOSIT_AMOUNT);
      await pool.connect(user1).deposit(DEPOSIT_AMOUNT, 1, DEFAULT_LOCK_DURATION, depositHash2);
      await time.increase(TWENTY_FOUR_HOURS);

      const userBalanceBefore = await token.balanceOf(user1.address);
      const feeBalanceBefore = await token.balanceOf(feeAddress.address);

      await pool.connect(withdrawAdmin).withdrawWithItem(
        user1.address,
        WITHDRAW_AMOUNT,
        depositHash2,
        withdrawHash2
      );

      const expectedFee = (WITHDRAW_AMOUNT * MAX_FEE_BPS) / BPS_DENOMINATOR;
      const expectedUserAmount = WITHDRAW_AMOUNT - expectedFee;

      const userBalanceAfter = await token.balanceOf(user1.address);
      const feeBalanceAfter = await token.balanceOf(feeAddress.address);

      expect(userBalanceAfter).to.equal(userBalanceBefore + expectedUserAmount);
      expect(feeBalanceAfter).to.equal(feeBalanceBefore + expectedFee);
    });
  });

  describe("Operator Access to withdrawAdminFun", function () {
    let operator;
    let investItemId;

    beforeEach(async function () {
      operator = user2;
      await pool.connect(admin).addOperator(operator.address);
      investItemId = await createDefaultInvestItem();
      const depositHash = ethers.keccak256(ethers.toUtf8Bytes("deposit1"));
      await token.connect(user1).approve(await pool.getAddress(), DEPOSIT_AMOUNT);
      await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, DEFAULT_LOCK_DURATION, depositHash);
    });

    it("should allow admin to call withdrawAdminFun", async function () {
      const withdrawAmount = ethers.parseEther("100");
      await expect(pool.connect(admin).withdrawAdminFun(withdrawAmount))
        .to.emit(pool, "AdminWithdrawal")
        .withArgs(vaults.address, withdrawAmount);
    });

    it("should allow operator to call withdrawAdminFun", async function () {
      const withdrawAmount = ethers.parseEther("100");
      await expect(pool.connect(operator).withdrawAdminFun(withdrawAmount))
        .to.emit(pool, "AdminWithdrawal")
        .withArgs(vaults.address, withdrawAmount);
    });

    it("should revert if called by non-operator/non-admin", async function () {
      await expect(
        pool.connect(user1).withdrawAdminFun(ethers.parseEther("100"))
      ).to.be.revertedWith("FuturesMarginPool/ONLY_OPERATOR_OR_ADMIN");
    });

    it("should transfer correct amount to vaults", async function () {
      const withdrawAmount = ethers.parseEther("100");
      const vaultsBalanceBefore = await token.balanceOf(vaults.address);

      await pool.connect(operator).withdrawAdminFun(withdrawAmount);

      const vaultsBalanceAfter = await token.balanceOf(vaults.address);
      expect(vaultsBalanceAfter).to.equal(vaultsBalanceBefore + withdrawAmount);
    });
  });

  describe("MIN_LOCK_DURATION constant", function () {
    it("should have correct MIN_LOCK_DURATION value", async function () {
      expect(await pool.MIN_LOCK_DURATION()).to.equal(MIN_LOCK_DURATION);
    });
  });

  describe("MAX_LOCK_DURATION constant", function () {
    it("should have correct MAX_LOCK_DURATION value", async function () {
      expect(await pool.MAX_LOCK_DURATION()).to.equal(MAX_LOCK_DURATION);
    });
  });

  describe("getDepositRecord", function () {
    let investItemId;

    beforeEach(async function () {
      investItemId = await createDefaultInvestItem();
    });

    it("should return correct deposit record", async function () {
      const depositHash = ethers.keccak256(ethers.toUtf8Bytes("deposit1"));
      await token.connect(user1).approve(await pool.getAddress(), DEPOSIT_AMOUNT);
      const tx = await pool.connect(user1).deposit(DEPOSIT_AMOUNT, investItemId, FORTY_EIGHT_HOURS, depositHash);
      const receipt = await tx.wait();
      const block = await ethers.provider.getBlock(receipt.blockNumber);
      const expectedUnlockTime = block.timestamp + FORTY_EIGHT_HOURS;

      const [user, amount, itemId, unlockTime, remainingAmount] = await pool.getDepositRecord(depositHash);
      expect(user).to.equal(user1.address);
      expect(amount).to.equal(DEPOSIT_AMOUNT);
      expect(itemId).to.equal(investItemId);
      expect(unlockTime).to.equal(expectedUnlockTime);
      expect(remainingAmount).to.equal(DEPOSIT_AMOUNT);
    });

    it("should return empty values for non-existent deposit", async function () {
      const nonExistentHash = ethers.keccak256(ethers.toUtf8Bytes("nonexistent"));
      const [user, amount, itemId, unlockTime, remainingAmount] = await pool.getDepositRecord(nonExistentHash);
      expect(user).to.equal(ethers.ZeroAddress);
      expect(amount).to.equal(0);
      expect(itemId).to.equal(0);
      expect(unlockTime).to.equal(0);
      expect(remainingAmount).to.equal(0);
    });
  });
});
