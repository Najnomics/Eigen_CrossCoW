// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IStakeRegistry
 * @notice Interface for CrossCoW stake registry
 */
interface IStakeRegistry {
    struct OperatorStakeUpdate {
        uint32 fromTaskNumber;
        uint32 toTaskNumber;
        uint96 stake;
    }

    struct StakeUpdate {
        uint32 updateBlockNumber;
        uint32 nextUpdateBlockNumber;
        uint96 stake;
    }

    // Events
    event StakeUpdated(
        bytes32 indexed operatorId,
        uint8 quorumNumber,
        uint96 stake
    );

    event QuorumCreated(uint8 indexed quorumNumber);

    // Functions
    function registerOperator(
        address operator,
        bytes32 operatorId,
        uint96 stake
    ) external;

    function deregisterOperator(bytes32 operatorId) external;

    function updateOperatorStake(
        address operator,
        bytes32 operatorId,
        uint96 stake
    ) external;

    function getCurrentStake(bytes32 operatorId, uint8 quorumNumber) 
        external view returns (uint96);

    function getStakeAtBlockNumberAndIndex(
        uint8 quorumNumber,
        uint32 blockNumber,
        bytes32 operatorId,
        uint256 index
    ) external view returns (uint96);

    function getLatestStakeUpdate(bytes32 operatorId, uint8 quorumNumber)
        external view returns (StakeUpdate memory);

    function getStakeUpdateAtIndex(uint8 quorumNumber, bytes32 operatorId, uint256 index)
        external view returns (StakeUpdate memory);

    function getStakeHistoryLength(bytes32 operatorId, uint8 quorumNumber) 
        external view returns (uint256);
}