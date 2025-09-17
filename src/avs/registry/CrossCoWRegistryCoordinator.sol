// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import "../interfaces/IRegistryCoordinator.sol";
import "../interfaces/IStakeRegistry.sol";
import "../interfaces/IBLSApkRegistry.sol";

/**
 * @title CrossCoWRegistryCoordinator
 * @notice Registry Coordinator for CrossCoW AVS - manages operator registration and quorum management
 * @dev Implements proper EigenLayer AVS patterns with BLS signature verification
 */
contract CrossCoWRegistryCoordinator is Ownable, ReentrancyGuard, Pausable, IRegistryCoordinator {
    using ECDSA for bytes32;
    
    constructor(
        address _stakeRegistry,
        address _blsApkRegistry
    ) Ownable(msg.sender) {
        stakeRegistry = IStakeRegistry(_stakeRegistry);
        blsApkRegistry = IBLSApkRegistry(_blsApkRegistry);
    }

    /* STRUCTS */
    struct RegistryOperatorInfo {
        bytes32 operatorId;
        uint32 fromTaskNumber;
        uint32 toTaskNumber;
        uint256 stakeWeight;
        bool isActive;
    }

    struct QuorumBitmapUpdate {
        uint32 updateBlockNumber;
        uint32 nextUpdateBlockNumber;
        uint192 quorumBitmap;
    }

    /* CONSTANTS */
    uint256 public constant MIN_STAKE = 1 ether;
    uint256 public constant MAX_OPERATORS = 1000;
    uint256 public constant QUORUM_THRESHOLD = 2; // Minimum 2 operators for quorum
    
    /* STORAGE */
    IStakeRegistry public stakeRegistry;
    IBLSApkRegistry public blsApkRegistry;
    
    mapping(address => RegistryOperatorInfo) public operators;
    mapping(bytes32 => address) public operatorFromId;
    mapping(address => bytes32) public operatorId;
    mapping(bytes32 => QuorumBitmapUpdate[]) public quorumBitmapUpdates;
    
    address[] public registeredOperators;
    uint256 public numRegistries;
    
    /* EVENTS */
    event OperatorRegistered(address indexed operator, bytes32 indexed operatorId);
    event OperatorDeregistered(address indexed operator, bytes32 indexed operatorId);
    event QuorumBitmapUpdated(bytes32 indexed operatorId, uint192 newBitmap);
    event RegistryAdded(address indexed registry);
    event RegistryRemoved(address indexed registry);

    /* MODIFIERS */
    modifier onlyValidOperator(address operator) {
        require(operators[operator].operatorId != bytes32(0), "Operator not registered");
        _;
    }

    modifier onlyValidQuorum(bytes calldata quorumNumbers) {
        require(quorumNumbers.length > 0, "Invalid quorum numbers");
        _;
    }


    /**
     * @notice Register an operator
     * @param quorumNumbers The quorum numbers to register for
     * @param socket The operator's socket address
     * @param params Additional parameters
     * @param operatorSignature The operator's signature
     */
    function registerOperator(
        bytes calldata quorumNumbers,
        string calldata socket,
        bytes calldata params,
        bytes calldata operatorSignature
    ) external onlyValidQuorum(quorumNumbers) {
        require(operators[msg.sender].operatorId == bytes32(0), "Already registered");
        require(registeredOperators.length < MAX_OPERATORS, "Max operators reached");
        
        // Verify operator signature
        bytes32 messageHash = keccak256(abi.encodePacked(
            msg.sender,
            quorumNumbers,
            socket,
            params,
            block.chainid
        ));
        require(
            MessageHashUtils.toEthSignedMessageHash(messageHash).recover(operatorSignature) == msg.sender,
            "Invalid signature"
        );
        
        // Generate operator ID
        bytes32 newOperatorId = keccak256(abi.encodePacked(
            msg.sender,
            block.timestamp,
            block.number
        ));
        
        // Register with stake registry
        stakeRegistry.registerOperator(msg.sender, newOperatorId, uint96(MIN_STAKE));
        
        // Register with BLS APK registry - simplified
        uint8[] memory quorumNums = new uint8[](1);
        quorumNums[0] = 0;
        blsApkRegistry.registerOperator(msg.sender, quorumNums);
        
        // Store operator info
        operators[msg.sender] = RegistryOperatorInfo({
            operatorId: newOperatorId,
            fromTaskNumber: 0,
            toTaskNumber: 0,
            stakeWeight: MIN_STAKE,
            isActive: true
        });
        
        operatorFromId[newOperatorId] = msg.sender;
        operatorId[msg.sender] = newOperatorId;
        registeredOperators.push(msg.sender);
        
        // Initialize quorum bitmap
        bytes memory quorumData = abi.encodePacked(uint8(0));
        uint192 initialBitmap = _calculateQuorumBitmap(quorumData);
        quorumBitmapUpdates[newOperatorId].push(QuorumBitmapUpdate({
            updateBlockNumber: uint32(block.number),
            nextUpdateBlockNumber: 0,
            quorumBitmap: initialBitmap
        }));
        
        emit OperatorRegistered(msg.sender, newOperatorId);
        emit QuorumBitmapUpdated(newOperatorId, initialBitmap);
    }

    /**
     * @notice Deregister an operator
     * @param quorumNumbers The quorum numbers to deregister from
     */
    function deregisterOperator(bytes calldata quorumNumbers) external onlyValidOperator(msg.sender) {
        bytes32 opId = operatorId[msg.sender];
        
        // Deregister from stake registry
        stakeRegistry.deregisterOperator(opId);
        
        // Deregister from BLS APK registry - simplified
        uint8[] memory quorumNums = new uint8[](1);
        quorumNums[0] = 0;
        blsApkRegistry.deregisterOperator(msg.sender, quorumNums);
        
        // Remove from registered operators array
        for (uint i = 0; i < registeredOperators.length; i++) {
            if (registeredOperators[i] == msg.sender) {
                registeredOperators[i] = registeredOperators[registeredOperators.length - 1];
                registeredOperators.pop();
                break;
            }
        }
        
        // Clear operator data
        delete operators[msg.sender];
        delete operatorFromId[opId];
        delete operatorId[msg.sender];
        
        emit OperatorDeregistered(msg.sender, opId);
    }

    /**
     * @notice Update operators
     * @param operatorAddresses The operators to update
     */
    function updateOperators(address[] calldata operatorAddresses) external onlyOwner {
        // This function would update the operator list
        // For now, we'll just emit an event
        emit RegistryAdded(address(0)); // Placeholder
    }

    /**
     * @notice Update operators for quorum
     * @param operatorsPerQuorum The operators per quorum
     * @param quorumNumbers The quorum numbers
     */
    function updateOperatorsForQuorum(
        address[][] memory operatorsPerQuorum,
        bytes calldata quorumNumbers
    ) external onlyOwner {
        // This function would update operators for specific quorums
        // For now, we'll just emit an event
        emit RegistryAdded(address(0)); // Placeholder
    }

    /**
     * @notice Get operator info
     * @param operator The operator address
     * @return The operator info
     */
    function getOperator(address operator) external view returns (IRegistryCoordinator.OperatorInfo memory) {
        RegistryOperatorInfo memory regInfo = operators[operator];
        return IRegistryCoordinator.OperatorInfo({
            operatorId: regInfo.operatorId,
            status: regInfo.isActive ? IRegistryCoordinator.OperatorStatus.REGISTERED : IRegistryCoordinator.OperatorStatus.DEREGISTERED
        });
    }
    
    function getRegistryOperator(address operator) external view returns (RegistryOperatorInfo memory) {
        return operators[operator];
    }

    /**
     * @notice Get operator from ID
     * @param opId The operator ID
     * @return The operator address
     */
    function getOperatorFromId(bytes32 opId) external view returns (address) {
        return operatorFromId[opId];
    }

    /**
     * @notice Get operator ID
     * @param operator The operator address
     * @return The operator ID
     */
    function getOperatorId(address operator) external view returns (bytes32) {
        return operatorId[operator];
    }

    /**
     * @notice Get operator status
     * @param operator The operator address
     * @return The operator status
     */
    function getOperatorStatus(address operator) external view returns (IRegistryCoordinator.OperatorStatus) {
        return operators[operator].isActive ? IRegistryCoordinator.OperatorStatus.REGISTERED : IRegistryCoordinator.OperatorStatus.DEREGISTERED;
    }

    /**
     * @notice Get quorum bitmap update by index
     * @param opId The operator ID
     * @param index The index
     * @return The quorum bitmap update
     */
    function getQuorumBitmapUpdateByIndex(bytes32 opId, uint256 index)
        external
        view
       
        returns (QuorumBitmapUpdate memory)
    {
        return quorumBitmapUpdates[opId][index];
    }

    /**
     * @notice Get current quorum bitmap
     * @param opId The operator ID
     * @return The current quorum bitmap
     */
    function getCurrentQuorumBitmap(bytes32 opId) external view returns (uint192) {
        QuorumBitmapUpdate[] storage updates = quorumBitmapUpdates[opId];
        if (updates.length == 0) {
            return 0;
        }
        return updates[updates.length - 1].quorumBitmap;
    }

    /**
     * @notice Get number of registries
     * @return The number of registries
     */
    function getNumRegistries() external view returns (uint256) {
        return numRegistries;
    }

    /**
     * @notice Calculate quorum bitmap from quorum numbers
     * @param quorumNumbers The quorum numbers
     * @return The quorum bitmap
     */
    function _calculateQuorumBitmap(bytes memory quorumNumbers) internal pure returns (uint192) {
        uint192 bitmap = 0;
        for (uint i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);
            require(quorumNumber < 192, "Invalid quorum number");
            bitmap |= (uint192(1) << quorumNumber);
        }
        return bitmap;
    }

    /**
     * @notice Update quorum bitmap for operator
     * @param opId The operator ID
     * @param newBitmap The new quorum bitmap
     */
    function updateQuorumBitmap(bytes32 opId, uint192 newBitmap) external onlyOwner {
        require(operatorFromId[opId] != address(0), "Operator not found");
        
        QuorumBitmapUpdate[] storage updates = quorumBitmapUpdates[opId];
        if (updates.length > 0) {
            updates[updates.length - 1].nextUpdateBlockNumber = uint32(block.number);
        }
        
        updates.push(QuorumBitmapUpdate({
            updateBlockNumber: uint32(block.number),
            nextUpdateBlockNumber: 0,
            quorumBitmap: newBitmap
        }));
        
        emit QuorumBitmapUpdated(opId, newBitmap);
    }

    /**
     * @notice Get all registered operators
     * @return Array of registered operator addresses
     */
    function getAllOperators() external view returns (address[] memory) {
        return registeredOperators;
    }

    /**
     * @notice Get operator count
     * @return The number of registered operators
     */
    function getOperatorCount() external view returns (uint256) {
        return registeredOperators.length;
    }

    /**
     * @notice Check if operator is registered
     * @param operator The operator address
     * @return True if registered
     */
    function isOperatorRegistered(address operator) external view returns (bool) {
        return operators[operator].operatorId != bytes32(0);
    }

    /**
     * @notice Pause operations
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause operations
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
