// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IStakeRegistry {
    struct StrategyParams {
        address strategy;
        uint96 multiplier;
    }

    struct StakeUpdate {
        uint32 updateBlockNumber;
        uint32 nextUpdateBlockNumber;
        uint96 stake;
    }

    function registerOperator(
        address operator,
        bytes32 operatorId,
        bytes calldata quorumNumbers
    ) external returns (uint96[] memory);

    function deregisterOperator(
        bytes32 operatorId,
        bytes calldata quorumNumbers
    ) external;

    function updateOperatorStake(
        address operator,
        bytes32 operatorId,
        bytes calldata quorumNumbers
    ) external returns (uint96[] memory);

    function getCurrentStake(bytes32 operatorId, uint8 quorumNumber)
        external
        view
        returns (uint96);

    function getStakeAtBlockNumber(bytes32 operatorId, uint8 quorumNumber, uint32 blockNumber)
        external
        view
        returns (uint96);

    function getTotalStakeAtBlockNumber(uint8 quorumNumber, uint32 blockNumber)
        external
        view
        returns (uint96);

    function getLatestStakeUpdate(bytes32 operatorId, uint8 quorumNumber)
        external
        view
        returns (StakeUpdate memory);

    function minimumStakeForQuorum(uint8 quorumNumber) external view returns (uint96);

    function strategyParams(uint8 quorumNumber, uint256 strategyIndex)
        external
        view
        returns (StrategyParams memory);

    function strategyParamsLength(uint8 quorumNumber) external view returns (uint256);

    event OperatorStakeUpdate(
        bytes32 indexed operatorId,
        uint8 quorumNumber,
        uint96 stake
    );

    event StakeRegistryCreated(uint8 indexed quorumNumber);
}