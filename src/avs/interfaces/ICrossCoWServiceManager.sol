// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../../libraries/IntentLib.sol";

interface ICrossCoWServiceManager {
    struct OperatorInfo {
        address operatorAddress;
        uint256 stake;
        bool isActive;
        uint256 lastTaskTime;
        uint256 successCount;
        uint256 failureCount;
        uint256 totalRewards;
    }

    struct MatchingTask {
        uint32 taskIndex;
        bytes32 tradeId;
        IntentLib.MatchedTrade trade;
        uint256 taskCreatedBlock;
        uint256 deadline;
        bool isComplete;
        address assignedOperator;
    }

    struct TaskResponse {
        uint32 taskIndex;
        bytes32 tradeId;
        bool success;
        bytes32 acrossDepositId;
        uint256 gasUsed;
        uint256 executionTime;
        bytes signature;
    }

    // Events
    event OperatorRegistered(address indexed operator, uint256 stake);
    event OperatorDeregistered(address indexed operator);
    event TaskCreated(uint32 indexed taskIndex, bytes32 indexed tradeId, address indexed assignedOperator);
    event TaskCompleted(uint32 indexed taskIndex, bytes32 indexed tradeId, bool success);
    event TaskTimeout(uint32 indexed taskIndex, bytes32 indexed tradeId);
    event OperatorSlashed(address indexed operator, uint256 amount, string reason);
    event OperatorRewarded(address indexed operator, uint256 amount);

    // Core functions
    function registerOperator(bytes calldata operatorSignature) external payable;
    function deregisterOperator() external;
    function processMatchedTrade(IntentLib.MatchedTrade calldata trade) external;
    function submitTaskResponse(TaskResponse calldata response) external;
    
    // Admin functions
    function slashOperator(address operator, uint256 amount, string calldata reason) external;
    function rewardOperator(address operator, uint256 amount) external;
    function updateTaskTimeout(uint256 newTimeout) external;
    function pauseOperations() external;
    function unpauseOperations() external;
    
    // View functions
    function getOperatorInfo(address operator) external view returns (OperatorInfo memory);
    function getTask(uint32 taskIndex) external view returns (MatchingTask memory);
    function getActiveOperators() external view returns (address[] memory);
    function getTotalStake() external view returns (uint256);
    function isOperatorRegistered(address operator) external view returns (bool);
}