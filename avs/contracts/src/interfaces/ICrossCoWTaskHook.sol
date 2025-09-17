// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IAVSTaskHook} from "@eigenlayer-contracts/src/contracts/interfaces/IAVSTaskHook.sol";
import {ITaskMailboxTypes} from "@eigenlayer-contracts/src/contracts/interfaces/ITaskMailbox.sol";

/**
 * @title ICrossCoWTaskHook
 * @notice Interface for CrossCoW Task Hook
 */
interface ICrossCoWTaskHook is IAVSTaskHook {
    /**
     * @notice Get the main CrossCoW Hook address
     * @return The address of the main CrossCoW logic contract
     */
    function getCrossCoWHook() external view returns (address);

    /**
     * @notice Get fee for a specific task type
     * @param taskType The task type
     * @return The fee for that task type
     */
    function getTaskTypeFee(bytes32 taskType) external view returns (uint96);

    /**
     * @notice Get all supported task types
     * @return Array of supported task type hashes
     */
    function getSupportedTaskTypes() external pure returns (bytes32[] memory);

    /**
     * @notice Update fee for a task type (only service manager)
     * @param taskType The task type to update
     * @param newFee The new fee amount
     */
    function updateTaskTypeFee(bytes32 taskType, uint96 newFee) external;

    /**
     * @notice Task type constants
     */
    function TASK_TYPE_INTENT_MATCHING() external pure returns (bytes32);
    function TASK_TYPE_CROSS_CHAIN_EXECUTION() external pure returns (bytes32);
    function TASK_TYPE_TRADE_VALIDATION() external pure returns (bytes32);
    function TASK_TYPE_SETTLEMENT() external pure returns (bytes32);

    /**
     * @notice Events
     */
    event TaskValidated(bytes32 indexed taskHash, bytes32 taskType, address caller);
    event TaskCreated(bytes32 indexed taskHash, bytes32 taskType);
    event TaskResultSubmitted(bytes32 indexed taskHash, address caller);
    event TaskFeeCalculated(bytes32 indexed taskHash, bytes32 taskType, uint96 fee);
    event CrossCoWHookUpdated(address indexed oldHook, address indexed newHook);
}
