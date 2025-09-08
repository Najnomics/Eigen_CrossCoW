// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface ICrossCoWTaskManager {
    // Task-related events
    event NewTradeMatchingTaskCreated(uint32 indexed taskIndex, TradeMatchingTask task);
    event TradeMatchingTaskResponded(uint32 indexed taskIndex, TradeMatchingTask task, TradeMatchingResponse response);
    event CrossChainExecutionInitiated(uint32 indexed taskIndex, bytes32 acrossDepositId);
    event CrossChainExecutionCompleted(uint32 indexed taskIndex, bool success);
    event TradeMatchingTaskChallenged(uint32 indexed taskIndex, address challenger);

    // Data structures
    struct Intent {
        address user;
        address inputToken;
        address outputToken;
        uint256 inputAmount;
        uint256 minOutputAmount;
        uint32 sourceChain;
        uint32 destinationChain;
        uint32 deadline;
        bytes signature;
    }

    struct TradeMatchingTask {
        Intent[] intents;
        uint256 maxSlippage;
        uint32 deadline;
        uint32 taskCreatedBlock;
        bytes32 intentPoolHash;
    }

    struct MatchedTrade {
        uint32 intentAIndex;
        uint32 intentBIndex;
        uint256 executionAmount;
        uint256 bridgeFee;
        bytes executionProof;
    }

    struct TradeMatchingResponse {
        uint32 referenceTaskIndex;
        MatchedTrade[] matches;
        uint256 totalGasEstimate;
        uint32 executionPriority;
    }

    struct CrossChainExecution {
        bytes32 acrossDepositId;
        address sourceToken;
        address destinationToken;
        uint256 amount;
        uint32 sourceChain;
        uint32 destinationChain;
        bool completed;
        bool success;
        uint256 executedAt;
    }

    // Simplified signature verification (no BLS)
    struct SimpleSignature {
        address signer;
        bytes signature;
        uint32 signatureType; // 0 = ECDSA, 1 = Multi-sig
    }

    // View functions
    function latestTaskNum() external view returns (uint32);
    function allTaskHashes(uint32 taskIndex) external view returns (bytes32);
    function allTaskResponses(uint32 taskIndex) external view returns (bytes32);
    function taskSuccessfullyCompleted(uint32 taskIndex) external view returns (bool);
    function taskSuccessfullyChallenged(uint32 taskIndex) external view returns (bool);
    function getTaskExecution(uint32 taskIndex) external view returns (CrossChainExecution memory);

    // Core functions
    function createNewTradeMatchingTask(
        Intent[] memory intents,
        uint256 maxSlippage,
        uint32 deadline
    ) external returns (TradeMatchingTask memory);

    function respondToTradeMatchingTask(
        TradeMatchingTask calldata task,
        TradeMatchingResponse calldata taskResponse,
        SimpleSignature calldata signature
    ) external;

    function raiseAndResolveChallenge(
        TradeMatchingTask calldata task,
        TradeMatchingResponse calldata taskResponse,
        uint32 taskIndex,
        string calldata reason
    ) external;

    function onAcrossDepositFilled(
        bytes32 depositId,
        bool success
    ) external;
}