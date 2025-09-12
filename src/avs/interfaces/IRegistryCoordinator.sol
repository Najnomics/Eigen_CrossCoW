// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRegistryCoordinator {
    struct OperatorInfo {
        bytes32 operatorId;
        uint32 fromTaskNumber;
        uint32 toTaskNumber;
        uint256 stakeWeight;
    }

    struct QuorumBitmapUpdate {
        uint32 updateBlockNumber;
        uint32 nextUpdateBlockNumber;
        uint192 quorumBitmap;
    }

    function registerOperator(
        bytes calldata quorumNumbers,
        string calldata socket,
        bytes calldata params,
        bytes calldata operatorSignature
    ) external;

    function deregisterOperator(bytes calldata quorumNumbers) external;

    function updateOperators(address[] calldata operators) external;

    function updateOperatorsForQuorum(
        address[][] memory operatorsPerQuorum,
        bytes calldata quorumNumbers
    ) external;

    function getOperator(address operator) external view returns (OperatorInfo memory);

    function getOperatorFromId(bytes32 operatorId) external view returns (address);

    function getOperatorId(address operator) external view returns (bytes32);

    function getQuorumBitmapUpdateByIndex(bytes32 operatorId, uint256 index)
        external
        view
        returns (QuorumBitmapUpdate memory);

    function getCurrentQuorumBitmap(bytes32 operatorId) external view returns (uint192);

    function getNumRegistries() external view returns (uint256);

    event OperatorRegistered(address indexed operator, bytes32 indexed operatorId);
    event OperatorDeregistered(address indexed operator, bytes32 indexed operatorId);
}