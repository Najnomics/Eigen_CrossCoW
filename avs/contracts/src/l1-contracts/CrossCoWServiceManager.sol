// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAllocationManager} from "@eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IKeyRegistrar} from "@eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";
import {IPermissionController} from "@eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {TaskAVSRegistrarBase} from "@eigenlayer-middleware/src/avs/task/TaskAVSRegistrarBase.sol";
import {ICrossCoWServiceManager} from "../interfaces/ICrossCoWServiceManager.sol";

/**
 * @title CrossCoWServiceManager
 * @notice EigenLayer L1 service manager for CrossCoW AVS
 * @dev This is a CONNECTOR contract that manages EigenLayer integration only.
 * The actual CrossCoW business logic remains in the main EigenCrossCoWHook contract.
 * This contract handles:
 * - Operator registration with EigenLayer
 * - Staking management
 * - Task validation (delegates to L2 hook for actual CrossCoW logic)
 */
contract CrossCoWServiceManager is TaskAVSRegistrarBase, ICrossCoWServiceManager {
    
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Address of the main CrossCoW Hook contract on L2
    address public immutable crossCoWHookL2;
    
    /// @notice Minimum stake required for CrossCoW operators
    uint256 public constant MINIMUM_CROSSCOW_STAKE = 10 ether;
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event CrossCoWOperatorRegistered(address indexed operator, bytes32 indexed operatorId);
    event CrossCoWOperatorDeregistered(address indexed operator, bytes32 indexed operatorId);
    event CrossCoWHookUpdated(address indexed oldHook, address indexed newHook);
    
    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @dev Constructor that passes parameters to parent TaskAVSRegistrarBase
     * @param _allocationManager The AllocationManager contract address
     * @param _keyRegistrar The KeyRegistrar contract address
     * @param _permissionController The PermissionController contract address
     * @param _crossCoWHookL2 The address of the main CrossCoW Hook on L2
     */
    constructor(
        IAllocationManager _allocationManager,
        IKeyRegistrar _keyRegistrar,
        IPermissionController _permissionController,
        address _crossCoWHookL2
    ) TaskAVSRegistrarBase(_allocationManager, _keyRegistrar, _permissionController) {
        require(_crossCoWHookL2 != address(0), "Invalid L2 hook address");
        crossCoWHookL2 = _crossCoWHookL2;
    }

    /*//////////////////////////////////////////////////////////////
                              INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @dev Initializer that calls parent initializer
     * @param _avs The address of the AVS
     * @param _owner The owner of the contract
     * @param _initialConfig The initial AVS configuration
     */
    function initialize(address _avs, address _owner, AvsConfig memory _initialConfig) external initializer {
        __TaskAVSRegistrarBase_init(_avs, _owner, _initialConfig);
    }

    /*//////////////////////////////////////////////////////////////
                         CROSSCOW-SPECIFIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register an operator specifically for CrossCoW tasks
     * @dev This extends the base registration with CrossCoW-specific requirements
     * @param operator The operator address to register
     * @param operatorSignature The operator's signature for EigenLayer
     */
    function registerCrossCoWOperator(
        address operator,
        bytes calldata operatorSignature
    ) external payable {
        require(msg.value >= MINIMUM_CROSSCOW_STAKE, "Insufficient stake for CrossCoW operations");
        
        // Call parent registration logic (handles EigenLayer integration)
        _registerOperator(operator, operatorSignature);
        
        bytes32 operatorId = keccak256(abi.encodePacked(operator, block.timestamp));
        emit CrossCoWOperatorRegistered(operator, operatorId);
    }

    /**
     * @notice Deregister an operator from CrossCoW tasks
     * @param operator The operator address to deregister
     */
    function deregisterCrossCoWOperator(address operator) external {
        // Call parent deregistration logic
        _deregisterOperator(operator);
        
        bytes32 operatorId = keccak256(abi.encodePacked(operator, block.timestamp));
        emit CrossCoWOperatorDeregistered(operator, operatorId);
    }

    /**
     * @notice Check if an operator meets CrossCoW requirements
     * @param operator The operator address to check
     * @return Whether the operator is qualified for CrossCoW operations
     */
    function isCrossCoWOperatorQualified(address operator) external view returns (bool) {
        // Check base registration status and add CrossCoW-specific checks
        return _isRegistered(operator) && _getOperatorStake(operator) >= MINIMUM_CROSSCOW_STAKE;
    }

    /**
     * @notice Get the L2 CrossCoW Hook contract address
     * @return The address of the main CrossCoW logic contract
     */
    function getCrossCoWHook() external view returns (address) {
        return crossCoWHookL2;
    }

    /**
     * @notice Process a matched trade from the main CrossCoW Hook
     * @param tradeData The matched trade data
     */
    function processMatchedTrade(bytes calldata tradeData) external override {
        // Only the main CrossCoW Hook can call this function
        require(msg.sender == crossCoWHookL2, "Only CrossCoW Hook can process trades");
        
        // Extract trade ID from trade data (first 32 bytes)
        bytes32 tradeId = bytes32(tradeData[:32]);
        
        // TODO: Implement trade processing logic
        // - Validate trade data
        // - Update operator rewards
        // - Emit events for monitoring
        
        emit MatchedTradeProcessed(tradeId, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal function to check operator registration
     * @param operator The operator address
     * @return Whether the operator is registered
     */
    function _isRegistered(address operator) internal view returns (bool) {
        // Implementation depends on TaskAVSRegistrarBase structure
        // This is a placeholder - actual implementation would check registration status
        return true; // TODO: Implement based on TaskAVSRegistrarBase
    }

    /**
     * @notice Internal function to get operator stake
     * @param operator The operator address
     * @return The operator's stake amount
     */
    function _getOperatorStake(address operator) internal view returns (uint256) {
        // Implementation depends on TaskAVSRegistrarBase structure  
        // This is a placeholder - actual implementation would return stake
        return 0; // TODO: Implement based on TaskAVSRegistrarBase
    }
}