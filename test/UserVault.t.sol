// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {UserVault} from "../src/UserVault.sol";
import {MockERC20} from "./MockERC20.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

/**
 * @title UserVaultTest
 * @notice UserVault 合约的完整测试套件
 */
contract UserVaultTest is Test {
    UserVault public vault;
    MockERC20 public token;
    
    // 测试账户
    address public owner1;
    address public owner2;
    address public owner3;
    address public operator1;
    address public operator2;
    address public user1;
    address public user2;
    
    // 常量
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10**6; // 100万 USDC
    uint256 public constant DEPOSIT_AMOUNT = 1000 * 10**6; // 1000 USDC
    uint256 public constant WITHDRAW_AMOUNT = 500 * 10**6; // 500 USDC
    
    // 事件
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
    event OperatorAdded(address indexed operator);
    event OperatorRemoved(address indexed operator);
    event Paused(address indexed account);
    event Unpaused(address indexed account);
    
    function setUp() public {
        // 创建测试账户
        owner1 = address(0x1);
        owner2 = address(0x2);
        owner3 = address(0x3);
        operator1 = address(0x4);
        operator2 = address(0x5);
        user1 = address(0x6);
        user2 = address(0x7);
        
        // 创建 Mock ERC20 代币
        token = new MockERC20("USD Coin", "USDC", 6);
        
        // 创建 Owner 数组
        address[] memory owners = new address[](3);
        owners[0] = owner1;
        owners[1] = owner2;
        owners[2] = owner3;
        
        // 部署 UserVault 合约（3-of-3 多签，需要 2 个确认）
        vault = new UserVault(address(token), owners, 2);
        
        // 给测试账户分配代币
        token.mint(user1, INITIAL_SUPPLY);
        token.mint(user2, INITIAL_SUPPLY);
        token.mint(operator1, INITIAL_SUPPLY);
        token.mint(operator2, INITIAL_SUPPLY);
    }
    
    // ============ 构造函数和初始化测试 ============
    
    function test_Constructor_Success() public {
        address[] memory owners = new address[](2);
        owners[0] = address(0x10);
        owners[1] = address(0x11);
        
        UserVault newVault = new UserVault(address(token), owners, 2);
        
        assertEq(address(newVault.token()), address(token));
        assertEq(newVault.requiredConfirmations(), 2);
        assertEq(newVault.getOwnerCount(), 2);
        assertTrue(newVault.isOwner(address(0x10)));
        assertTrue(newVault.isOwner(address(0x11)));
    }
    
    function test_Constructor_RevertIf_InvalidToken() public {
        address[] memory owners = new address[](1);
        owners[0] = owner1;
        
        vm.expectRevert("UserVault: invalid token address");
        new UserVault(address(0), owners, 1);
    }
    
    function test_Constructor_RevertIf_NoOwners() public {
        address[] memory owners = new address[](0);
        
        vm.expectRevert("UserVault: owners required");
        new UserVault(address(token), owners, 1);
    }
    
    function test_Constructor_RevertIf_InvalidConfirmations() public {
        address[] memory owners = new address[](2);
        owners[0] = owner1;
        owners[1] = owner2;
        
        vm.expectRevert("UserVault: invalid required confirmations");
        new UserVault(address(token), owners, 0);
        
        vm.expectRevert("UserVault: invalid required confirmations");
        new UserVault(address(token), owners, 3);
    }
    
    function test_Constructor_RevertIf_DuplicateOwners() public {
        address[] memory owners = new address[](2);
        owners[0] = owner1;
        owners[1] = owner1;
        
        vm.expectRevert("UserVault: duplicate owner");
        new UserVault(address(token), owners, 1);
    }
    
    function test_Constructor_RevertIf_ZeroOwner() public {
        address[] memory owners = new address[](2);
        owners[0] = owner1;
        owners[1] = address(0);
        
        vm.expectRevert("UserVault: invalid owner");
        new UserVault(address(token), owners, 1);
    }
    
    // ============ 用户充值测试 ============
    
    function test_Deposit_Success() public {
        uint256 amount = DEPOSIT_AMOUNT;
        bytes32 depositId = keccak256("deposit-1");
        
        // 用户授权合约
        vm.prank(user1);
        token.approve(address(vault), amount);
        
        // 检查事件
        vm.expectEmit(true, false, false, true);
        emit Deposit(user1, amount, depositId);
        
        // 用户充值
        vm.prank(user1);
        vault.deposit(amount, depositId);
        
        // 验证余额
        assertEq(vault.balances(user1), amount);
        assertEq(token.balanceOf(address(vault)), amount);
        assertEq(token.balanceOf(user1), INITIAL_SUPPLY - amount);
        
        // 验证 depositId 已使用
        assertTrue(vault.usedDepositIds(depositId));
    }
    
    function test_Deposit_Multiple() public {
        uint256 amount1 = DEPOSIT_AMOUNT;
        uint256 amount2 = DEPOSIT_AMOUNT * 2;
        bytes32 depositId1 = keccak256("deposit-1");
        bytes32 depositId2 = keccak256("deposit-2");
        
        // 用户授权合约
        vm.prank(user1);
        token.approve(address(vault), amount1 + amount2);
        
        // 第一次充值
        vm.prank(user1);
        vault.deposit(amount1, depositId1);
        
        // 第二次充值
        vm.prank(user1);
        vault.deposit(amount2, depositId2);
        
        // 验证总余额
        assertEq(vault.balances(user1), amount1 + amount2);
        assertEq(token.balanceOf(address(vault)), amount1 + amount2);
    }
    
    function test_Deposit_RevertIf_ZeroAmount() public {
        bytes32 depositId = keccak256("deposit-1");
        
        vm.prank(user1);
        vm.expectRevert("UserVault: amount must be greater than 0");
        vault.deposit(0, depositId);
    }
    
    function test_Deposit_RevertIf_DuplicateDepositId() public {
        uint256 amount = DEPOSIT_AMOUNT;
        bytes32 depositId = keccak256("deposit-1");
        
        // 第一次充值
        vm.prank(user1);
        token.approve(address(vault), amount);
        vm.prank(user1);
        vault.deposit(amount, depositId);
        
        // 尝试使用相同的 depositId
        vm.prank(user2);
        token.approve(address(vault), amount);
        vm.prank(user2);
        vm.expectRevert("UserVault: depositId already used");
        vault.deposit(amount, depositId);
    }
    
    function test_Deposit_RevertIf_Paused() public {
        // 暂停合约
        _pauseContract();
        
        uint256 amount = DEPOSIT_AMOUNT;
        bytes32 depositId = keccak256("deposit-1");
        
        vm.prank(user1);
        token.approve(address(vault), amount);
        vm.prank(user1);
        vm.expectRevert("UserVault: paused");
        vault.deposit(amount, depositId);
    }
    
    function test_Deposit_RevertIf_InsufficientAllowance() public {
        uint256 amount = DEPOSIT_AMOUNT;
        bytes32 depositId = keccak256("deposit-1");
        
        // 不授权或授权不足
        vm.prank(user1);
        token.approve(address(vault), amount - 1);
        vm.prank(user1);
        vm.expectRevert("UserVault: transferFrom failed");
        vault.deposit(amount, depositId);
    }
    
    // ============ 用户提现测试 ============
    
    function test_Withdraw_Success() public {
        uint256 depositAmount = DEPOSIT_AMOUNT;
        uint256 withdrawAmount = WITHDRAW_AMOUNT;
        bytes32 depositId = keccak256("deposit-1");
        
        // 先充值
        vm.prank(user1);
        token.approve(address(vault), depositAmount);
        vm.prank(user1);
        vault.deposit(depositAmount, depositId);
        
        uint256 userBalanceBefore = token.balanceOf(user1);
        
        // 检查事件
        vm.expectEmit(true, false, false, true);
        emit Withdraw(user1, withdrawAmount);
        
        // 提现
        vm.prank(user1);
        vault.withdraw(withdrawAmount);
        
        // 验证余额
        assertEq(vault.balances(user1), depositAmount - withdrawAmount);
        assertEq(token.balanceOf(address(vault)), depositAmount - withdrawAmount);
        assertEq(token.balanceOf(user1), userBalanceBefore + withdrawAmount);
    }
    
    function test_Withdraw_All() public {
        uint256 depositAmount = DEPOSIT_AMOUNT;
        bytes32 depositId = keccak256("deposit-1");
        
        // 先充值
        vm.prank(user1);
        token.approve(address(vault), depositAmount);
        vm.prank(user1);
        vault.deposit(depositAmount, depositId);
        
        // 全部提现
        vm.prank(user1);
        vault.withdraw(depositAmount);
        
        // 验证余额为 0
        assertEq(vault.balances(user1), 0);
        assertEq(token.balanceOf(address(vault)), 0);
    }
    
    function test_Withdraw_RevertIf_ZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert("UserVault: amount must be greater than 0");
        vault.withdraw(0);
    }
    
    function test_Withdraw_RevertIf_InsufficientBalance() public {
        uint256 depositAmount = DEPOSIT_AMOUNT;
        uint256 withdrawAmount = depositAmount + 1;
        bytes32 depositId = keccak256("deposit-1");
        
        // 先充值
        vm.prank(user1);
        token.approve(address(vault), depositAmount);
        vm.prank(user1);
        vault.deposit(depositAmount, depositId);
        
        // 尝试提现超过余额
        vm.prank(user1);
        vm.expectRevert("UserVault: insufficient balance");
        vault.withdraw(withdrawAmount);
    }
    
    function test_Withdraw_RevertIf_Paused() public {
        uint256 depositAmount = DEPOSIT_AMOUNT;
        bytes32 depositId = keccak256("deposit-1");
        
        // 先充值
        vm.prank(user1);
        token.approve(address(vault), depositAmount);
        vm.prank(user1);
        vault.deposit(depositAmount, depositId);
        
        // 暂停合约
        _pauseContract();
        
        // 尝试提现
        vm.prank(user1);
        vm.expectRevert("UserVault: paused");
        vault.withdraw(DEPOSIT_AMOUNT);
    }
    
    // ============ 防重复充值机制测试 ============
    
    function test_DepositId_Uniqueness() public {
        uint256 amount = DEPOSIT_AMOUNT;
        bytes32 depositId1 = keccak256("deposit-1");
        bytes32 depositId2 = keccak256("deposit-2");
        
        vm.prank(user1);
        token.approve(address(vault), amount * 2);
        
        // 使用不同的 depositId 可以多次充值
        vm.prank(user1);
        vault.deposit(amount, depositId1);
        
        vm.prank(user1);
        vault.deposit(amount, depositId2);
        
        assertEq(vault.balances(user1), amount * 2);
    }
    
    function test_OpId_Uniqueness() public {
        // 先添加 Operator
        _addOperator(operator1);
        
        uint256 amount = DEPOSIT_AMOUNT;
        bytes32 opId1 = keccak256("op-1");
        bytes32 opId2 = keccak256("op-2");
        
        vm.prank(operator1);
        token.approve(address(vault), amount * 2);
        
        // 使用不同的 opId 可以多次操作
        vm.prank(operator1);
        vault.operatorDeposit(user1, amount, opId1);
        
        vm.prank(operator1);
        vault.operatorDeposit(user1, amount, opId2);
        
        assertEq(vault.balances(user1), amount * 2);
    }
    
    // ============ Operator 功能测试 ============
    
    function test_OperatorDeposit_Success() public {
        // 先添加 Operator
        _addOperator(operator1);
        
        uint256 amount = DEPOSIT_AMOUNT;
        bytes32 opId = keccak256("op-deposit-1");
        
        vm.prank(operator1);
        token.approve(address(vault), amount);
        
        // 检查事件
        vm.expectEmit(true, true, false, true);
        emit OperatorDeposit(operator1, user1, amount, opId);
        
        // Operator 为用户充值
        vm.prank(operator1);
        vault.operatorDeposit(user1, amount, opId);
        
        // 验证余额
        assertEq(vault.balances(user1), amount);
        assertEq(token.balanceOf(address(vault)), amount);
        assertEq(token.balanceOf(operator1), INITIAL_SUPPLY - amount);
        
        // 验证 opId 已使用
        assertTrue(vault.usedOpIds(opId));
    }
    
    function test_OperatorDeposit_RevertIf_NotOperator() public {
        uint256 amount = DEPOSIT_AMOUNT;
        bytes32 opId = keccak256("op-deposit-1");
        
        vm.prank(operator1);
        token.approve(address(vault), amount);
        vm.prank(operator1);
        vm.expectRevert("UserVault: caller is not operator");
        vault.operatorDeposit(user1, amount, opId);
    }
    
    function test_OperatorDeposit_RevertIf_DuplicateOpId() public {
        // 先添加 Operator
        _addOperator(operator1);
        
        uint256 amount = DEPOSIT_AMOUNT;
        bytes32 opId = keccak256("op-deposit-1");
        
        vm.prank(operator1);
        token.approve(address(vault), amount * 2);
        
        // 第一次操作
        vm.prank(operator1);
        vault.operatorDeposit(user1, amount, opId);
        
        // 尝试使用相同的 opId
        vm.prank(operator1);
        vm.expectRevert("UserVault: opId already used");
        vault.operatorDeposit(user1, amount, opId);
    }
    
    function test_OperatorTransfer_Success() public {
        // 先添加 Operator
        _addOperator(operator1);
        
        uint256 depositAmount = DEPOSIT_AMOUNT;
        uint256 transferAmount = WITHDRAW_AMOUNT;
        bytes32 depositId = keccak256("deposit-1");
        bytes32 opId = keccak256("op-transfer-1");
        
        // 用户先充值
        vm.prank(user1);
        token.approve(address(vault), depositAmount);
        vm.prank(user1);
        vault.deposit(depositAmount, depositId);
        
        uint256 toBalanceBefore = token.balanceOf(user2);
        
        // 检查事件
        vm.expectEmit(true, true, true, true);
        emit OperatorTransfer(operator1, user1, user2, transferAmount, opId);
        
        // Operator 转移用户资金
        vm.prank(operator1);
        vault.operatorTransfer(user1, user2, transferAmount, opId);
        
        // 验证余额
        assertEq(vault.balances(user1), depositAmount - transferAmount);
        assertEq(token.balanceOf(user2), toBalanceBefore + transferAmount);
        assertEq(token.balanceOf(address(vault)), depositAmount - transferAmount);
        
        // 验证 opId 已使用
        assertTrue(vault.usedOpIds(opId));
    }
    
    function test_OperatorTransfer_RevertIf_InsufficientBalance() public {
        // 先添加 Operator
        _addOperator(operator1);
        
        uint256 depositAmount = DEPOSIT_AMOUNT;
        uint256 transferAmount = depositAmount + 1;
        bytes32 depositId = keccak256("deposit-1");
        bytes32 opId = keccak256("op-transfer-1");
        
        // 用户先充值
        vm.prank(user1);
        token.approve(address(vault), depositAmount);
        vm.prank(user1);
        vault.deposit(depositAmount, depositId);
        
        // 尝试转移超过余额
        vm.prank(operator1);
        vm.expectRevert("UserVault: insufficient balance");
        vault.operatorTransfer(user1, user2, transferAmount, opId);
    }
    
    function test_OperatorTransfer_RevertIf_InvalidAddresses() public {
        // 先添加 Operator
        _addOperator(operator1);
        
        uint256 amount = DEPOSIT_AMOUNT;
        bytes32 opId = keccak256("op-transfer-1");
        
        vm.prank(operator1);
        vm.expectRevert("UserVault: invalid user address");
        vault.operatorTransfer(address(0), user2, amount, opId);
        
        vm.prank(operator1);
        vm.expectRevert("UserVault: invalid to address");
        vault.operatorTransfer(user1, address(0), amount, opId);
    }
    
    // ============ 多签功能测试 ============
    
    function test_SubmitProposal_Success() public {
        bytes memory data = abi.encode(operator1);
        
        vm.expectEmit(true, false, false, false);
        emit MultiSigSubmitted(1);
        
        vm.prank(owner1);
        uint256 proposalId = vault.submitProposal(UserVault.ProposalType.AddOperator, data);
        
        assertEq(proposalId, 1);
        assertEq(vault.getProposalConfirmations(proposalId), 1);
        assertTrue(vault.hasConfirmed(proposalId, owner1));
    }
    
    function test_SubmitProposal_RevertIf_NotOwner() public {
        bytes memory data = abi.encode(operator1);
        
        vm.prank(user1);
        vm.expectRevert("UserVault: caller is not owner");
        vault.submitProposal(UserVault.ProposalType.AddOperator, data);
    }
    
    function test_ConfirmProposal_Success() public {
        bytes memory data = abi.encode(operator1);
        
        // Owner1 提交提案
        vm.prank(owner1);
        uint256 proposalId = vault.submitProposal(UserVault.ProposalType.AddOperator, data);
        
        // Owner2 确认提案
        vm.expectEmit(true, true, false, false);
        emit MultiSigConfirmed(owner2, proposalId);
        
        vm.prank(owner2);
        vault.confirmProposal(proposalId);
        
        assertEq(vault.getProposalConfirmations(proposalId), 2);
        assertTrue(vault.hasConfirmed(proposalId, owner2));
        
        // 应该自动执行（因为达到确认数）
        assertTrue(vault.operators(operator1));
    }
    
    function test_ConfirmProposal_AutoExecute() public {
        bytes memory data = abi.encode(operator1);
        
        // Owner1 提交提案
        vm.prank(owner1);
        uint256 proposalId = vault.submitProposal(UserVault.ProposalType.AddOperator, data);
        
        // Owner2 确认提案（达到确认数，自动执行）
        vm.expectEmit(true, false, false, false);
        emit MultiSigExecuted(proposalId);
        
        vm.expectEmit(true, false, false, false);
        emit OperatorAdded(operator1);
        
        vm.prank(owner2);
        vault.confirmProposal(proposalId);
        
        // 验证 Operator 已添加
        assertTrue(vault.operators(operator1));
    }
    
    function test_ConfirmProposal_RevertIf_NotOwner() public {
        bytes memory data = abi.encode(operator1);
        
        vm.prank(owner1);
        uint256 proposalId = vault.submitProposal(UserVault.ProposalType.AddOperator, data);
        
        vm.prank(user1);
        vm.expectRevert("UserVault: caller is not owner");
        vault.confirmProposal(proposalId);
    }
    
    function test_ConfirmProposal_RevertIf_AlreadyConfirmed() public {
        bytes memory data = abi.encode(operator1);
        
        vm.prank(owner1);
        uint256 proposalId = vault.submitProposal(UserVault.ProposalType.AddOperator, data);
        
        // Owner1 再次确认
        vm.prank(owner1);
        vm.expectRevert("UserVault: already confirmed");
        vault.confirmProposal(proposalId);
    }
    
    function test_ExecuteProposal_AddOperator() public {
        bytes memory data = abi.encode(operator1);
        
        // 提交并确认提案
        vm.prank(owner1);
        uint256 proposalId = vault.submitProposal(UserVault.ProposalType.AddOperator, data);
        
        vm.prank(owner2);
        vault.confirmProposal(proposalId);
        
        // 验证 Operator 已添加
        assertTrue(vault.operators(operator1));
        
        vm.expectEmit(true, false, false, false);
        emit OperatorAdded(operator1);
    }
    
    function test_ExecuteProposal_RemoveOperator() public {
        // 先添加 Operator
        _addOperator(operator1);
        
        bytes memory data = abi.encode(operator1);
        
        // 提交并确认移除提案
        vm.prank(owner1);
        uint256 proposalId = vault.submitProposal(UserVault.ProposalType.RemoveOperator, data);
        
        vm.expectEmit(true, false, false, false);
        emit OperatorRemoved(operator1);
        
        vm.prank(owner2);
        vault.confirmProposal(proposalId);
        
        // 验证 Operator 已移除
        assertFalse(vault.operators(operator1));
    }
    
    function test_ExecuteProposal_Pause() public {
        bytes memory data = abi.encode("");
        
        // 提交并确认暂停提案
        vm.prank(owner1);
        uint256 proposalId = vault.submitProposal(UserVault.ProposalType.Pause, data);
        
        vm.expectEmit(true, false, false, false);
        emit Paused(owner2);
        
        vm.prank(owner2);
        vault.confirmProposal(proposalId);
        
        // 验证合约已暂停
        assertTrue(vault.paused());
    }
    
    function test_ExecuteProposal_Unpause() public {
        // 先暂停合约
        _pauseContract();
        
        bytes memory data = abi.encode("");
        
        // 提交并确认恢复提案
        vm.prank(owner1);
        uint256 proposalId = vault.submitProposal(UserVault.ProposalType.Unpause, data);
        
        vm.expectEmit(true, false, false, false);
        emit Unpaused(owner2);
        
        vm.prank(owner2);
        vault.confirmProposal(proposalId);
        
        // 验证合约已恢复
        assertFalse(vault.paused());
    }
    
    function test_ExecuteProposal_RevertIf_InsufficientConfirmations() public {
        bytes memory data = abi.encode(operator1);
        
        // 提交提案（只有 1 个确认）
        vm.prank(owner1);
        uint256 proposalId = vault.submitProposal(UserVault.ProposalType.AddOperator, data);
        
        // 尝试执行（确认数不足）
        vm.expectRevert("UserVault: insufficient confirmations");
        vault.executeProposal(proposalId);
    }
    
    function test_ExecuteProposal_RevertIf_AlreadyExecuted() public {
        bytes memory data = abi.encode(operator1);
        
        // 提交并确认提案（自动执行）
        vm.prank(owner1);
        uint256 proposalId = vault.submitProposal(UserVault.ProposalType.AddOperator, data);
        
        vm.prank(owner2);
        vault.confirmProposal(proposalId);
        
        // 尝试再次执行
        vm.expectRevert("UserVault: proposal already executed");
        vault.executeProposal(proposalId);
    }
    
    // ============ 边界情况和错误处理测试 ============
    
    function test_ReentrancyProtection() public {
        // 创建一个会尝试重入的恶意合约
        ReentrancyAttacker attacker = new ReentrancyAttacker(vault, token);
        
        // 给攻击者代币
        token.mint(address(attacker), DEPOSIT_AMOUNT);
        
        // 尝试重入攻击
        vm.prank(address(attacker));
        vm.expectRevert("UserVault: reentrant call");
        attacker.attack();
    }
    
    function test_MultipleUsers_Deposit() public {
        uint256 amount = DEPOSIT_AMOUNT;
        bytes32 depositId1 = keccak256("user1-deposit");
        bytes32 depositId2 = keccak256("user2-deposit");
        
        // User1 充值
        vm.prank(user1);
        token.approve(address(vault), amount);
        vm.prank(user1);
        vault.deposit(amount, depositId1);
        
        // User2 充值
        vm.prank(user2);
        token.approve(address(vault), amount);
        vm.prank(user2);
        vault.deposit(amount, depositId2);
        
        // 验证各自余额
        assertEq(vault.balances(user1), amount);
        assertEq(vault.balances(user2), amount);
        assertEq(token.balanceOf(address(vault)), amount * 2);
    }
    
    function test_ContractBalance_Consistency() public {
        uint256 depositAmount = DEPOSIT_AMOUNT;
        uint256 withdrawAmount = WITHDRAW_AMOUNT;
        bytes32 depositId = keccak256("deposit-1");
        
        // 充值
        vm.prank(user1);
        token.approve(address(vault), depositAmount);
        vm.prank(user1);
        vault.deposit(depositAmount, depositId);
        
        uint256 contractBalance = vault.getContractBalance();
        assertEq(contractBalance, depositAmount);
        
        // 提现
        vm.prank(user1);
        vault.withdraw(withdrawAmount);
        
        contractBalance = vault.getContractBalance();
        assertEq(contractBalance, depositAmount - withdrawAmount);
        
        // 验证内部账本总和
        uint256 totalInternalBalance = vault.balances(user1);
        assertEq(contractBalance, totalInternalBalance);
    }
    
    function test_ViewFunctions() public {
        // 测试 isOwner
        assertTrue(vault.isOwner(owner1));
        assertFalse(vault.isOwner(user1));
        
        // 测试 getOwnerCount
        assertEq(vault.getOwnerCount(), 3);
        
        // 测试 getOwners
        address[] memory owners = vault.getOwners();
        assertEq(owners.length, 3);
        assertEq(owners[0], owner1);
        assertEq(owners[1], owner2);
        assertEq(owners[2], owner3);
        
        // 测试 getUserBalance
        assertEq(vault.getUserBalance(user1), 0);
    }
    
    // ============ 辅助函数 ============
    
    function _addOperator(address operator) internal {
        bytes memory data = abi.encode(operator);
        
        vm.prank(owner1);
        uint256 proposalId = vault.submitProposal(UserVault.ProposalType.AddOperator, data);
        
        vm.prank(owner2);
        vault.confirmProposal(proposalId);
    }
    
    function _pauseContract() internal {
        bytes memory data = abi.encode("");
        
        vm.prank(owner1);
        uint256 proposalId = vault.submitProposal(UserVault.ProposalType.Pause, data);
        
        vm.prank(owner2);
        vault.confirmProposal(proposalId);
    }
}

/**
 * @title ReentrancyAttacker
 * @notice 用于测试重入保护的恶意合约
 */
contract ReentrancyAttacker {
    UserVault public vault;
    IERC20 public token;
    bool public attacking;
    
    constructor(UserVault _vault, IERC20 _token) {
        vault = _vault;
        token = _token;
    }
    
    function attack() external {
        attacking = true;
        uint256 amount = 1000 * 10**6;
        bytes32 depositId = keccak256("attack");
        
        // 授权并充值
        token.approve(address(vault), amount);
        vault.deposit(amount, depositId);
        
        // 尝试在 withdraw 时重入
        vault.withdraw(amount);
    }
    
    // 如果 withdraw 调用 transfer，这个函数会被调用
    // 但 withdraw 有 nonReentrant 保护，所以不会成功
}
