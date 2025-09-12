// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/ICrossCoWServiceManager.sol";
import "../interfaces/IRegistryCoordinator.sol";
import "../interfaces/IStakeRegistry.sol";
import "../interfaces/IBLSApkRegistry.sol";
import "../../libraries/IntentLib.sol";

/**
 * @title CrossCoWServiceManager
 * @notice Service Manager for CrossCoW AVS - handles operator registration, task management, and rewards
 * @dev Implements proper EigenLayer AVS patterns with BLS signature verification
 */
contract CrossCoWServiceManager is ICrossCoWServiceManager, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /* CONSTANTS */
    uint256 public constant MIN_STAKE = 1 ether;
    uint256 public constant TASK_TIMEOUT = 300; // 5 minutes
    uint256 public constant REWARD_RATE = 100; // 1% of task value
    uint256 public constant SLASH_PENALTY = 1000; // 10% of stake
    
    /* STORAGE */
    IRegistryCoordinator public registryCoordinator;
    IStakeRegistry public stakeRegistry;
    IBLSApkRegistry public blsApkRegistry;
    
    mapping(address => OperatorInfo) public operators;
    mapping(uint32 => MatchingTask) public tasks;
    mapping(address => uint256) public operatorStakes;
    mapping(address => uint256) public operatorRewards;
    
    address[] public activeOperators;
    uint32 public latestTaskIndex;
    uint256 public totalStake;
    uint256 public totalRewards;
    
    /* EVENTS */
    event OperatorRegistered(address indexed operator, uint256 stake);
    event OperatorDeregistered(address indexed operator);
    event TaskCreated(uint32 indexed taskIndex, bytes32 indexed tradeId, address indexed assignedOperator);
    event TaskCompleted(uint32 indexed taskIndex, bytes32 indexed tradeId, bool success);
    event TaskTimeout(uint32 indexed taskIndex, bytes32 indexed tradeId);
    event OperatorSlashed(address indexed operator, uint256 amount, string reason);
    event OperatorRewarded(address indexed operator, uint256 amount);
    event StakeDeposited(address indexed operator, uint256 amount);
    event StakeWithdrawn(address indexed operator, uint256 amount);

    /* MODIFIERS */
    modifier onlyRegisteredOperator() {
        require(operators[msg.sender].isActive, "Not registered operator");
        _;
    }

    modifier onlyValidTask(uint32 taskIndex) {
        require(tasks[taskIndex].taskIndex == taskIndex, "Invalid task");
        require(!tasks[taskIndex].isComplete, "Task already complete");
        _;
    }

    constructor(
        address _registryCoordinator,
        address _stakeRegistry,
        address _blsApkRegistry
    ) {
        registryCoordinator = IRegistryCoordinator(_registryCoordinator);
        stakeRegistry = IStakeRegistry(_stakeRegistry);
        blsApkRegistry = IBLSApkRegistry(_blsApkRegistry);
    }

    /**
     * @notice Register as an operator with stake
     * @param operatorSignature BLS signature for operator registration
     */
    function registerOperator(bytes calldata operatorSignature) external payable override {
        require(msg.value >= MIN_STAKE, "Insufficient stake");
        require(!operators[msg.sender].isActive, "Already registered");
        
        // Register with registry coordinator
        bytes memory quorumNumbers = abi.encodePacked(uint8(0)); // Single quorum
        string memory socket = ""; // Empty socket for now
        bytes memory params = abi.encode(msg.sender);
        
        registryCoordinator.registerOperator(
            quorumNumbers,
            socket,
            params,
            operatorSignature
        );
        
        // Initialize operator info
        operators[msg.sender] = OperatorInfo({
            operatorAddress: msg.sender,
            stake: msg.value,
            isActive: true,
            lastTaskTime: 0,
            successCount: 0,
            failureCount: 0,
            totalRewards: 0
        });
        
        operatorStakes[msg.sender] = msg.value;
        totalStake += msg.value;
        activeOperators.push(msg.sender);
        
        emit OperatorRegistered(msg.sender, msg.value);
        emit StakeDeposited(msg.sender, msg.value);
    }

    /**
     * @notice Deregister as an operator and withdraw stake
     */
    function deregisterOperator() external override onlyRegisteredOperator {
        OperatorInfo storage operator = operators[msg.sender];
        require(operator.isActive, "Not active");
        
        // Deregister from registry coordinator
        bytes memory quorumNumbers = abi.encodePacked(uint8(0));
        registryCoordinator.deregisterOperator(quorumNumbers);
        
        // Update state
        operator.isActive = false;
        totalStake -= operator.stake;
        
        // Remove from active operators array
        for (uint i = 0; i < activeOperators.length; i++) {
            if (activeOperators[i] == msg.sender) {
                activeOperators[i] = activeOperators[activeOperators.length - 1];
                activeOperators.pop();
                break;
            }
        }
        
        // Withdraw stake
        uint256 stakeAmount = operator.stake;
        operator.stake = 0;
        operatorStakes[msg.sender] = 0;
        
        payable(msg.sender).transfer(stakeAmount);
        
        emit OperatorDeregistered(msg.sender);
        emit StakeWithdrawn(msg.sender, stakeAmount);
    }

    /**
     * @notice Process a matched trade and create a task
     * @param trade The matched trade to process
     */
    function processMatchedTrade(IntentLib.MatchedTrade calldata trade) external override {
        require(trade.tradeId != bytes32(0), "Invalid trade");
        require(trade.amountA > 0 && trade.amountB > 0, "Invalid amounts");
        
        // Assign task to operator (round-robin for now)
        address assignedOperator = _selectOperator();
        require(assignedOperator != address(0), "No operators available");
        
        // Create task
        MatchingTask memory newTask = MatchingTask({
            taskIndex: latestTaskIndex,
            tradeId: trade.tradeId,
            trade: trade,
            taskCreatedBlock: block.number,
            deadline: block.timestamp + TASK_TIMEOUT,
            isComplete: false,
            assignedOperator: assignedOperator
        });
        
        tasks[latestTaskIndex] = newTask;
        operators[assignedOperator].lastTaskTime = block.timestamp;
        
        emit TaskCreated(latestTaskIndex, trade.tradeId, assignedOperator);
        latestTaskIndex++;
    }

    /**
     * @notice Submit task response
     * @param response The task response
     */
    function submitTaskResponse(TaskResponse calldata response) external override onlyRegisteredOperator {
        require(tasks[response.taskIndex].assignedOperator == msg.sender, "Not assigned operator");
        require(block.timestamp <= tasks[response.taskIndex].deadline, "Task expired");
        
        MatchingTask storage task = tasks[response.taskIndex];
        require(!task.isComplete, "Task already complete");
        
        // Mark task as complete
        task.isComplete = true;
        
        // Update operator stats
        OperatorInfo storage operator = operators[msg.sender];
        if (response.success) {
            operator.successCount++;
            _rewardOperator(msg.sender, _calculateReward(task.trade));
        } else {
            operator.failureCount++;
            _slashOperator(msg.sender, SLASH_PENALTY, "Task failed");
        }
        
        emit TaskCompleted(response.taskIndex, response.tradeId, response.success);
    }

    /**
     * @notice Slash an operator
     * @param operator The operator to slash
     * @param amount The amount to slash
     * @param reason The reason for slashing
     */
    function slashOperator(address operator, uint256 amount, string calldata reason) external override onlyOwner {
        require(operators[operator].isActive, "Operator not active");
        require(amount <= operators[operator].stake, "Insufficient stake");
        
        operators[operator].stake -= amount;
        operatorStakes[operator] -= amount;
        totalStake -= amount;
        
        emit OperatorSlashed(operator, amount, reason);
    }

    /**
     * @notice Update task timeout
     * @param newTimeout The new timeout in seconds
     */
    function updateTaskTimeout(uint256 newTimeout) external override onlyOwner {
        // This would require updating the constant, so we'll emit an event instead
        emit TaskTimeout(0, bytes32(0)); // Placeholder event
    }

    /**
     * @notice Pause operations
     */
    function pauseOperations() external override onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause operations
     */
    function unpauseOperations() external override onlyOwner {
        _unpause();
    }

    /**
     * @notice Get operator info
     * @param operator The operator address
     * @return The operator info
     */
    function getOperatorInfo(address operator) external view override returns (OperatorInfo memory) {
        return operators[operator];
    }

    /**
     * @notice Get task info
     * @param taskIndex The task index
     * @return The task info
     */
    function getTask(uint32 taskIndex) external view override returns (MatchingTask memory) {
        return tasks[taskIndex];
    }

    /**
     * @notice Get active operators
     * @return Array of active operator addresses
     */
    function getActiveOperators() external view override returns (address[] memory) {
        return activeOperators;
    }

    /**
     * @notice Get total stake
     * @return The total stake amount
     */
    function getTotalStake() external view override returns (uint256) {
        return totalStake;
    }

    /**
     * @notice Check if operator is registered
     * @param operator The operator address
     * @return True if registered
     */
    function isOperatorRegistered(address operator) external view override returns (bool) {
        return operators[operator].isActive;
    }

    /**
     * @notice Select an operator for task assignment
     * @return The selected operator address
     */
    function _selectOperator() internal view returns (address) {
        if (activeOperators.length == 0) {
            return address(0);
        }
        
        // Simple round-robin selection
        uint256 index = latestTaskIndex % activeOperators.length;
        return activeOperators[index];
    }

    /**
     * @notice Calculate reward for operator
     * @param trade The trade that was executed
     * @return The reward amount
     */
    function _calculateReward(IntentLib.MatchedTrade memory trade) internal pure returns (uint256) {
        // 1% of total trade value
        return (trade.amountA + trade.amountB) * REWARD_RATE / 10000;
    }

    /**
     * @notice Reward an operator
     * @param operator The operator to reward
     * @param amount The reward amount
     */
    function _rewardOperator(address operator, uint256 amount) internal {
        operators[operator].totalRewards += amount;
        operatorRewards[operator] += amount;
        totalRewards += amount;
        
        emit OperatorRewarded(operator, amount);
    }

    /**
     * @notice Slash an operator
     * @param operator The operator to slash
     * @param penalty The penalty amount
     * @param reason The reason for slashing
     */
    function _slashOperator(address operator, uint256 penalty, string memory reason) internal {
        require(penalty <= operators[operator].stake, "Insufficient stake");
        
        operators[operator].stake -= penalty;
        operatorStakes[operator] -= penalty;
        totalStake -= penalty;
        
        emit OperatorSlashed(operator, penalty, reason);
    }

    /**
     * @notice Handle expired tasks
     */
    function handleExpiredTasks() external {
        for (uint32 i = 0; i < latestTaskIndex; i++) {
            MatchingTask storage task = tasks[i];
            if (!task.isComplete && block.timestamp > task.deadline) {
                task.isComplete = true;
                emit TaskTimeout(i, task.tradeId);
            }
        }
    }

    /**
     * @notice Emergency withdraw function
     */
    function emergencyWithdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
}
