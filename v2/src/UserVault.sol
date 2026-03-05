// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title UserVault
 * @notice 基于 ERC20 的用户资金托管合约，支持防重复充值、多签 Owner 和 Operator 权限控制
 * @dev 使用 Solidity ^0.8.x，内置溢出检查
 */
contract UserVault {
    // ============ 状态变量 ============
    
    using SafeERC20 for IERC20;
    
    /// @notice 支持的 ERC20 代币地址（不可变）
    IERC20 public immutable token;
    
    /// @notice 用户内部账本余额
    mapping(address => uint256) public balances;
    
    /// @notice 用户充值防重：已使用的 depositId
    mapping(bytes32 => bool) public usedDepositIds;
    
    /// @notice 操作员操作防重：已使用的 opId
    mapping(bytes32 => bool) public usedOpIds;
    
    /// @notice Operator 权限映射
    mapping(address => bool) public operators;
    
    /// @notice 重入锁
    uint256 private _locked;
    
    // ============ 多签相关状态变量 ============
    
    /// @notice Owner 地址列表
    address[] public owners;
    
    /// @notice Owner 地址到索引的映射（用于快速查找）
    mapping(address => uint256) private ownerIndex;
    
    /// @notice 最少确认数
    uint256 public requiredConfirmations;
    
    /// @notice 提案计数器
    uint256 public proposalCounter;
    
    /// @notice 提案结构
    struct Proposal {
        uint256 id;
        address proposer;
        ProposalType proposalType;
        bytes data;
        uint256 confirmations;
        bool executed;
        bool cancelled;                 // 是否已取消
        uint256 confirmationTimestamp;  // 达到确认数的时间戳
        mapping(address => bool) confirmedBy;
    }
    
    /// @notice 提案时间锁时长（默认 24 小时）
    uint256 public timelockDuration = 24 hours;
    
    /// @notice 提案类型枚举
    enum ProposalType {
        AddOperator,        // 添加 Operator
        RemoveOperator,     // 移除 Operator
        AddOwner,           // 添加 Owner
        RemoveOwner,         // 移除 Owner
        Pause,              // 暂停合约
        Unpause,            // 恢复合约
        EmergencyWithdraw    // 紧急提取（如需要）
    }
    
    /// @notice 提案映射
    mapping(uint256 => Proposal) internal proposals;
    
    /// @notice 合约是否暂停
    bool public paused;
    
    // ============ 事件 ============
    
    event Deposit(address indexed user, uint256 amount, bytes32 depositId);
    event Withdraw(address indexed user, uint256 amount);
    event OperatorDeposit(
        address indexed operator,
        address indexed user,
        uint256 amount,
        bytes32 opId
    );
    event OperatorTransfer(
        address indexed operator,
        address indexed user,
        address indexed to,
        uint256 amount,
        bytes32 opId
    );
    event MultiSigSubmitted(uint256 indexed txId);
    event MultiSigConfirmed(address indexed owner, uint256 indexed txId);
    event MultiSigExecuted(uint256 indexed txId);
    event ProposalCancelled(uint256 indexed proposalId, address indexed canceller);
    event OperatorAdded(address indexed operator);
    event OperatorRemoved(address indexed operator);
    event OwnerAdded(address indexed owner);
    event OwnerRemoved(address indexed owner);
    event Paused(address indexed account);
    event Unpaused(address indexed account);
    event EmergencyWithdraw(address indexed recipient, uint256 amount);
    event TimelockDurationChanged(uint256 oldDuration, uint256 newDuration);
    
    // ============ 修饰符 ============
    
    /// @notice 重入锁修饰符
    modifier nonReentrant() {
        require(_locked == 0, "UserVault: reentrant call");
        _locked = 1;
        _;
        _locked = 0;
    }
    
    /// @notice 仅 Operator 修饰符
    modifier onlyOperator() {
        require(operators[msg.sender], "UserVault: caller is not operator");
        _;
    }
    
    /// @notice 仅 Owner 修饰符
    modifier onlyOwner() {
        require(isOwner(msg.sender), "UserVault: caller is not owner");
        _;
    }
    
    /// @notice 未暂停修饰符
    modifier whenNotPaused() {
        require(!paused, "UserVault: paused");
        _;
    }
    
    // ============ 构造函数 ============
    
    /**
     * @notice 初始化合约
     * @param _token ERC20 代币地址
     * @param _owners Owner 地址数组
     * @param _requiredConfirmations 最少确认数（必须 <= owners.length）
     */
    constructor(
        address _token,
        address[] memory _owners,
        uint256 _requiredConfirmations
    ) {
        require(_token != address(0), "UserVault: invalid token address");
        require(_owners.length > 0, "UserVault: owners required");
        require(
            _requiredConfirmations > 0 && _requiredConfirmations <= _owners.length,
            "UserVault: invalid required confirmations"
        );
        
        token = IERC20(_token);
        requiredConfirmations = _requiredConfirmations;
        
        // 初始化 owners 数组和索引映射
        for (uint256 i = 0; i < _owners.length; i++) {
            require(_owners[i] != address(0), "UserVault: invalid owner");
            require(!isOwner(_owners[i]), "UserVault: duplicate owner");
            owners.push(_owners[i]);
            ownerIndex[_owners[i]] = i + 1; // 索引从 1 开始，0 表示不存在
        }
    }
    
    // ============ 用户功能 ============
    
    /**
     * @notice 用户充值
     * @param amount 充值金额
     * @param depositId 唯一充值 ID（用于防重）
     * @dev 用户需提前 approve 合约
     */
    function deposit(uint256 amount, bytes32 depositId)
        external
        whenNotPaused
        nonReentrant
    {
        require(amount > 0, "UserVault: amount must be greater than 0");
        require(!usedDepositIds[depositId], "UserVault: depositId already used");
        
        // 标记 depositId 为已使用（Checks → Effects）
        usedDepositIds[depositId] = true;
        
        // 更新用户余额
        balances[msg.sender] += amount;
        
        // 从用户账户转账到合约（Interactions）
        token.safeTransferFrom(msg.sender, address(this), amount);
        
        emit Deposit(msg.sender, amount, depositId);
    }
    
    /**
     * @notice 用户提现
     * @param amount 提现金额
     */
    function withdraw(uint256 amount) external whenNotPaused nonReentrant {
        require(amount > 0, "UserVault: amount must be greater than 0");
        require(balances[msg.sender] >= amount, "UserVault: insufficient balance");
        
        // 更新用户余额（Checks → Effects）
        balances[msg.sender] -= amount;
        
        // 转账给用户（Interactions）
        token.safeTransfer(msg.sender, amount);
        
        emit Withdraw(msg.sender, amount);
    }
    
    // ============ Operator 功能 ============
    
    /**
     * @notice Operator 为用户充值
     * @param user 用户地址
     * @param amount 充值金额
     * @param opId 唯一操作 ID（用于防重）
     */
    function operatorDeposit(
        address user,
        uint256 amount,
        bytes32 opId
    ) external onlyOperator whenNotPaused nonReentrant {
        require(user != address(0), "UserVault: invalid user address");
        require(amount > 0, "UserVault: amount must be greater than 0");
        require(!usedOpIds[opId], "UserVault: opId already used");
        
        // 标记 opId 为已使用
        usedOpIds[opId] = true;
        
        // 更新用户余额
        balances[user] += amount;
        
        // 从 Operator 账户转账到合约
        token.safeTransferFrom(msg.sender, address(this), amount);
        
        emit OperatorDeposit(msg.sender, user, amount, opId);
    }
    
    /**
     * @notice Operator 转移用户资金
     * @param user 用户地址
     * @param to 接收地址
     * @param amount 转移金额
     * @param opId 唯一操作 ID（用于防重）
     */
    function operatorTransfer(
        address user,
        address to,
        uint256 amount,
        bytes32 opId
    ) external onlyOperator whenNotPaused nonReentrant {
        require(user != address(0), "UserVault: invalid user address");
        require(to != address(0), "UserVault: invalid to address");
        require(amount > 0, "UserVault: amount must be greater than 0");
        require(balances[user] >= amount, "UserVault: insufficient balance");
        require(!usedOpIds[opId], "UserVault: opId already used");
        
        // 标记 opId 为已使用
        usedOpIds[opId] = true;
        
        // 更新用户余额
        balances[user] -= amount;
        
        // 转账给接收地址
        token.safeTransfer(to, amount);
        
        emit OperatorTransfer(msg.sender, user, to, amount, opId);
    }
    
    // ============ 多签功能 ============
    
    /**
     * @notice 提交多签提案
     * @param proposalType 提案类型
     * @param data 提案数据（编码后的参数）
     * @return proposalId 提案 ID
     */
    function submitProposal(ProposalType proposalType, bytes memory data)
        external
        onlyOwner
        returns (uint256 proposalId)
    {
        // M-4: 验证提案数据格式
        if (proposalType == ProposalType.AddOperator || 
            proposalType == ProposalType.RemoveOperator ||
            proposalType == ProposalType.AddOwner ||
            proposalType == ProposalType.RemoveOwner) {
            require(data.length == 32, "UserVault: invalid data length for address");
            address addr = abi.decode(data, (address));
            require(addr != address(0), "UserVault: invalid address");
        } else if (proposalType == ProposalType.EmergencyWithdraw) {
            require(data.length == 64, "UserVault: invalid data length for EmergencyWithdraw");
            (address recipient, uint256 amount) = abi.decode(data, (address, uint256));
            require(recipient != address(0), "UserVault: invalid recipient");
            require(amount > 0, "UserVault: amount must be greater than 0");
        } else if (proposalType == ProposalType.Pause || proposalType == ProposalType.Unpause) {
            require(data.length == 0, "UserVault: Pause/Unpause requires empty data");
        }
        
        proposalId = ++proposalCounter;
        Proposal storage proposal = proposals[proposalId];
        proposal.id = proposalId;
        proposal.proposer = msg.sender;
        proposal.proposalType = proposalType;
        proposal.data = data;
        proposal.confirmations = 1;
        proposal.executed = false;
        proposal.cancelled = false;
        proposal.confirmationTimestamp = 0;
        proposal.confirmedBy[msg.sender] = true;
        
        emit MultiSigSubmitted(proposalId);
    }
    
    /**
     * @notice 确认多签提案
     * @param proposalId 提案 ID
     */
    function confirmProposal(uint256 proposalId) external onlyOwner {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.id != 0, "UserVault: proposal does not exist");
        require(!proposal.executed, "UserVault: proposal already executed");
        require(!proposal.cancelled, "UserVault: proposal already cancelled");
        require(!proposal.confirmedBy[msg.sender], "UserVault: already confirmed");
        
        proposal.confirmedBy[msg.sender] = true;
        proposal.confirmations++;
        
        emit MultiSigConfirmed(msg.sender, proposalId);
        
        // M-2: 如果达到确认数，记录时间戳（不自动执行，需要等待时间锁）
        if (proposal.confirmations >= requiredConfirmations && proposal.confirmationTimestamp == 0) {
            proposal.confirmationTimestamp = block.timestamp;
        }
    }
    
    /**
     * @notice 取消提案（仅提案提交者可取消）
     * @param proposalId 提案 ID
     */
    function cancelProposal(uint256 proposalId) external onlyOwner {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.id != 0, "UserVault: proposal does not exist");
        require(!proposal.executed, "UserVault: proposal already executed");
        require(!proposal.cancelled, "UserVault: proposal already cancelled");
        require(proposal.proposer == msg.sender, "UserVault: only proposer can cancel");
        
        proposal.cancelled = true;
        emit ProposalCancelled(proposalId, msg.sender);
    }
    
    /**
     * @notice 执行多签提案
     * @param proposalId 提案 ID
     * @dev 只能由 Owner 调用，或由 confirmProposal 自动调用
     */
    function executeProposal(uint256 proposalId) public onlyOwner {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.id != 0, "UserVault: proposal does not exist");
        require(!proposal.executed, "UserVault: proposal already executed");
        require(!proposal.cancelled, "UserVault: proposal already cancelled");
        require(
            proposal.confirmations >= requiredConfirmations,
            "UserVault: insufficient confirmations"
        );
        
        // M-2: 检查时间锁
        require(
            proposal.confirmationTimestamp > 0,
            "UserVault: proposal not confirmed yet"
        );
        require(
            block.timestamp >= proposal.confirmationTimestamp + timelockDuration,
            "UserVault: timelock not expired"
        );
        
        proposal.executed = true;
        
        // 根据提案类型执行相应操作
        if (proposal.proposalType == ProposalType.AddOperator) {
            address operator = abi.decode(proposal.data, (address));
            _addOperator(operator);
        } else if (proposal.proposalType == ProposalType.RemoveOperator) {
            address operator = abi.decode(proposal.data, (address));
            _removeOperator(operator);
        } else if (proposal.proposalType == ProposalType.AddOwner) {
            // M-3: 添加 Owner
            address newOwner = abi.decode(proposal.data, (address));
            _addOwner(newOwner);
        } else if (proposal.proposalType == ProposalType.RemoveOwner) {
            // M-3: 移除 Owner
            address ownerToRemove = abi.decode(proposal.data, (address));
            _removeOwner(ownerToRemove);
        } else if (proposal.proposalType == ProposalType.Pause) {
            // L-1: 传递 proposer 而不是 msg.sender
            _pause(proposal.proposer);
        } else if (proposal.proposalType == ProposalType.Unpause) {
            // L-1: 传递 proposer 而不是 msg.sender
            _unpause(proposal.proposer);
        } else if (proposal.proposalType == ProposalType.EmergencyWithdraw) {
            // EmergencyWithdraw: 紧急提取代币
            (address recipient, uint256 amount) = abi.decode(proposal.data, (address, uint256));
            require(recipient != address(0), "UserVault: invalid recipient");
            require(amount > 0, "UserVault: amount must be greater than 0");
            token.safeTransfer(recipient, amount);
            emit EmergencyWithdraw(recipient, amount);
        }
        
        emit MultiSigExecuted(proposalId);
    }
    
    // ============ 内部函数 ============
    
    /**
     * @notice 添加 Operator（内部函数，仅多签可调用）
     */
    function _addOperator(address operator) internal {
        require(operator != address(0), "UserVault: invalid operator");
        require(!operators[operator], "UserVault: operator already exists");
        operators[operator] = true;
        emit OperatorAdded(operator);
    }
    
    /**
     * @notice 移除 Operator（内部函数，仅多签可调用）
     */
    function _removeOperator(address operator) internal {
        require(operators[operator], "UserVault: operator does not exist");
        operators[operator] = false;
        emit OperatorRemoved(operator);
    }
    
    /**
     * @notice 暂停合约（内部函数，仅多签可调用）
     * @param initiator 发起暂停的地址（提案提交者）
     */
    function _pause(address initiator) internal {
        require(!paused, "UserVault: already paused");
        paused = true;
        emit Paused(initiator);
    }
    
    /**
     * @notice 恢复合约（内部函数，仅多签可调用）
     * @param initiator 发起恢复的地址（提案提交者）
     */
    function _unpause(address initiator) internal {
        require(paused, "UserVault: not paused");
        paused = false;
        emit Unpaused(initiator);
    }
    
    /**
     * @notice 添加 Owner（内部函数，仅多签可调用）
     * @param newOwner 新 Owner 地址
     */
    function _addOwner(address newOwner) internal {
        require(newOwner != address(0), "UserVault: invalid owner");
        require(!isOwner(newOwner), "UserVault: owner already exists");
        require(owners.length < 50, "UserVault: too many owners"); // 防止数组过大
        
        owners.push(newOwner);
        ownerIndex[newOwner] = owners.length; // 索引从 1 开始
        emit OwnerAdded(newOwner);
    }
    
    /**
     * @notice 移除 Owner（内部函数，仅多签可调用）
     * @param ownerToRemove 要移除的 Owner 地址
     */
    function _removeOwner(address ownerToRemove) internal {
        require(isOwner(ownerToRemove), "UserVault: owner does not exist");
        require(owners.length > 1, "UserVault: cannot remove last owner");
        require(
            owners.length - 1 >= requiredConfirmations,
            "UserVault: would break required confirmations"
        );
        
        // 找到要移除的 Owner 的索引
        uint256 index = ownerIndex[ownerToRemove] - 1; // 转换为 0-based
        
        // 将最后一个元素移到要删除的位置
        address lastOwner = owners[owners.length - 1];
        owners[index] = lastOwner;
        ownerIndex[lastOwner] = index + 1; // 更新索引
        
        // 删除最后一个元素
        owners.pop();
        ownerIndex[ownerToRemove] = 0; // 清除索引
        
        emit OwnerRemoved(ownerToRemove);
    }
    
    // ============ 视图函数 ============
    
    /**
     * @notice 检查地址是否为 Owner
     */
    function isOwner(address account) public view returns (bool) {
        return ownerIndex[account] > 0;
    }
    
    /**
     * @notice 获取 Owner 数量
     */
    function getOwnerCount() external view returns (uint256) {
        return owners.length;
    }
    
    /**
     * @notice 获取所有 Owner 地址
     */
    function getOwners() external view returns (address[] memory) {
        return owners;
    }
    
    /**
     * @notice 获取提案信息
     */
    /**
     * @notice 获取提案信息
     * @return id 提案 ID
     * @return proposer 提案提交者
     * @return proposalType 提案类型
     * @return data 提案数据
     * @return confirmations 确认数
     * @return executed 是否已执行
     * @return cancelled 是否已取消
     * @return confirmationTimestamp 达到确认数的时间戳
     */
    function getProposal(uint256 proposalId)
        external
        view
        returns (
            uint256 id,
            address proposer,
            ProposalType proposalType,
            bytes memory data,
            uint256 confirmations,
            bool executed,
            bool cancelled,
            uint256 confirmationTimestamp
        )
    {
        Proposal storage proposal = proposals[proposalId];
        return (
            proposal.id,
            proposal.proposer,
            proposal.proposalType,
            proposal.data,
            proposal.confirmations,
            proposal.executed,
            proposal.cancelled,
            proposal.confirmationTimestamp
        );
    }
    
    /**
     * @notice 获取提案确认数
     */
    function getProposalConfirmations(uint256 proposalId)
        external
        view
        returns (uint256)
    {
        return proposals[proposalId].confirmations;
    }
    
    /**
     * @notice 检查 Owner 是否已确认提案
     */
    function hasConfirmed(uint256 proposalId, address owner)
        external
        view
        returns (bool)
    {
        return proposals[proposalId].confirmedBy[owner];
    }
    
    /**
     * @notice 获取合约 ERC20 余额
     */
    function getContractBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }
    
    /**
     * @notice 获取用户余额
     */
    function getUserBalance(address user) external view returns (uint256) {
        return balances[user];
    }
    
    /**
     * @notice 检查余额一致性
     * @dev 注意：此函数需要遍历所有用户，Gas 消耗可能很高
     * @dev 实际应用中，建议在链下计算总余额并与合约余额对比
     * @return 合约实际余额
     * @return 提示信息：需要在链下计算所有用户余额之和
     */
    function checkBalanceConsistency() external view returns (uint256, string memory) {
        uint256 contractBalance = token.balanceOf(address(this));
        // 注意：无法在链上遍历所有用户计算总余额
        // 返回提示信息，建议在链下计算
        return (
            contractBalance,
            "Use off-chain calculation to sum all balances[user] and compare with contractBalance"
        );
    }
    
    /**
     * @notice 恢复多余的代币（仅 Owner 可调用）
     * @dev 用于恢复用户直接转账到合约的代币
     * @param recipient 接收地址
     * @param amount 恢复金额
     * @dev 建议通过多签提案调用以确保安全
     */
    function recoverExcessTokens(address recipient, uint256 amount)
        external
        onlyOwner
        whenNotPaused
        nonReentrant
    {
        require(recipient != address(0), "UserVault: invalid recipient");
        require(amount > 0, "UserVault: amount must be greater than 0");
        
        uint256 contractBalance = token.balanceOf(address(this));
        require(contractBalance >= amount, "UserVault: insufficient contract balance");
        
        // 注意：此函数不验证余额一致性，由 Owner 负责验证
        // 建议在调用前通过链下计算确认存在多余代币
        token.safeTransfer(recipient, amount);
        
        emit EmergencyWithdraw(recipient, amount);
    }
}
