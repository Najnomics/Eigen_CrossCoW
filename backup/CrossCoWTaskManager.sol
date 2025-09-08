// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@eigenlayer/contracts/permissions/Pausable.sol";
import "@eigenlayer-middleware/src/interfaces/IServiceManager.sol";
import {BLSApkRegistry} from "@eigenlayer-middleware/src/BLSApkRegistry.sol";
import {RegistryCoordinator} from "@eigenlayer-middleware/src/RegistryCoordinator.sol";
import {IRegistryCoordinator} from "@eigenlayer-middleware/src/interfaces/IRegistryCoordinator.sol";
import {BLSSignatureChecker} from "@eigenlayer-middleware/src/BLSSignatureChecker.sol";
import {OperatorStateRetriever} from "@eigenlayer-middleware/src/OperatorStateRetriever.sol";
import "@eigenlayer-middleware/src/libraries/BN254.sol";
import "./ICrossCoWTaskManager.sol";
import "../../integration/AcrossIntegration.sol";

/**
 * @title CrossCoW Task Manager
 * @notice Manages cross-chain CoW trading tasks with EigenLayer AVS integration
 * @dev Handles task creation, response aggregation, and cross-chain execution via Across Protocol
 */
contract CrossCoWTaskManager is
    Initializable,
    OwnableUpgradeable,
    Pausable,
    BLSSignatureChecker,
    OperatorStateRetriever,
    ICrossCoWTaskManager
{
    using BN254 for BN254.G1Point;

    /* CONSTANTS */
    uint32 public immutable TASK_RESPONSE_WINDOW_BLOCK;
    uint32 public constant TASK_CHALLENGE_WINDOW_BLOCK = 100;
    uint256 internal constant _THRESHOLD_DENOMINATOR = 100;

    /* STORAGE */
    // Latest task index
    uint32 public latestTaskNum;

    // Task storage
    mapping(uint32 => bytes32) public allTaskHashes;
    mapping(uint32 => bytes32) public allTaskResponses;
    mapping(uint32 => bool) public taskSuccessfullyCompleted;
    mapping(uint32 => bool) public taskSuccessfullyChallenged;

    // Cross-chain execution tracking
    mapping(uint32 => CrossChainExecution) public taskExecutions;
    mapping(bytes32 => uint32) public acrossDepositToTask; // Maps Across deposit ID to task

    // Contract addresses
    address public aggregator;
    address public generator;
    address public serviceManager;
    AcrossIntegration public acrossIntegration;

    /* EVENTS */
    event NewTradeMatchingTaskCreated(uint32 indexed taskIndex, TradeMatchingTask task);
    event TradeMatchingTaskResponded(uint32 indexed taskIndex, TradeMatchingTask task, TradeMatchingResponse response);
    event CrossChainExecutionInitiated(uint32 indexed taskIndex, bytes32 acrossDepositId);
    event CrossChainExecutionCompleted(uint32 indexed taskIndex, bool success);
    event TradeMatchingTaskChallenged(uint32 indexed taskIndex, address challenger);
    
    /* MODIFIERS */
    modifier onlyAggregator() {
        require(msg.sender == aggregator, "Only aggregator can call this function");
        _;
    }

    modifier onlyTaskGenerator() {
        require(msg.sender == generator, "Only task generator can call this function");
        _;
    }

    constructor(
        IRegistryCoordinator _registryCoordinator,
        uint32 _taskResponseWindowBlock
    ) BLSSignatureChecker(_registryCoordinator) {
        TASK_RESPONSE_WINDOW_BLOCK = _taskResponseWindowBlock;
    }

    function initialize(
        IPauserRegistry _pauserRegistry,
        address initialOwner,
        address _aggregator,
        address _generator,
        address _serviceManager,
        address _acrossIntegration
    ) public initializer {
        _initializePauser(_pauserRegistry, UNPAUSE_ALL);
        _transferOwnership(initialOwner);
        aggregator = _aggregator;
        generator = _generator;
        serviceManager = _serviceManager;
        acrossIntegration = AcrossIntegration(_acrossIntegration);
    }

    /**
     * @notice Creates a new trade matching task
     * @param intents Array of user trading intents to match
     * @param maxSlippage Maximum allowed slippage in basis points
     * @param deadline Task execution deadline
     */
    function createNewTradeMatchingTask(
        Intent[] memory intents,
        uint256 maxSlippage,
        uint32 deadline
    ) external onlyTaskGenerator returns (TradeMatchingTask memory) {
        require(intents.length >= 2, "Need at least 2 intents to match");
        require(deadline > block.timestamp, "Deadline must be in the future");
        require(maxSlippage <= 1000, "Max slippage cannot exceed 10%"); // 10% = 1000 basis points

        // Validate all intents
        for (uint i = 0; i < intents.length; i++) {
            require(_validateIntent(intents[i]), "Invalid intent");
        }

        TradeMatchingTask memory newTask = TradeMatchingTask({
            intents: intents,
            maxSlippage: maxSlippage,
            deadline: deadline,
            taskCreatedBlock: uint32(block.number),
            intentPoolHash: keccak256(abi.encode(intents))
        });

        // Store task hash
        allTaskHashes[latestTaskNum] = keccak256(abi.encode(newTask));

        emit NewTradeMatchingTaskCreated(latestTaskNum, newTask);

        latestTaskNum++;
        return newTask;
    }

    /**
     * @notice Responds to a trade matching task with BLS aggregated signatures
     * @param task The original task
     * @param taskResponse The matching response from operators
     * @param nonSignerStakesAndSignature BLS signature data
     */
    function respondToTradeMatchingTask(
        TradeMatchingTask calldata task,
        TradeMatchingResponse calldata taskResponse,
        NonSignerStakesAndSignature calldata nonSignerStakesAndSignature
    ) external onlyAggregator {
        uint32 taskIndex = taskResponse.referenceTaskIndex;
        
        // Validate task
        require(
            keccak256(abi.encode(task)) == allTaskHashes[taskIndex],
            "Task hash mismatch"
        );
        require(!taskSuccessfullyCompleted[taskIndex], "Task already completed");
        require(
            uint32(block.number) <= task.taskCreatedBlock + TASK_RESPONSE_WINDOW_BLOCK,
            "Task response window expired"
        );

        // Validate BLS signatures
        bytes32 messageHash = keccak256(abi.encode(taskResponse));
        _checkSignatures(
            messageHash,
            task.taskCreatedBlock,
            nonSignerStakesAndSignature
        );

        // Validate matching logic
        require(_validateMatching(task, taskResponse), "Invalid matching solution");

        // Store response
        allTaskResponses[taskIndex] = keccak256(abi.encode(taskResponse));
        taskSuccessfullyCompleted[taskIndex] = true;

        emit TradeMatchingTaskResponded(taskIndex, task, taskResponse);

        // Execute cross-chain trades
        _executeCrossChainTrades(taskIndex, task, taskResponse);
    }

    /**
     * @notice Executes the matched trades via Across Protocol
     * @dev This is where the actual cross-chain bridging happens
     */
    function _executeCrossChainTrades(
        uint32 taskIndex,
        TradeMatchingTask calldata task,
        TradeMatchingResponse calldata taskResponse
    ) internal {
        for (uint i = 0; i < taskResponse.matches.length; i++) {
            MatchedTrade memory matchedTrade = taskResponse.matches[i];
            Intent memory intentA = task.intents[matchedTrade.intentAIndex];
            Intent memory intentB = task.intents[matchedTrade.intentBIndex];

            // Execute cross-chain bridge for this matched pair
            _executeSingleCrossChainTrade(taskIndex, intentA, intentB, matchedTrade);
        }
    }

    /**
     * @notice Executes a single cross-chain trade pair
     */
    function _executeSingleCrossChainTrade(
        uint32 taskIndex,
        Intent memory intentA,
        Intent memory intentB,
        MatchedTrade memory matchedTrade
    ) internal {
        // Prepare Across bridge parameters
        AcrossIntegration.BridgeParams memory bridgeParams = AcrossIntegration.BridgeParams({
            inputToken: intentA.inputToken,
            outputToken: intentB.outputToken,
            inputAmount: matchedTrade.executionAmount,
            outputAmount: matchedTrade.executionAmount - matchedTrade.bridgeFee,
            recipient: intentB.user,
            originChainId: intentA.sourceChain,
            destinationChainId: intentB.destinationChain,
            quoteTimestamp: uint32(block.timestamp),
            fillDeadline: intentA.deadline,
            exclusivityDeadline: 0,
            exclusiveRelayer: address(0),
            message: ""
        });

        // Execute bridge through Across Protocol
        try acrossIntegration.depositV3(bridgeParams) returns (bytes32 depositId) {
            // Track the cross-chain execution
            taskExecutions[taskIndex] = CrossChainExecution({
                acrossDepositId: depositId,
                sourceToken: intentA.inputToken,
                destinationToken: intentB.outputToken,
                amount: matchedTrade.executionAmount,
                sourceChain: intentA.sourceChain,
                destinationChain: intentB.destinationChain,
                completed: false,
                success: false,
                executedAt: block.timestamp
            });

            // Map deposit ID back to task for callbacks
            acrossDepositToTask[depositId] = taskIndex;

            emit CrossChainExecutionInitiated(taskIndex, depositId);
        } catch Error(string memory reason) {
            emit CrossChainExecutionCompleted(taskIndex, false);
            // Could implement retry logic or mark task as failed
        }
    }

    /**
     * @notice Callback from Across Protocol when bridge is completed
     * @dev This would be called by Across relayers or monitoring system
     */
    function onAcrossDepositFilled(
        bytes32 depositId,
        bool success
    ) external {
        // Verify caller is authorized (Across Protocol or trusted relayer)
        // Implementation would check msg.sender against approved Across contracts

        uint32 taskIndex = acrossDepositToTask[depositId];
        require(taskIndex > 0, "Unknown deposit ID");

        CrossChainExecution storage execution = taskExecutions[taskIndex];
        require(!execution.completed, "Execution already completed");

        execution.completed = true;
        execution.success = success;

        emit CrossChainExecutionCompleted(taskIndex, success);
    }

    /**
     * @notice Challenge a task response for invalid matching
     */
    function raiseAndResolveChallenge(
        TradeMatchingTask calldata task,
        TradeMatchingResponse calldata taskResponse,
        uint32 taskIndex,
        string calldata reason
    ) external {
        require(!taskSuccessfullyChallenged[taskIndex], "Task already challenged");
        require(taskSuccessfullyCompleted[taskIndex], "Task not completed yet");
        require(
            uint32(block.number) <= task.taskCreatedBlock + TASK_RESPONSE_WINDOW_BLOCK + TASK_CHALLENGE_WINDOW_BLOCK,
            "Challenge window expired"
        );

        // Validate the challenge
        bool isValidChallenge = _validateChallenge(task, taskResponse, reason);
        require(isValidChallenge, "Invalid challenge");

        taskSuccessfullyChallenged[taskIndex] = true;

        emit TradeMatchingTaskChallenged(taskIndex, msg.sender);

        // TODO: Implement slashing logic
        // This would involve calling the ServiceManager to slash operators
        // who signed the invalid response
    }

    /**
     * @notice Validates a trading intent
     */
    function _validateIntent(Intent memory intent) internal pure returns (bool) {
        return (
            intent.user != address(0) &&
            intent.inputToken != address(0) &&
            intent.outputToken != address(0) &&
            intent.inputAmount > 0 &&
            intent.minOutputAmount > 0 &&
            intent.deadline > block.timestamp &&
            intent.sourceChain != intent.destinationChain
        );
    }

    /**
     * @notice Validates that the matching solution is optimal
     */
    function _validateMatching(
        TradeMatchingTask calldata task,
        TradeMatchingResponse calldata response
    ) internal pure returns (bool) {
        // Validate that all matches are feasible
        for (uint i = 0; i < response.matches.length; i++) {
            MatchedTrade memory match = response.matches[i];
            
            // Check intent indices are valid
            if (match.intentAIndex >= task.intents.length || 
                match.intentBIndex >= task.intents.length) {
                return false;
            }

            Intent memory intentA = task.intents[match.intentAIndex];
            Intent memory intentB = task.intents[match.intentBIndex];

            // Validate cross-chain compatibility
            if (intentA.sourceChain != intentB.destinationChain ||
                intentB.sourceChain != intentA.destinationChain) {
                return false;
            }

            // Validate token compatibility (should be complementary)
            if (intentA.outputToken != intentB.inputToken ||
                intentB.outputToken != intentA.inputToken) {
                return false;
            }

            // Validate amounts and slippage
            if (match.executionAmount > intentA.inputAmount ||
                match.executionAmount > intentB.inputAmount) {
                return false;
            }

            // Check minimum output amounts are satisfied after fees
            uint256 netAmountA = match.executionAmount - match.bridgeFee;
            if (netAmountA < intentA.minOutputAmount) {
                return false;
            }
        }

        return true;
    }

    /**
     * @notice Validates a challenge against a task response
     */
    function _validateChallenge(
        TradeMatchingTask calldata task,
        TradeMatchingResponse calldata response,
        string calldata reason
    ) internal pure returns (bool) {
        // Implement challenge validation logic
        // This could check for:
        // - Suboptimal matching
        // - Missed better matches
        // - Invalid cross-chain routes
        // - Excessive fees
        
        // For now, return false (no valid challenges)
        // In production, implement sophisticated challenge detection
        return false;
    }

    /**
     * @notice Get task execution status
     */
    function getTaskExecution(uint32 taskIndex) external view returns (CrossChainExecution memory) {
        return taskExecutions[taskIndex];
    }

    /**
     * @notice Emergency pause function
     */
    function pause(uint256 newPausedStatus) external onlyOwner {
        _pause(newPausedStatus);
    }

    /**
     * @notice Emergency unpause function
     */
    function unpause(uint256 newPausedStatus) external onlyOwner {
        _unpause(newPausedStatus);
    }
}