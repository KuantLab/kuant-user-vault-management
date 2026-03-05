// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/// @title FuturesMarginPoolClassics
/// @notice A secure margin pool contract for futures trading with ERC20 token deposits and withdrawals
/// @dev Implements role-based access control, pause mechanism, and on-chain balance validation
contract FuturesMarginPoolClassics is ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // ============ Constants ============

    /// @notice Maximum fee percentage (in basis points, 1000 = 10%)
    uint256 public constant MAX_FEE_BPS = 1000;

    /// @notice Basis points denominator (10000 = 100%)
    uint256 public constant BPS_DENOMINATOR = 10000;

    /// @notice Minimum lock duration (24 hours = 86400 seconds)
    uint256 public constant MIN_LOCK_DURATION = 24 hours;

    /// @notice Maximum lock duration (240 hours = 864000 seconds)
    uint256 public constant MAX_LOCK_DURATION = 240 hours;

    /// @notice Minimum deposit amount to prevent spam and increase attack cost (0.01 tokens with 18 decimals)
    uint256 public constant MIN_DEPOSIT_AMOUNT = 10**16;

    // ============ State Variables ============

    /// @notice Address of the ERC20 token used for margin
    address public marginCoinAddress;

    /// @notice Address authorized to process withdrawals
    address private withdrawAdmin;

    /// @notice Address to receive admin withdrawals
    address private vaults;

    /// @notice Address to receive withdrawal fees
    address private feeAddress;

    /// @notice Current admin address
    address private admin;

    /// @notice Pending admin address for two-step transfer
    address public pendingAdmin;

    /// @notice Tracks user deposit and withdrawal amounts
    struct UserAsset {
        uint256 inAmount;
        uint256 outAmount;
    }

    /// @notice Mapping of user addresses to their asset information
    mapping(address => UserAsset) private userAssetInfo;

    /// @notice Mapping to track processed withdrawal hashes (0 = not processed, 1 = processed)
    mapping(bytes32 => uint256) private withdrawFlag;

    /// @notice Mapping to track used deposit hashes
    mapping(bytes32 => bool) private depositFlag;

    /// @notice Mapping to track deposit nonce per user (for generating unique deposit hashes)
    mapping(address => uint256) private userDepositNonce;

    // ============ Operator Management ============

    /// @notice Mapping to track operator addresses
    mapping(address => bool) private operators;

    // ============ Invest Items ============

    /// @notice Struct to store invest item information
    struct InvestItem {
        bool exists;
        bool active;
        uint256 commissionBps;  // Commission in basis points (e.g., 500 = 5%)
        uint256 minLockDuration;  // Minimum lock duration in seconds
    }

    /// @notice Struct to track individual deposit records with time locks
    struct DepositRecord {
        address user;
        uint256 amount;
        uint256 investItemId;
        uint256 unlockTime;
        uint256 remainingAmount;  // Supports partial withdrawals
        address marginCoinAddress;  // Token address at deposit time (immutable per deposit)
        uint256 commissionBps;  // Commission rate at deposit time (immutable per deposit)
    }

    /// @notice Mapping of invest item ID to invest item details
    mapping(uint256 => InvestItem) private investItems;

    /// @notice Counter for invest items
    uint256 public investItemCount;

    /// @notice Mapping of deposit hash to deposit record
    mapping(bytes32 => DepositRecord) private depositRecords;

    // ============ Events ============

    event FuturesMarginDeposit(bytes32 indexed recordHash, address indexed account, uint256 amount, uint256 investItemId, uint256 unlockTime);
    event FuturesMarginWithdraw(bytes32 indexed recordHash, address indexed account, uint256 amount, uint256 fee);
    event AdminWithdrawal(address indexed vaults, uint256 amount);
    event AdminTransferInitiated(address indexed currentAdmin, address indexed pendingAdmin);
    event AdminTransferCompleted(address indexed oldAdmin, address indexed newAdmin);
    event AdminTransferCancelled(address indexed admin, address indexed cancelledPendingAdmin);
    event WithdrawAdminChanged(address indexed oldWithdrawAdmin, address indexed newWithdrawAdmin);
    event VaultsAddressChanged(address indexed oldVaults, address indexed newVaults);
    event FeeAddressChanged(address indexed oldFeeAddress, address indexed newFeeAddress);
    event MarginCoinAddressChanged(address indexed oldAddress, address indexed newAddress);
    event OperatorAdded(address indexed operator);
    event OperatorRemoved(address indexed operator);
    event InvestItemCreated(uint256 indexed itemId, uint256 commissionBps, uint256 minLockDuration);
    event InvestItemStatusChanged(uint256 indexed itemId, bool active);
    event InvestItemCommissionChanged(uint256 indexed itemId, uint256 oldCommission, uint256 newCommission);
    event InvestItemLockDurationChanged(uint256 indexed itemId, uint256 oldDuration, uint256 newDuration);

    // ============ Modifiers ============

    modifier onlyAdmin() {
        require(msg.sender == admin, "FuturesMarginPool/ONLY_ADMIN");
        _;
    }

    modifier onlyWithdrawAdmin() {
        require(msg.sender == withdrawAdmin, "FuturesMarginPool/ONLY_WITHDRAW_ADMIN");
        _;
    }

    modifier onlyOperatorOrAdmin() {
        require(operators[msg.sender] || msg.sender == admin, "FuturesMarginPool/ONLY_OPERATOR_OR_ADMIN");
        _;
    }

    // ============ Constructor ============

    /// @notice Initializes the contract with required addresses
    /// @param _withdrawAdmin Address authorized to process withdrawals
    /// @param _admin Address with administrative privileges
    /// @param _vaults Address to receive admin withdrawals
    /// @param _feeAddress Address to receive withdrawal fees
    /// @param _marginCoinAddress ERC20 token address for margin deposits
    constructor(
        address _withdrawAdmin,
        address _admin,
        address _vaults,
        address _feeAddress,
        address _marginCoinAddress
    ) public {
        require(
            _withdrawAdmin != address(0) && _admin != address(0) && _vaults != address(0)
                && _feeAddress != address(0) && _marginCoinAddress != address(0),
            "FuturesMarginPool/INIT_PARAMS_ERROR"
        );
        withdrawAdmin = _withdrawAdmin;
        admin = _admin;
        vaults = _vaults;
        feeAddress = _feeAddress;
        marginCoinAddress = _marginCoinAddress;
    }

    // ============ User Functions ============

    /// @notice Deposits margin tokens into the pool with time lock
    /// @dev Generates deposit hash on-chain to prevent front-running attacks
    /// @param depositAmount The amount of tokens to deposit (must be >= MIN_DEPOSIT_AMOUNT)
    /// @param investItemId The ID of the invest item to use
    /// @param lockDuration The lock duration in seconds (must be >= invest item's minLockDuration and >= 24 hours)
    /// @return depositHash The generated unique identifier for this deposit
    function deposit(
        uint256 depositAmount,
        uint256 investItemId,
        uint256 lockDuration
    ) public nonReentrant whenNotPaused returns (bytes32) {
        require(depositAmount >= MIN_DEPOSIT_AMOUNT, "FuturesMarginPool/BELOW_MIN_DEPOSIT");

        // Validate invest item
        InvestItem storage item = investItems[investItemId];
        require(item.exists, "FuturesMarginPool/INVEST_ITEM_NOT_FOUND");
        require(item.active, "FuturesMarginPool/INVEST_ITEM_NOT_ACTIVE");

        // Validate lock duration (must be >= item minimum, >= 24 hours, and <= 240 hours)
        require(lockDuration >= item.minLockDuration, "FuturesMarginPool/LOCK_BELOW_ITEM_MIN");
        require(lockDuration >= MIN_LOCK_DURATION, "FuturesMarginPool/LOCK_TOO_SHORT");
        require(lockDuration <= MAX_LOCK_DURATION, "FuturesMarginPool/LOCK_TOO_LONG");

        // Generate deposit hash on-chain using sender, params, and nonce (prevents front-running)
        uint256 nonce = userDepositNonce[msg.sender];
        bytes32 depositHash = keccak256(abi.encodePacked(
            msg.sender,
            depositAmount,
            investItemId,
            lockDuration,
            nonce,
            block.timestamp
        ));

        // Increment nonce for next deposit
        userDepositNonce[msg.sender] = nonce.add(1);

        // Mark hash as used (should never conflict due to nonce)
        depositFlag[depositHash] = true;

        // Calculate unlock time
        uint256 unlockTime = block.timestamp.add(lockDuration);

        // Store deposit record with immutable snapshots of marginCoinAddress and commissionBps
        depositRecords[depositHash] = DepositRecord({
            user: msg.sender,
            amount: depositAmount,
            investItemId: investItemId,
            unlockTime: unlockTime,
            remainingAmount: depositAmount,
            marginCoinAddress: marginCoinAddress,  // Snapshot at deposit time
            commissionBps: item.commissionBps  // Snapshot at deposit time
        });

        IERC20(marginCoinAddress).safeTransferFrom(msg.sender, address(this), depositAmount);

        userAssetInfo[msg.sender].inAmount = userAssetInfo[msg.sender].inAmount.add(depositAmount);

        emit FuturesMarginDeposit(depositHash, msg.sender, depositAmount, investItemId, unlockTime);

        return depositHash;
    }

    /// @notice Returns the caller's deposit and withdrawal totals
    /// @return inAmount Total amount deposited by the caller
    /// @return outAmount Total amount withdrawn by the caller
    function getUserAddressBalance() public view returns (uint256, uint256) {
        return (userAssetInfo[msg.sender].inAmount, userAssetInfo[msg.sender].outAmount);
    }

    /// @notice Returns the available balance for a user (deposits minus withdrawals)
    /// @param account The user address to check
    /// @return Available balance that can be withdrawn
    function getAvailableBalance(address account) public view returns (uint256) {
        UserAsset storage asset = userAssetInfo[account];
        if (asset.inAmount <= asset.outAmount) {
            return 0;
        }
        return asset.inAmount.sub(asset.outAmount);
    }

    /// @notice Checks if a deposit hash has been used
    /// @param depositHash The hash to check
    /// @return True if the hash has been used
    function getDepositStatus(bytes32 depositHash) public view returns (bool) {
        return depositFlag[depositHash];
    }

    /// @notice Returns the current deposit nonce for a user
    /// @param user The user address to check
    /// @return The current nonce value for the user
    function getUserDepositNonce(address user) public view returns (uint256) {
        return userDepositNonce[user];
    }

    /// @notice Checks if a withdrawal hash has been processed
    /// @param withdrawHash The hash to check
    /// @return 1 if processed, 0 if not
    function getWithdrawStatus(bytes32 withdrawHash) public view returns (uint256) {
        return withdrawFlag[withdrawHash];
    }

    // ============ WithdrawAdmin Functions ============

    /// @notice Processes a withdrawal for a user from a specific deposit
    /// @dev Validates withdrawal amount against deposit's remaining balance and time lock
    /// @param account The user address to withdraw to
    /// @param withdrawAmount The total withdrawal amount (including fee)
    /// @param fee The fee to deduct from the withdrawal
    /// @param depositHash The hash of the deposit to withdraw from
    /// @param withdrawHash Unique identifier for this withdrawal
    function withdraw(
        address account,
        uint256 withdrawAmount,
        uint256 fee,
        bytes32 depositHash,
        bytes32 withdrawHash
    ) public nonReentrant whenNotPaused onlyWithdrawAdmin {
        require(withdrawAmount > 0, "FuturesMarginPool/ZERO_AMOUNT");
        require(withdrawFlag[withdrawHash] == 0, "FuturesMarginPool/ALREADY_WITHDRAWN");
        require(account != address(0), "FuturesMarginPool/INVALID_ACCOUNT");

        // Validate deposit exists and belongs to account
        DepositRecord storage depositRecord = depositRecords[depositHash];
        require(depositRecord.amount > 0, "FuturesMarginPool/DEPOSIT_NOT_FOUND");
        require(depositRecord.user == account, "FuturesMarginPool/NOT_DEPOSIT_OWNER");

        // Check time lock
        require(block.timestamp >= depositRecord.unlockTime, "FuturesMarginPool/DEPOSIT_LOCKED");

        // Check remaining amount
        require(withdrawAmount <= depositRecord.remainingAmount, "FuturesMarginPool/EXCEEDS_DEPOSIT_REMAINING");

        // Validate fee does not exceed maximum percentage
        uint256 maxFee = withdrawAmount.mul(MAX_FEE_BPS).div(BPS_DENOMINATOR);
        require(fee <= maxFee, "FuturesMarginPool/FEE_TOO_HIGH");

        // Mark as processed before transfers (checks-effects-interactions pattern)
        withdrawFlag[withdrawHash] = 1;
        depositRecord.remainingAmount = depositRecord.remainingAmount.sub(withdrawAmount);
        userAssetInfo[account].outAmount = userAssetInfo[account].outAmount.add(withdrawAmount);

        // Transfer funds using the token address recorded at deposit time
        uint256 userAmount = withdrawAmount.sub(fee);
        if (userAmount > 0) {
            IERC20(depositRecord.marginCoinAddress).safeTransfer(account, userAmount);
        }
        if (fee > 0) {
            IERC20(depositRecord.marginCoinAddress).safeTransfer(feeAddress, fee);
        }

        emit FuturesMarginWithdraw(withdrawHash, account, withdrawAmount, fee);
    }

    /// @notice Processes a withdrawal for a user using invest item's commission rate from deposit
    /// @dev Uses the invest item from the deposit record for commission calculation
    /// @param account The user address to withdraw to
    /// @param withdrawAmount The total withdrawal amount (fee will be calculated from invest item)
    /// @param depositHash The hash of the deposit to withdraw from
    /// @param withdrawHash Unique identifier for this withdrawal
    function withdrawWithItem(
        address account,
        uint256 withdrawAmount,
        bytes32 depositHash,
        bytes32 withdrawHash
    ) public nonReentrant whenNotPaused onlyWithdrawAdmin {
        require(withdrawAmount > 0, "FuturesMarginPool/ZERO_AMOUNT");
        require(withdrawFlag[withdrawHash] == 0, "FuturesMarginPool/ALREADY_WITHDRAWN");
        require(account != address(0), "FuturesMarginPool/INVALID_ACCOUNT");

        // Validate deposit exists and belongs to account
        DepositRecord storage depositRecord = depositRecords[depositHash];
        require(depositRecord.amount > 0, "FuturesMarginPool/DEPOSIT_NOT_FOUND");
        require(depositRecord.user == account, "FuturesMarginPool/NOT_DEPOSIT_OWNER");

        // Check time lock
        require(block.timestamp >= depositRecord.unlockTime, "FuturesMarginPool/DEPOSIT_LOCKED");

        // Check remaining amount
        require(withdrawAmount <= depositRecord.remainingAmount, "FuturesMarginPool/EXCEEDS_DEPOSIT_REMAINING");

        // Validate invest item still exists (optional safety check)
        InvestItem storage item = investItems[depositRecord.investItemId];
        require(item.exists, "FuturesMarginPool/INVEST_ITEM_NOT_FOUND");
        require(item.active, "FuturesMarginPool/INVEST_ITEM_NOT_ACTIVE");

        // Calculate fee using commission rate recorded at deposit time (prevents rate manipulation)
        uint256 fee = withdrawAmount.mul(depositRecord.commissionBps).div(BPS_DENOMINATOR);

        // Mark as processed before transfers (checks-effects-interactions pattern)
        withdrawFlag[withdrawHash] = 1;
        depositRecord.remainingAmount = depositRecord.remainingAmount.sub(withdrawAmount);
        userAssetInfo[account].outAmount = userAssetInfo[account].outAmount.add(withdrawAmount);

        // Transfer funds using the token address recorded at deposit time
        uint256 userAmount = withdrawAmount.sub(fee);
        if (userAmount > 0) {
            IERC20(depositRecord.marginCoinAddress).safeTransfer(account, userAmount);
        }
        if (fee > 0) {
            IERC20(depositRecord.marginCoinAddress).safeTransfer(feeAddress, fee);
        }

        emit FuturesMarginWithdraw(withdrawHash, account, withdrawAmount, fee);
    }

    // ============ Admin Functions ============

    /// @notice Transfers funds from the pool to vaults (admin or operator only)
    /// @param withdrawAmount The amount to transfer to vaults
    function withdrawAdminFun(uint256 withdrawAmount) public onlyOperatorOrAdmin {
        require(withdrawAmount > 0, "FuturesMarginPool/ZERO_AMOUNT");

        IERC20(marginCoinAddress).safeTransfer(vaults, withdrawAmount);

        emit AdminWithdrawal(vaults, withdrawAmount);
    }

    /// @notice Pauses all deposit and withdrawal operations (admin only)
    function pause() external onlyAdmin {
        _pause();
    }

    /// @notice Unpauses all operations (admin only)
    function unpause() external onlyAdmin {
        _unpause();
    }

    /// @notice Updates the margin token address (admin only)
    /// @param _marginCoinAddress The new margin token address
    function modifyMarginAddress(address _marginCoinAddress) public onlyAdmin {
        require(_marginCoinAddress != address(0), "FuturesMarginPool/MARGIN_COIN_ERROR");

        address oldAddress = marginCoinAddress;
        marginCoinAddress = _marginCoinAddress;

        emit MarginCoinAddressChanged(oldAddress, _marginCoinAddress);
    }

    /// @notice Updates the withdrawal admin address (admin only)
    /// @param _withdrawAdmin The new withdrawal admin address
    function modifyWithdrawAdmin(address _withdrawAdmin) public onlyAdmin {
        require(_withdrawAdmin != address(0), "FuturesMarginPool/WITHDRAW_ADMIN_ERROR");

        address oldWithdrawAdmin = withdrawAdmin;
        withdrawAdmin = _withdrawAdmin;

        emit WithdrawAdminChanged(oldWithdrawAdmin, _withdrawAdmin);
    }

    /// @notice Updates the vaults address (admin only)
    /// @param _vaults The new vaults address
    function modifyVaultsAddress(address _vaults) public onlyAdmin {
        require(_vaults != address(0), "FuturesMarginPool/VAULTS_ERROR");

        address oldVaults = vaults;
        vaults = _vaults;

        emit VaultsAddressChanged(oldVaults, _vaults);
    }

    /// @notice Updates the fee address (admin only)
    /// @param _feeAddress The new fee address
    function modifyFeeAddress(address _feeAddress) public onlyAdmin {
        require(_feeAddress != address(0), "FuturesMarginPool/FEE_ADDRESS_ERROR");

        address oldFeeAddress = feeAddress;
        feeAddress = _feeAddress;

        emit FeeAddressChanged(oldFeeAddress, _feeAddress);
    }

    /// @notice Initiates admin transfer to a new address (two-step process)
    /// @dev The new admin must call acceptAdmin() to complete the transfer
    /// @param _newAdmin The address to transfer admin rights to
    function transferAdmin(address _newAdmin) public onlyAdmin {
        require(_newAdmin != address(0), "FuturesMarginPool/ADMIN_ERROR");
        require(_newAdmin != admin, "FuturesMarginPool/SAME_ADMIN");

        pendingAdmin = _newAdmin;

        emit AdminTransferInitiated(admin, _newAdmin);
    }

    /// @notice Completes the admin transfer (must be called by pending admin)
    function acceptAdmin() public {
        require(msg.sender == pendingAdmin, "FuturesMarginPool/NOT_PENDING_ADMIN");

        address oldAdmin = admin;
        admin = pendingAdmin;
        pendingAdmin = address(0);

        emit AdminTransferCompleted(oldAdmin, admin);
    }

    /// @notice Cancels a pending admin transfer (admin only)
    function cancelAdminTransfer() public onlyAdmin {
        address cancelledAdmin = pendingAdmin;
        pendingAdmin = address(0);

        emit AdminTransferCancelled(msg.sender, cancelledAdmin);
    }

    // ============ Operator Management Functions ============

    /// @notice Adds an operator (admin only)
    /// @param _operator Address to add as operator
    function addOperator(address _operator) public onlyAdmin {
        require(_operator != address(0), "FuturesMarginPool/OPERATOR_ZERO_ADDRESS");
        require(!operators[_operator], "FuturesMarginPool/ALREADY_OPERATOR");

        operators[_operator] = true;

        emit OperatorAdded(_operator);
    }

    /// @notice Removes an operator (admin only)
    /// @param _operator Address to remove as operator
    function removeOperator(address _operator) public onlyAdmin {
        require(operators[_operator], "FuturesMarginPool/NOT_OPERATOR");

        operators[_operator] = false;

        emit OperatorRemoved(_operator);
    }

    /// @notice Checks if an address is an operator
    /// @param _operator Address to check
    /// @return True if the address is an operator
    function isOperator(address _operator) public view returns (bool) {
        return operators[_operator];
    }

    // ============ Invest Item Management Functions ============

    /// @notice Creates a new invest item (admin or operator only)
    /// @param commissionBps Commission rate in basis points
    /// @param minLockDuration Minimum lock duration in seconds (must be >= 24 hours)
    /// @return itemId The ID of the newly created invest item
    function createInvestItem(uint256 commissionBps, uint256 minLockDuration) public onlyOperatorOrAdmin returns (uint256) {
        require(commissionBps <= MAX_FEE_BPS, "FuturesMarginPool/COMMISSION_TOO_HIGH");
        require(minLockDuration >= MIN_LOCK_DURATION, "FuturesMarginPool/LOCK_TOO_SHORT");
        require(minLockDuration <= MAX_LOCK_DURATION, "FuturesMarginPool/LOCK_TOO_LONG");

        uint256 itemId = investItemCount;
        investItems[itemId] = InvestItem({
            exists: true,
            active: true,
            commissionBps: commissionBps,
            minLockDuration: minLockDuration
        });
        investItemCount = investItemCount.add(1);

        emit InvestItemCreated(itemId, commissionBps, minLockDuration);

        return itemId;
    }

    /// @notice Sets the active status of an invest item (admin or operator only)
    /// @param itemId The ID of the invest item
    /// @param active The new active status
    function setInvestItemStatus(uint256 itemId, bool active) public onlyOperatorOrAdmin {
        require(investItems[itemId].exists, "FuturesMarginPool/INVEST_ITEM_NOT_FOUND");

        investItems[itemId].active = active;

        emit InvestItemStatusChanged(itemId, active);
    }

    /// @notice Sets the commission rate of an invest item (admin or operator only)
    /// @param itemId The ID of the invest item
    /// @param commissionBps The new commission rate in basis points
    function setInvestItemCommission(uint256 itemId, uint256 commissionBps) public onlyOperatorOrAdmin {
        require(investItems[itemId].exists, "FuturesMarginPool/INVEST_ITEM_NOT_FOUND");
        require(commissionBps <= MAX_FEE_BPS, "FuturesMarginPool/COMMISSION_TOO_HIGH");

        uint256 oldCommission = investItems[itemId].commissionBps;
        investItems[itemId].commissionBps = commissionBps;

        emit InvestItemCommissionChanged(itemId, oldCommission, commissionBps);
    }

    /// @notice Sets the minimum lock duration of an invest item (admin or operator only)
    /// @param itemId The ID of the invest item
    /// @param minLockDuration The new minimum lock duration in seconds
    function setInvestItemLockDuration(uint256 itemId, uint256 minLockDuration) public onlyOperatorOrAdmin {
        require(investItems[itemId].exists, "FuturesMarginPool/INVEST_ITEM_NOT_FOUND");
        require(minLockDuration >= MIN_LOCK_DURATION, "FuturesMarginPool/LOCK_TOO_SHORT");
        require(minLockDuration <= MAX_LOCK_DURATION, "FuturesMarginPool/LOCK_TOO_LONG");

        uint256 oldDuration = investItems[itemId].minLockDuration;
        investItems[itemId].minLockDuration = minLockDuration;

        emit InvestItemLockDurationChanged(itemId, oldDuration, minLockDuration);
    }

    /// @notice Gets the details of an invest item
    /// @param itemId The ID of the invest item
    /// @return exists Whether the invest item exists
    /// @return active Whether the invest item is active
    /// @return commissionBps The commission rate in basis points
    /// @return minLockDuration The minimum lock duration in seconds
    function getInvestItem(uint256 itemId) public view returns (
        bool exists,
        bool active,
        uint256 commissionBps,
        uint256 minLockDuration
    ) {
        InvestItem storage item = investItems[itemId];
        return (item.exists, item.active, item.commissionBps, item.minLockDuration);
    }

    /// @notice Gets the details of a deposit record
    /// @param depositHash The hash of the deposit
    /// @return user The address of the user who made the deposit
    /// @return amount The original deposit amount
    /// @return investItemId The ID of the invest item used
    /// @return unlockTime The timestamp when the deposit can be withdrawn
    /// @return remainingAmount The remaining amount that can still be withdrawn
    /// @return marginCoinAddr The token address at deposit time
    /// @return commissionBps The commission rate at deposit time
    function getDepositRecord(bytes32 depositHash) public view returns (
        address user,
        uint256 amount,
        uint256 investItemId,
        uint256 unlockTime,
        uint256 remainingAmount,
        address marginCoinAddr,
        uint256 commissionBps
    ) {
        DepositRecord storage record = depositRecords[depositHash];
        return (
            record.user,
            record.amount,
            record.investItemId,
            record.unlockTime,
            record.remainingAmount,
            record.marginCoinAddress,
            record.commissionBps
        );
    }

    // ============ View Functions ============

    /// @notice Returns the current admin address
    function adminAddress() public view returns (address) {
        return admin;
    }

    /// @notice Returns the vaults address
    function vaultsAddress() public view returns (address) {
        return vaults;
    }

    /// @notice Returns the fee address
    function getFeeAddress() public view returns (address) {
        return feeAddress;
    }

    /// @notice Returns the withdrawal admin address
    function withdrawAdminAddress() public view returns (address) {
        return withdrawAdmin;
    }

    /// @notice Returns the maximum fee in basis points
    function getMaxFeeBps() public pure returns (uint256) {
        return MAX_FEE_BPS;
    }
}
