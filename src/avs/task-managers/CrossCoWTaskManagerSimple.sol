// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../../integration/AcrossIntegration.sol";
import "./ICrossCoWTaskManager.sol";
import "@uniswap/v4-core/types/Currency.sol";

/**
 * @title CrossCoWTaskManagerSimple
 * @notice Simplified TaskManager for CrossCoW without complex EigenLayer dependencies
 * @dev Focuses on core functionality - onchain Across Protocol integration
 */
contract CrossCoWTaskManagerSimple is Ownable, ReentrancyGuard, Pausable, ICrossCoWTaskManager {
    
    /* CONSTANTS */
    uint32 public constant TASK_RESPONSE_WINDOW = 300; // 5 minutes
    uint32 public constant TASK_CHALLENGE_WINDOW = 7200; // 2 hours
    
    /* STORAGE */
    uint32 public latestTaskNum;
    mapping(uint32 => bytes32) public allTaskHashes;
    mapping(uint32 => bool) public taskSuccessfullyCompleted;
    mapping(uint32 => CrossChainExecution) public taskExecutions;
    mapping(bytes32 => uint32) public acrossDepositToTask;
    
    address public aggregator;
    address public generator;
    AcrossIntegration public acrossIntegration;

    // Using structs from ICrossCoWTaskManager interface

    /* EVENTS - Using events from interface */

    /* MODIFIERS */
    modifier onlyAggregator() {
        require(msg.sender == aggregator, "Only aggregator");
        _;
    }

    modifier onlyTaskGenerator() {
        require(msg.sender == generator, "Only generator");
        _;
    }

    constructor(
        address _owner,
        address _aggregator,
        address _generator,
        address payable _acrossIntegration
    ) Ownable(_owner) {
        aggregator = _aggregator;
        generator = _generator;
        acrossIntegration = AcrossIntegration(_acrossIntegration);
    }

    /**
     * @notice Creates a new trade matching task
     */
    function createNewTradeMatchingTask(
        Intent[] memory intents,
        uint256 maxSlippage,
        uint32 deadline
    ) external onlyTaskGenerator returns (TradeMatchingTask memory) {
        require(intents.length >= 2, "Need at least 2 intents");
        require(deadline > block.timestamp, "Deadline must be future");
        require(maxSlippage <= 1000, "Max slippage 10%");

        TradeMatchingTask memory newTask = TradeMatchingTask({
            intents: intents,
            maxSlippage: maxSlippage,
            deadline: deadline,
            taskCreatedBlock: uint32(block.number),
            intentPoolHash: keccak256(abi.encode(intents))
        });

        allTaskHashes[latestTaskNum] = keccak256(abi.encode(newTask));
        emit NewTradeMatchingTaskCreated(latestTaskNum, newTask);
        latestTaskNum++;
        return newTask;
    }

    /**
     * @notice Simplified response handler (no BLS signature verification)
     */
    function respondToTradeMatchingTask(
        TradeMatchingTask calldata task,
        TradeMatchingResponse calldata taskResponse,
        SimpleSignature calldata /* signature */
    ) external onlyAggregator {
        uint32 taskIndex = taskResponse.referenceTaskIndex;
        
        require(
            keccak256(abi.encode(task)) == allTaskHashes[taskIndex],
            "Task hash mismatch"
        );
        require(!taskSuccessfullyCompleted[taskIndex], "Already completed");
        require(
            uint32(block.number) <= task.taskCreatedBlock + TASK_RESPONSE_WINDOW,
            "Response window expired"
        );

        taskSuccessfullyCompleted[taskIndex] = true;
        emit TradeMatchingTaskResponded(taskIndex, task, taskResponse);

        // Execute cross-chain trades via Across Protocol
        _executeCrossChainTrades(taskIndex, task, taskResponse);
    }

    /**
     * @notice Executes matched trades via Across Protocol
     * @dev This is the KEY FEATURE - onchain cross-chain execution
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

            _executeSingleCrossChainTrade(taskIndex, intentA, intentB, matchedTrade);
        }
    }

    /**
     * @notice Executes a single cross-chain trade pair via Across Protocol
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
            destinationChainId: intentB.destinationChain,
            recipient: intentB.user,
            fillDeadline: intentA.deadline,
            exclusivityDeadline: 0,
            exclusiveRelayer: address(0),
            message: ""
        });

        // Create a MatchedTrade struct for the call
        IntentLib.MatchedTrade memory matchedTradeStruct = IntentLib.MatchedTrade({
            tradeId: keccak256(abi.encode(taskIndex, intentA, intentB)),
            intentA: keccak256(abi.encode(intentA)),
            intentB: keccak256(abi.encode(intentB)),
            amountA: matchedTrade.executionAmount,
            amountB: matchedTrade.executionAmount - matchedTrade.bridgeFee,
            chainA: intentA.sourceChain,
            chainB: intentB.destinationChain,
            userA: intentA.user,
            userB: intentB.user,
            tokenA: Currency.wrap(intentA.inputToken),
            tokenB: Currency.wrap(intentB.outputToken),
            isExecuted: false,
            executionTime: 0,
            acrossDepositId: bytes32(0)
        });

        // Execute bridge through Across Protocol - THIS IS THE CORE FUNCTIONALITY
        try acrossIntegration.executeCrossChainTrade(matchedTradeStruct, bridgeParams) returns (uint32 depositId) {
            // Track the cross-chain execution
            taskExecutions[taskIndex] = CrossChainExecution({
                acrossDepositId: bytes32(uint256(depositId)),
                sourceToken: intentA.inputToken,
                destinationToken: intentB.outputToken,
                amount: matchedTrade.executionAmount,
                sourceChain: intentA.sourceChain,
                destinationChain: intentB.destinationChain,
                completed: false,
                success: false,
                executedAt: block.timestamp
            });

            acrossDepositToTask[bytes32(uint256(depositId))] = taskIndex;
            emit CrossChainExecutionInitiated(taskIndex, bytes32(uint256(depositId)));
        } catch Error(string memory) {
            emit CrossChainExecutionCompleted(taskIndex, false);
        }
    }

    /**
     * @notice Callback from Across Protocol when bridge is completed
     */
    function onAcrossDepositFilled(
        bytes32 depositId,
        bool success
    ) external {
        uint32 taskIndex = acrossDepositToTask[depositId];
        require(taskIndex > 0, "Unknown deposit");

        CrossChainExecution storage execution = taskExecutions[taskIndex];
        require(!execution.completed, "Already completed");

        execution.completed = true;
        execution.success = success;
        emit CrossChainExecutionCompleted(taskIndex, success);
    }

    /**
     * @notice Get task execution status
     */
    function getTaskExecution(uint32 taskIndex) external view returns (CrossChainExecution memory) {
        return taskExecutions[taskIndex];
    }

    // Interface implementations
    function allTaskResponses(uint32 taskIndex) external view returns (bytes32) {
        return bytes32(0); // Simplified implementation
    }

    function taskSuccessfullyChallenged(uint32 taskIndex) external view returns (bool) {
        return false; // Simplified implementation
    }

    function raiseAndResolveChallenge(
        TradeMatchingTask calldata,
        TradeMatchingResponse calldata,
        uint32,
        string calldata
    ) external {
        revert("Challenges not implemented in simplified version");
    }

    /**
     * @notice Admin functions
     */
    function setAggregator(address _aggregator) external onlyOwner {
        aggregator = _aggregator;
    }

    function setGenerator(address _generator) external onlyOwner {
        generator = _generator;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}