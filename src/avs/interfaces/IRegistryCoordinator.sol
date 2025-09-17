// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IRegistryCoordinator
 * @notice Interface for CrossCoW registry coordinator
 */
interface IRegistryCoordinator {
    struct OperatorInfo {
        bytes32 operatorId;
        OperatorStatus status;
    }

    enum OperatorStatus {
        NEVER_REGISTERED,
        REGISTERED,
        DEREGISTERED
    }

    // Events
    event OperatorRegistered(bytes32 indexed operatorId, address indexed operator);
    event OperatorDeregistered(bytes32 indexed operatorId, address indexed operator);

    // Functions
    function registerOperator(
        bytes memory quorumNumbers,
        string memory socket,
        bytes memory params,
        bytes memory operatorSignature
    ) external;

    function deregisterOperator(bytes memory quorumNumbers) external;

    function getOperator(address operator) external view returns (OperatorInfo memory);
    
    function getOperatorStatus(address operator) external view returns (OperatorStatus);
    
    function getOperatorId(address operator) external view returns (bytes32);
}