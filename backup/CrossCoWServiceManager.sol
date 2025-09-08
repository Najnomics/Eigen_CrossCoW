// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@eigenlayer/contracts/interfaces/IAVSDirectory.sol";
import "@eigenlayer/contracts/interfaces/IRegistryCoordinator.sol";
import "@eigenlayer/contracts/interfaces/IStakeRegistry.sol";
import "@eigenlayer/contracts/interfaces/IBLSApkRegistry.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "./interfaces/ICrossCoWServiceManager.sol";
import "../libraries/IntentLib.sol";

contract CrossCoWServiceManager is ICrossCoWServiceManager, Ownable, ReentrancyGuard, Pausable {
    using ECDSA for bytes32;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    uint256 public constant MINIMUM_STAKE = 32 ether;
    uint256 public constant TASK_RESPONSE_WINDOW = 60; // 60 seconds
    uint256 public constant CHALLENGE_WINDOW = 7 days;
    uint256 public constant MINIMUM_QUORUM_SIZE = 3;
    uint256 public constant OPERATOR_REWARD_RATE = 100; // 1% in basis points
    uint256 public constant BASIS_POINTS = 10000;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    IAVSDirectory public immutable avsDirectory;
    IRegistryCoordinator public immutable registryCoordinator;
    IStakeRegistry public immutable stakeRegistry;
    IBLSApkRegistry public immutable blsApkRegistry;

    uint32 public latestTaskNum;
    uint256 public taskTimeout = TASK_RESPONSE_WINDOW;
    
    // Operator management
    mapping(address => OperatorInfo) public operators;
    address[] public registeredOperators;
    mapping(address => uint256) public operatorIndex;
    
    // Task management
    mapping(uint32 => MatchingTask) public tasks;
    mapping(uint32 => TaskResponse) public taskResponses;
    mapping(uint32 => mapping(address => bool)) public operatorResponded;
    mapping(uint32 => bool) public taskChallenged;
    
    // Hook authorization
    mapping(address => bool) public authorizedHooks;
    
    // Rewards and slashing
    uint256 public rewardPool;
    uint256 public totalRewardsDistributed;
    uint256 public totalSlashed;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event HookAuthorized(address indexed hook, bool authorized);
    event TaskTimeoutUpdated(uint256 oldTimeout, uint256 newTimeout);
    event RewardPoolFunded(address indexed funder, uint256 amount);
    event EmergencyWithdraw(address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    modifier onlyAuthorizedHook() {
        require(authorizedHooks[msg.sender], "Not authorized hook");
        _;
    }
    
    modifier onlyRegisteredOperator() {
        require(operators[msg.sender].isActive, "Not registered operator");
        _;
    }
    
    modifier onlyValidTask(uint32 taskIndex) {
        require(taskIndex < latestTaskNum, "Invalid task index");
        require(!tasks[taskIndex].isComplete, "Task already complete");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(
        IAVSDirectory _avsDirectory,
        IRegistryCoordinator _registryCoordinator,
        IStakeRegistry _stakeRegistry,
        IBLSApkRegistry _blsApkRegistry
    ) Ownable(msg.sender) {
        avsDirectory = _avsDirectory;
        registryCoordinator = _registryCoordinator;
        stakeRegistry = _stakeRegistry;
        blsApkRegistry = _blsApkRegistry;
    }

    /*//////////////////////////////////////////////////////////////
                        OPERATOR MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    
    function registerOperator(bytes calldata operatorSignature) 
        external 
        payable 
        nonReentrant 
        whenNotPaused 
    {
        require(!operators[msg.sender].isActive, "Already registered");
        require(msg.value >= MINIMUM_STAKE, "Insufficient stake");
        
        // Register with EigenLayer AVS Directory
        avsDirectory.registerOperatorToAVS(msg.sender, operatorSignature);
        
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
        
        // Add to operators array
        operatorIndex[msg.sender] = registeredOperators.length;
        registeredOperators.push(msg.sender);
        
        emit OperatorRegistered(msg.sender, msg.value);
    }
    
    function deregisterOperator() external onlyRegisteredOperator nonReentrant {
        // Deregister from EigenLayer
        avsDirectory.deregisterOperatorFromAVS(msg.sender);
        
        OperatorInfo storage operatorInfo = operators[msg.sender];
        uint256 stake = operatorInfo.stake;
        
        // Mark as inactive
        operatorInfo.isActive = false;
        operatorInfo.stake = 0;
        
        // Remove from operators array
        _removeOperator(msg.sender);
        
        // Return stake
        payable(msg.sender).transfer(stake);
        
        emit OperatorDeregistered(msg.sender);
    }
    
    function addStake() external payable onlyRegisteredOperator {
        operators[msg.sender].stake += msg.value;
    }

    /*//////////////////////////////////////////////////////////////
                            TASK MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    
    function processMatchedTrade(IntentLib.MatchedTrade calldata trade) 
        external 
        onlyAuthorizedHook 
        nonReentrant 
        whenNotPaused 
    {
        require(registeredOperators.length >= MINIMUM_QUORUM_SIZE, "Insufficient operators");
        require(!trade.isExecuted, "Trade already executed");
        
        uint32 taskIndex = latestTaskNum++;
        address assignedOperator = _selectOperator(taskIndex);
        
        tasks[taskIndex] = MatchingTask({
            taskIndex: taskIndex,
            tradeId: trade.tradeId,
            trade: trade,
            taskCreatedBlock: uint32(block.number),
            deadline: block.timestamp + taskTimeout,
            isComplete: false,
            assignedOperator: assignedOperator
        });
        
        // Update operator's last task time
        operators[assignedOperator].lastTaskTime = block.timestamp;
        
        emit TaskCreated(taskIndex, trade.tradeId, assignedOperator);
    }
    
    function submitTaskResponse(TaskResponse calldata response) 
        external 
        onlyRegisteredOperator 
        onlyValidTask(response.taskIndex) 
        nonReentrant 
    {
        MatchingTask storage task = tasks[response.taskIndex];
        require(task.assignedOperator == msg.sender, "Not assigned operator");
        require(block.timestamp <= task.deadline, "Task deadline passed");
        require(!operatorResponded[response.taskIndex][msg.sender], "Already responded");
        
        // Verify signature
        bytes32 responseHash = keccak256(abi.encode(response.taskIndex, response.tradeId, response.success));
        require(_verifyOperatorSignature(msg.sender, responseHash, response.signature), "Invalid signature");
        
        // Store response
        taskResponses[response.taskIndex] = response;
        operatorResponded[response.taskIndex][msg.sender] = true;
        
        // Complete task
        task.isComplete = true;
        
        // Update operator stats and distribute rewards
        if (response.success) {
            operators[msg.sender].successCount++;
            _distributeReward(msg.sender, task.trade.amountA + task.trade.amountB);
        } else {
            operators[msg.sender].failureCount++;
        }
        
        emit TaskCompleted(response.taskIndex, response.tradeId, response.success);
        
        // Notify hook contract
        if (response.success && authorizedHooks[tx.origin]) {
            // Calculate estimated savings (simplified)
            uint256 totalSavings = _calculateSavings(task.trade);
            
            // This would be called back to the hook
            // IEigenCrossCoWHook(tx.origin).confirmTradeExecution(
            //     response.tradeId,
            //     response.acrossDepositId,
            //     totalSavings
            // );
        }
    }
    
    function challengeTask(uint32 taskIndex) external payable {
        require(msg.value >= 0.1 ether, "Insufficient challenge stake");
        require(tasks[taskIndex].isComplete, "Task not complete");
        require(!taskChallenged[taskIndex], "Already challenged");
        require(
            block.timestamp <= tasks[taskIndex].deadline + CHALLENGE_WINDOW,
            "Challenge window expired"
        );
        
        taskChallenged[taskIndex] = true;
        
        // In a full implementation, this would trigger dispute resolution
        // For now, we'll just slash the operator if challenge is valid
        address operator = tasks[taskIndex].assignedOperator;
        _slashOperator(operator, operators[operator].stake / 10, "Task challenged");
        
        // Return challenge stake to challenger
        payable(msg.sender).transfer(msg.value);
    }

    /*//////////////////////////////////////////////////////////////
                           REWARD MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    
    function _distributeReward(address operator, uint256 tradeValue) internal {
        uint256 reward = (tradeValue * OPERATOR_REWARD_RATE) / BASIS_POINTS;
        
        if (reward > 0 && reward <= rewardPool) {
            rewardPool -= reward;
            operators[operator].totalRewards += reward;
            totalRewardsDistributed += reward;
            
            payable(operator).transfer(reward);
            emit OperatorRewarded(operator, reward);
        }
    }
    
    function _calculateSavings(IntentLib.MatchedTrade memory trade) internal pure returns (uint256) {
        // Simplified savings calculation
        // In practice, this would consider gas fees, bridge fees, slippage, etc.
        uint256 baseSavings = (trade.amountA + trade.amountB) / 100; // 1% base savings
        return baseSavings;
    }

    /*//////////////////////////////////////////////////////////////
                           SLASHING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function slashOperator(address operator, uint256 amount, string calldata reason) 
        external 
        onlyOwner 
    {
        _slashOperator(operator, amount, reason);
    }
    
    function _slashOperator(address operator, uint256 amount, string memory reason) internal {
        OperatorInfo storage operatorInfo = operators[operator];
        require(operatorInfo.isActive, "Operator not active");
        require(operatorInfo.stake >= amount, "Insufficient stake");
        
        operatorInfo.stake -= amount;
        totalSlashed += amount;
        rewardPool += amount; // Add slashed amount to reward pool
        
        emit OperatorSlashed(operator, amount, reason);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function authorizeHook(address hook, bool authorized) external onlyOwner {
        authorizedHooks[hook] = authorized;
        emit HookAuthorized(hook, authorized);
    }
    
    function updateTaskTimeout(uint256 newTimeout) external onlyOwner {
        require(newTimeout >= 30 && newTimeout <= 300, "Invalid timeout");
        uint256 oldTimeout = taskTimeout;
        taskTimeout = newTimeout;
        emit TaskTimeoutUpdated(oldTimeout, newTimeout);
    }
    
    function pauseOperations() external onlyOwner {
        _pause();
    }
    
    function unpauseOperations() external onlyOwner {
        _unpause();
    }
    
    function fundRewardPool() external payable {
        rewardPool += msg.value;
        emit RewardPoolFunded(msg.sender, msg.value);
    }
    
    function emergencyWithdraw(address payable to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid address");
        require(amount <= address(this).balance, "Insufficient balance");
        to.transfer(amount);
        emit EmergencyWithdraw(to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function getOperatorInfo(address operator) external view returns (OperatorInfo memory) {
        return operators[operator];
    }
    
    function getTask(uint32 taskIndex) external view returns (MatchingTask memory) {
        return tasks[taskIndex];
    }
    
    function getActiveOperators() external view returns (address[] memory) {
        uint256 activeCount = 0;
        
        // Count active operators
        for (uint256 i = 0; i < registeredOperators.length; i++) {
            if (operators[registeredOperators[i]].isActive) {
                activeCount++;
            }
        }
        
        // Create array of active operators
        address[] memory activeOperators = new address[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < registeredOperators.length; i++) {
            if (operators[registeredOperators[i]].isActive) {
                activeOperators[index] = registeredOperators[i];
                index++;
            }
        }
        
        return activeOperators;
    }
    
    function getTotalStake() external view returns (uint256) {
        uint256 totalStake = 0;
        for (uint256 i = 0; i < registeredOperators.length; i++) {
            if (operators[registeredOperators[i]].isActive) {
                totalStake += operators[registeredOperators[i]].stake;
            }
        }
        return totalStake;
    }
    
    function isOperatorRegistered(address operator) external view returns (bool) {
        return operators[operator].isActive;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _selectOperator(uint32 taskIndex) internal view returns (address) {
        require(registeredOperators.length > 0, "No operators available");
        
        // Simple round-robin selection
        uint256 index = taskIndex % registeredOperators.length;
        
        // Find next active operator
        for (uint256 i = 0; i < registeredOperators.length; i++) {
            uint256 currentIndex = (index + i) % registeredOperators.length;
            address operator = registeredOperators[currentIndex];
            
            if (operators[operator].isActive) {
                return operator;
            }
        }
        
        revert("No active operators");
    }
    
    function _removeOperator(address operator) internal {
        uint256 index = operatorIndex[operator];
        uint256 lastIndex = registeredOperators.length - 1;
        
        if (index != lastIndex) {
            address lastOperator = registeredOperators[lastIndex];
            registeredOperators[index] = lastOperator;
            operatorIndex[lastOperator] = index;
        }
        
        registeredOperators.pop();
        delete operatorIndex[operator];
    }
    
    function _verifyOperatorSignature(
        address operator,
        bytes32 messageHash,
        bytes memory signature
    ) internal pure returns (bool) {
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        address recovered = ethSignedMessageHash.recover(signature);
        return recovered == operator;
    }
    
    receive() external payable {
        rewardPool += msg.value;
    }
}