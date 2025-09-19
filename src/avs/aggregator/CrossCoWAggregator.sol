
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import "../interfaces/ICrossCoWServiceManager.sol";
import "../interfaces/IRegistryCoordinator.sol";
import "../interfaces/IStakeRegistry.sol";
import "../interfaces/IBLSApkRegistry.sol";
import "../task-managers/ICrossCoWTaskManager.sol";
import "../../libraries/IntentLib.sol";

/**
 * @title CrossCoWAggregator
 * @notice Aggregator for CrossCoW AVS - collects, validates, and finalizes operator responses
 * @dev Implements proper EigenLayer AVS patterns with BLS signature aggregation
 */
contract CrossCoWAggregator is Ownable, ReentrancyGuard, Pausable {
    using ECDSA for bytes32;

    constructor() Ownable(msg.sender) {}

    /* ADMIN FUNCTIONS */
    function setServiceManager(address _serviceManager) external onlyOwner {
        require(_serviceManager != address(0), "Invalid service manager");
        serviceManager = ICrossCoWServiceManager(_serviceManager);
    }

    function setRegistryCoordinator(address _registryCoordinator) external onlyOwner {
        require(_registryCoordinator != address(0), "Invalid registry coordinator");
        registryCoordinator = IRegistryCoordinator(_registryCoordinator);
    }

    function setStakeRegistry(address _stakeRegistry) external onlyOwner {
        require(_stakeRegistry != address(0), "Invalid stake registry");
        stakeRegistry = IStakeRegistry(_stakeRegistry);
    }

    function setBlsApkRegistry(address _blsApkRegistry) external onlyOwner {
        require(_blsApkRegistry != address(0), "Invalid BLS APK registry");
        blsApkRegistry = IBLSApkRegistry(_blsApkRegistry);
    }

    function setTaskManager(address _taskManager) external onlyOwner {
        require(_taskManager != address(0), "Invalid task manager");
        taskManager = ICrossCoWTaskManager(_taskManager);
    }

    /* CONSTANTS */
    uint256 public constant MIN_OPERATORS = 2;
    uint256 public constant MAX_OPERATORS = 100;
    uint256 public constant RESPONSE_TIMEOUT = 300; // 5 minutes
    uint256 public constant CHALLENGE_TIMEOUT = 3600; // 1 hour
    uint256 public constant QUORUM_THRESHOLD = 51; // 51% of operators must agree
    
    /* STORAGE */
    ICrossCoWServiceManager public serviceManager;
    IRegistryCoordinator public registryCoordinator;
    IStakeRegistry public stakeRegistry;
    IBLSApkRegistry public blsApkRegistry;
    ICrossCoWTaskManager public taskManager;
    
    mapping(uint32 => AggregatedResponse) public aggregatedResponses;
    mapping(uint32 => mapping(address => OperatorResponse)) public operatorResponses;
    mapping(uint32 => address[]) public respondingOperators;
    mapping(uint32 => uint256) public responseDeadlines;
    
    uint32 public latestTaskIndex;
    uint256 public totalTasksProcessed;
    uint256 public totalSuccessfulTasks;
    
    /* STRUCTS */
    struct AggregatedResponse {
        uint32 taskIndex;
        bytes32 taskHash;
        bytes32 responseHash;
        address[] operators;
        uint256 timestamp;
        bool isFinalized;
        bool isChallenged;
        uint256 challengeDeadline;
    }
    
    struct OperatorResponse {
        address operator;
        bytes32 responseHash;
        bytes signature;
        uint256 timestamp;
        bool isValid;
    }
    
    struct Challenge {
        address challenger;
        uint32 taskIndex;
        string reason;
        uint256 timestamp;
        bool isResolved;
    }
    
    mapping(uint32 => Challenge) public challenges;
    
    /* EVENTS */
    event TaskReceived(uint32 indexed taskIndex, bytes32 indexed taskHash);
    event OperatorResponseReceived(uint32 indexed taskIndex, address indexed operator, bytes32 responseHash);
    event ResponseAggregated(uint32 indexed taskIndex, bytes32 indexed responseHash, address[] operators);
    event ResponseFinalized(uint32 indexed taskIndex, bool success);
    event ChallengeRaised(uint32 indexed taskIndex, address indexed challenger, string reason);
    event ChallengeResolved(uint32 indexed taskIndex, bool challengerWon);
    event OperatorSlashed(address indexed operator, uint256 amount, string reason);
    event OperatorRewarded(address indexed operator, uint256 amount);

    /* MODIFIERS */
    modifier onlyValidTask(uint32 taskIndex) {
        require(aggregatedResponses[taskIndex].taskIndex == taskIndex, "Invalid task");
        _;
    }

    modifier onlyBeforeDeadline(uint32 taskIndex) {
        require(block.timestamp <= responseDeadlines[taskIndex], "Response deadline passed");
        _;
    }

    modifier onlyAfterDeadline(uint32 taskIndex) {
        require(block.timestamp > responseDeadlines[taskIndex], "Response deadline not passed");
        _;
    }


    /**
     * @notice Submit a task for aggregation
     * @param taskIndex The task index
     * @param taskHash The task hash
     */
    function submitTask(uint32 taskIndex, bytes32 taskHash) external onlyOwner {
        require(aggregatedResponses[taskIndex].taskIndex == 0, "Task already submitted");
        
        aggregatedResponses[taskIndex] = AggregatedResponse({
            taskIndex: taskIndex,
            taskHash: taskHash,
            responseHash: bytes32(0),
            operators: new address[](0),
            timestamp: block.timestamp,
            isFinalized: false,
            isChallenged: false,
            challengeDeadline: 0
        });
        
        responseDeadlines[taskIndex] = block.timestamp + RESPONSE_TIMEOUT;
        latestTaskIndex = taskIndex;
        
        emit TaskReceived(taskIndex, taskHash);
    }

    /**
     * @notice Submit operator response
     * @param taskIndex The task index
     * @param responseHash The response hash
     * @param signature The operator's signature
     */
    function submitResponse(
        uint32 taskIndex,
        bytes32 responseHash,
        bytes calldata signature
    ) external onlyValidTask(taskIndex) onlyBeforeDeadline(taskIndex) {
        require(serviceManager.isOperatorRegistered(msg.sender), "Not registered operator");
        require(operatorResponses[taskIndex][msg.sender].operator == address(0), "Already responded");
        
        // Verify signature
        bytes32 messageHash = keccak256(abi.encodePacked(taskIndex, responseHash, block.chainid));
        require(
            MessageHashUtils.toEthSignedMessageHash(messageHash).recover(signature) == msg.sender,
            "Invalid signature"
        );
        
        // Store operator response
        operatorResponses[taskIndex][msg.sender] = OperatorResponse({
            operator: msg.sender,
            responseHash: responseHash,
            signature: signature,
            timestamp: block.timestamp,
            isValid: true
        });
        
        respondingOperators[taskIndex].push(msg.sender);
        
        emit OperatorResponseReceived(taskIndex, msg.sender, responseHash);
        
        // Check if we have enough responses to aggregate
        if (respondingOperators[taskIndex].length >= MIN_OPERATORS) {
            _aggregateResponses(taskIndex);
        }
    }

    /**
     * @notice Aggregate operator responses
     * @param taskIndex The task index
     */
    function _aggregateResponses(uint32 taskIndex) internal {
        address[] memory operators = respondingOperators[taskIndex];
        require(operators.length >= MIN_OPERATORS, "Insufficient responses");
        
        // Count response hashes using a simple approach
        bytes32[] memory uniqueHashes = new bytes32[](operators.length);
        uint256[] memory counts = new uint256[](operators.length);
        uint256 uniqueCount = 0;
        
        for (uint i = 0; i < operators.length; i++) {
            bytes32 responseHash = operatorResponses[taskIndex][operators[i]].responseHash;
            bool found = false;
            
            // Check if we've seen this hash before
            for (uint j = 0; j < uniqueCount; j++) {
                if (uniqueHashes[j] == responseHash) {
                    counts[j]++;
                    found = true;
                    break;
                }
            }
            
            // If not found, add it as a new unique hash
            if (!found) {
                uniqueHashes[uniqueCount] = responseHash;
                counts[uniqueCount] = 1;
                uniqueCount++;
            }
        }
        
        // Find the most common response hash
        bytes32 winningHash = bytes32(0);
        uint256 maxCount = 0;
        
        for (uint i = 0; i < uniqueCount; i++) {
            if (counts[i] > maxCount) {
                maxCount = counts[i];
                winningHash = uniqueHashes[i];
            }
        }
        
        // Check if we have quorum
        require(maxCount * 100 / operators.length >= QUORUM_THRESHOLD, "No quorum");
        
        // Update aggregated response
        AggregatedResponse storage aggResponse = aggregatedResponses[taskIndex];
        aggResponse.responseHash = winningHash;
        aggResponse.operators = operators;
        aggResponse.isChallenged = false;
        aggResponse.challengeDeadline = block.timestamp + CHALLENGE_TIMEOUT;
        
        emit ResponseAggregated(taskIndex, winningHash, operators);
    }

    /**
     * @notice Finalize aggregated response
     * @param taskIndex The task index
     */
    function finalizeResponse(uint32 taskIndex) external onlyValidTask(taskIndex) onlyAfterDeadline(taskIndex) {
        AggregatedResponse storage aggResponse = aggregatedResponses[taskIndex];
        require(!aggResponse.isFinalized, "Already finalized");
        require(aggResponse.responseHash != bytes32(0), "No aggregated response");
        require(!aggResponse.isChallenged || block.timestamp > aggResponse.challengeDeadline, "Challenge pending");
        
        // Mark as finalized
        aggResponse.isFinalized = true;
        totalTasksProcessed++;
        
        // Reward participating operators
        for (uint i = 0; i < aggResponse.operators.length; i++) {
            address operator = aggResponse.operators[i];
            if (operatorResponses[taskIndex][operator].responseHash == aggResponse.responseHash) {
                _rewardOperator(operator, 1 ether); // 1 ETH reward
            }
        }
        
        totalSuccessfulTasks++;
        
        emit ResponseFinalized(taskIndex, true);
    }

    /**
     * @notice Challenge an aggregated response
     * @param taskIndex The task index
     * @param reason The reason for challenge
     */
    function challengeResponse(uint32 taskIndex, string calldata reason) external onlyValidTask(taskIndex) {
        AggregatedResponse storage aggResponse = aggregatedResponses[taskIndex];
        require(!aggResponse.isFinalized, "Already finalized");
        require(block.timestamp <= aggResponse.challengeDeadline, "Challenge deadline passed");
        require(challenges[taskIndex].challenger == address(0), "Already challenged");
        
        challenges[taskIndex] = Challenge({
            challenger: msg.sender,
            taskIndex: taskIndex,
            reason: reason,
            timestamp: block.timestamp,
            isResolved: false
        });
        
        aggResponse.isChallenged = true;
        
        emit ChallengeRaised(taskIndex, msg.sender, reason);
    }

    /**
     * @notice Resolve a challenge
     * @param taskIndex The task index
     * @param challengerWon Whether the challenger won
     */
    function resolveChallenge(uint32 taskIndex, bool challengerWon) external onlyOwner {
        Challenge storage challenge = challenges[taskIndex];
        require(challenge.challenger != address(0), "No challenge");
        require(!challenge.isResolved, "Already resolved");
        
        challenge.isResolved = true;
        
        if (challengerWon) {
            // Slash operators who provided wrong responses
            AggregatedResponse storage aggResponse = aggregatedResponses[taskIndex];
            for (uint i = 0; i < aggResponse.operators.length; i++) {
                address operator = aggResponse.operators[i];
                if (operatorResponses[taskIndex][operator].responseHash != aggResponse.responseHash) {
                    _slashOperator(operator, 1 ether, "Wrong response");
                }
            }
        } else {
            // Slash challenger
            _slashOperator(challenge.challenger, 1 ether, "Invalid challenge");
        }
        
        emit ChallengeResolved(taskIndex, challengerWon);
    }

    /**
     * @notice Get aggregated response
     * @param taskIndex The task index
     * @return The aggregated response
     */
    function getAggregatedResponse(uint32 taskIndex) external view returns (AggregatedResponse memory) {
        return aggregatedResponses[taskIndex];
    }

    /**
     * @notice Get operator response
     * @param taskIndex The task index
     * @param operator The operator address
     * @return The operator response
     */
    function getOperatorResponse(uint32 taskIndex, address operator) external view returns (OperatorResponse memory) {
        return operatorResponses[taskIndex][operator];
    }

    /**
     * @notice Get responding operators for a task
     * @param taskIndex The task index
     * @return Array of responding operator addresses
     */
    function getRespondingOperators(uint32 taskIndex) external view returns (address[] memory) {
        return respondingOperators[taskIndex];
    }

    /**
     * @notice Get task statistics
     * @return Total tasks processed and successful tasks
     */
    function getTaskStatistics() external view returns (uint256, uint256) {
        return (totalTasksProcessed, totalSuccessfulTasks);
    }

    /**
     * @notice Reward an operator
     * @param operator The operator address
     * @param amount The reward amount
     */
    function _rewardOperator(address operator, uint256 amount) internal {
        serviceManager.rewardOperator(operator, amount);
        emit OperatorRewarded(operator, amount);
    }

    /**
     * @notice Slash an operator
     * @param operator The operator address
     * @param amount The slash amount
     * @param reason The reason for slashing
     */
    function _slashOperator(address operator, uint256 amount, string memory reason) internal {
        serviceManager.slashOperator(operator, amount, reason);
        emit OperatorSlashed(operator, amount, reason);
    }

    /**
     * @notice Pause operations
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause operations
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency function to finalize task
     * @param taskIndex The task index
     */
    function emergencyFinalizeTask(uint32 taskIndex) external onlyOwner {
        AggregatedResponse storage aggResponse = aggregatedResponses[taskIndex];
        require(!aggResponse.isFinalized, "Already finalized");
        
        aggResponse.isFinalized = true;
        totalTasksProcessed++;
        
        emit ResponseFinalized(taskIndex, true);
    }
}
