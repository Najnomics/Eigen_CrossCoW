// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title ICrossCoWServiceManager
 * @notice Interface for CrossCoW Service Manager
 */
interface ICrossCoWServiceManager {
    /**
     * @notice Register an operator specifically for CrossCoW tasks
     * @param operator The operator address to register
     * @param operatorSignature The operator's signature for EigenLayer
     */
    function registerCrossCoWOperator(
        address operator,
        bytes calldata operatorSignature
    ) external payable;

    /**
     * @notice Deregister an operator from CrossCoW tasks
     * @param operator The operator address to deregister
     */
    function deregisterCrossCoWOperator(address operator) external;

    /**
     * @notice Check if an operator meets CrossCoW requirements
     * @param operator The operator address to check
     * @return Whether the operator is qualified for CrossCoW operations
     */
    function isCrossCoWOperatorQualified(address operator) external view returns (bool);

    /**
     * @notice Get the L2 CrossCoW Hook contract address
     * @return The address of the main CrossCoW logic contract
     */
    function getCrossCoWHook() external view returns (address);

    /**
     * @notice Process a matched trade from the main CrossCoW Hook
     * @param tradeData The matched trade data
     */
    function processMatchedTrade(bytes calldata tradeData) external;

    /**
     * @notice Events
     */
    event CrossCoWOperatorRegistered(address indexed operator, bytes32 indexed operatorId);
    event CrossCoWOperatorDeregistered(address indexed operator, bytes32 indexed operatorId);
    event CrossCoWHookUpdated(address indexed oldHook, address indexed newHook);
    event MatchedTradeProcessed(bytes32 indexed tradeId, address indexed operator);
}
