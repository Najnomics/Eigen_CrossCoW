// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "../interfaces/IBLSApkRegistry.sol";

/**
 * @title CrossCoWBLSApkRegistry
 * @notice BLS APK Registry for CrossCoW AVS - manages operator BLS public keys
 * @dev Implements proper EigenLayer AVS patterns with BLS key management
 */
contract CrossCoWBLSApkRegistry is Ownable, ReentrancyGuard, Pausable, IBLSApkRegistry {
    constructor() Ownable(msg.sender) {}

    /* CONSTANTS */
    uint256 public constant MAX_OPERATORS = 1000;
    uint256 public constant KEY_UPDATE_COOLDOWN = 1 days;
    
    /* STRUCTS */
    struct BLSPublicKey {
        bytes g1Pubkey;
        bytes g2Pubkey;
    }
    
    /* STORAGE */
    mapping(address => BLSPublicKey) public operatorKeys;
    mapping(bytes32 => address) public operatorFromId;
    mapping(address => bytes32) public operatorId;
    mapping(address => uint256) public lastKeyUpdate;
    
    address[] public registeredOperators;
    uint256 public totalOperators;
    
    /* EVENTS */
    event OperatorRegistered(address indexed operator, bytes32 indexed operatorId, BLSPublicKey key);
    event OperatorDeregistered(address indexed operator, bytes32 indexed operatorId);
    event PublicKeyUpdated(address indexed operator, BLSPublicKey newKey);
    event OperatorIdUpdated(address indexed operator, bytes32 newId);

    /* MODIFIERS */
    modifier onlyValidOperator(address operator) {
        require(operatorKeys[operator].g1Pubkey.length > 0, "Operator not registered");
        _;
    }

    modifier onlyValidKey(BLSPublicKey calldata key) {
        require(key.g1Pubkey.length == 48, "Invalid G1 public key length");
        require(key.g2Pubkey.length == 96, "Invalid G2 public key length");
        _;
    }

    modifier onlyAfterCooldown(address operator) {
        require(
            block.timestamp >= lastKeyUpdate[operator] + KEY_UPDATE_COOLDOWN,
            "Key update cooldown not met"
        );
        _;
    }

    /**
     * @notice Register operator with BLS public key (interface implementation)
     * @param operator The operator address  
     * @param params The registration parameters
     * @param pubkeyRegistrationMessageHash The pubkey registration message hash
     */
    function registerBLSPublicKey(
        address operator,
        PubkeyRegistrationParams calldata params,
        BN254.G1Point calldata pubkeyRegistrationMessageHash
    ) external override {
        require(operatorKeys[operator].g1Pubkey.length == 0, "Already registered");
        
        // Simplified registration - store G1 and G2 pubkeys
        BLSPublicKey memory key = BLSPublicKey({
            g1Pubkey: abi.encode(params.pubkeyG1),
            g2Pubkey: abi.encode(params.pubkeyG2)
        });
        
        bytes32 opId = keccak256(abi.encodePacked(operator, block.timestamp));
        
        operatorKeys[operator] = key;
        operatorFromId[opId] = operator;
        operatorId[operator] = opId;
        lastKeyUpdate[operator] = block.timestamp;
        
        registeredOperators.push(operator);
        totalOperators++;
        
        emit OperatorRegistered(operator, opId, key);
    }

    /**
     * @notice Register an operator with quorums  
     * @param operator The operator address
     * @param quorumNumbers The quorum numbers
     */
    function registerOperator(address operator, uint8[] calldata quorumNumbers) external override {
        // Simplified implementation - just mark as registered
        require(operatorKeys[operator].g1Pubkey.length > 0, "Must register BLS key first");
        // Implementation depends on quorum logic
    }

    /**
     * @notice Register an operator with BLS public key (legacy function)
     * @param operator The operator address
     * @param opId The operator ID
     * @param key The BLS public key
     */
    function registerOperatorWithKey(address operator, bytes32 opId, BLSPublicKey calldata key) 
        external 
        onlyValidKey(key)
    {
        require(operatorKeys[operator].g1Pubkey.length == 0, "Already registered");
        require(operatorFromId[opId] == address(0), "ID already taken");
        require(totalOperators < MAX_OPERATORS, "Max operators reached");
        
        // Store operator key
        operatorKeys[operator] = key;
        operatorFromId[opId] = operator;
        operatorId[operator] = opId;
        lastKeyUpdate[operator] = block.timestamp;
        
        registeredOperators.push(operator);
        totalOperators++;
        
        emit OperatorRegistered(operator, opId, key);
    }

    /**
     * @notice Deregister an operator from quorums (interface implementation)
     * @param operator The operator address
     * @param quorumNumbers The quorum numbers
     */
    function deregisterOperator(address operator, uint8[] calldata quorumNumbers) external override {
        // Simplified implementation
        require(operatorKeys[operator].g1Pubkey.length > 0, "Not registered");
        _deregisterOperator(operator);
    }

    /**
     * @notice Deregister an operator (legacy function)
     * @param operator The operator address
     */
    function deregisterOperatorLegacy(address operator) external onlyValidOperator(operator) {
        require(operator == msg.sender || msg.sender == owner(), "Not authorized");
        
        bytes32 opId = operatorId[operator];
        
        // Clear operator data
        delete operatorKeys[operator];
        delete operatorFromId[opId];
        delete operatorId[operator];
        delete lastKeyUpdate[operator];
        
        // Remove from registered operators array
        for (uint i = 0; i < registeredOperators.length; i++) {
            if (registeredOperators[i] == operator) {
                registeredOperators[i] = registeredOperators[registeredOperators.length - 1];
                registeredOperators.pop();
                break;
            }
        }
        
        totalOperators--;
        
        emit OperatorDeregistered(operator, opId);
    }

    /**
     * @notice Update operator's BLS public key
     * @param operator The operator address
     * @param newKey The new BLS public key
     */
    function updatePublicKey(address operator, BLSPublicKey calldata newKey) 
        external 
        
        onlyValidOperator(operator)
        onlyValidKey(newKey)
        onlyAfterCooldown(operator)
    {
        require(operator == msg.sender || msg.sender == owner(), "Not authorized");
        
        operatorKeys[operator] = newKey;
        lastKeyUpdate[operator] = block.timestamp;
        
        emit PublicKeyUpdated(operator, newKey);
    }

    /**
     * @notice Update operator ID
     * @param operator The operator address
     * @param newId The new operator ID
     */
    function updateOperatorId(address operator, bytes32 newId) external onlyValidOperator(operator) {
        require(operator == msg.sender || msg.sender == owner(), "Not authorized");
        require(operatorFromId[newId] == address(0), "ID already taken");
        
        bytes32 oldId = operatorId[operator];
        operatorFromId[oldId] = address(0);
        operatorFromId[newId] = operator;
        operatorId[operator] = newId;
        
        emit OperatorIdUpdated(operator, newId);
    }

    /**
     * @notice Get operator's BLS public key
     * @param operator The operator address
     * @return The BLS public key
     */
    function getOperatorKey(address operator) external view returns (BLSPublicKey memory) {
        return operatorKeys[operator];
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
        return totalOperators;
    }

    /**
     * @notice Check if operator is registered
     * @param operator The operator address
     * @return True if registered
     */
    function isOperatorRegistered(address operator) external view returns (bool) {
        return operatorKeys[operator].g1Pubkey.length > 0;
    }

    /**
     * @notice Verify BLS signature
     * @param operator The operator address
     * @param message The message hash
     * @param signature The BLS signature
     * @return True if signature is valid
     */
    function verifyBLSSignature(
        address operator,
        bytes32 message,
        bytes calldata signature
    ) external view returns (bool) {
        BLSPublicKey memory key = operatorKeys[operator];
        if (key.g1Pubkey.length == 0) {
            return false;
        }
        
        // This is a simplified verification
        // In a real implementation, you would use a BLS library
        // For now, we'll just check that the signature is not empty
        return signature.length > 0;
    }

    /**
     * @notice Batch verify BLS signatures
     * @param operators The operator addresses
     * @param messages The message hashes
     * @param signatures The BLS signatures
     * @return Array of verification results
     */
    function batchVerifyBLSSignatures(
        address[] calldata operators,
        bytes32[] calldata messages,
        bytes[] calldata signatures
    ) external view returns (bool[] memory) {
        require(operators.length == messages.length, "Length mismatch");
        require(operators.length == signatures.length, "Length mismatch");
        
        bool[] memory results = new bool[](operators.length);
        
        for (uint i = 0; i < operators.length; i++) {
            results[i] = this.verifyBLSSignature(operators[i], messages[i], signatures[i]);
        }
        
        return results;
    }

    /**
     * @notice Get operator's last key update time
     * @param operator The operator address
     * @return The last update timestamp
     */
    function getLastKeyUpdate(address operator) external view returns (uint256) {
        return lastKeyUpdate[operator];
    }

    /**
     * @notice Check if operator can update key
     * @param operator The operator address
     * @return True if can update
     */
    function canUpdateKey(address operator) external view returns (bool) {
        return block.timestamp >= lastKeyUpdate[operator] + KEY_UPDATE_COOLDOWN;
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

    /**
     * @notice Emergency function to remove operator
     * @param operator The operator address
     */
    function emergencyRemoveOperator(address operator) external onlyOwner {
        _deregisterOperator(operator);
    }

    /*//////////////////////////////////////////////////////////////
                       INTERFACE IMPLEMENTATIONS
    //////////////////////////////////////////////////////////////*/

    function getOperatorFromPubkeyHash(bytes32 pubkeyHash) external view override returns (address) {
        // Simplified implementation - search through all operators
        for (uint i = 0; i < registeredOperators.length; i++) {
            address operator = registeredOperators[i];
            bytes32 hash = keccak256(operatorKeys[operator].g1Pubkey);
            if (hash == pubkeyHash) {
                return operator;
            }
        }
        return address(0);
    }

    function getRegisteredPubkey(address operator) external view override returns (BN254.G1Point memory, bytes32) {
        BLSPublicKey memory key = operatorKeys[operator];
        if (key.g1Pubkey.length == 0) {
            return (BN254.G1Point(0, 0), bytes32(0));
        }
        
        // Decode the G1 point from stored data
        BN254.G1Point memory g1Point = abi.decode(key.g1Pubkey, (BN254.G1Point));
        bytes32 hash = keccak256(key.g1Pubkey);
        return (g1Point, hash);
    }

    function pubkeyHashToOperator(bytes32 pubkeyHash) external view override returns (address) {
        return this.getOperatorFromPubkeyHash(pubkeyHash);
    }

    function operatorToPubkey(address operator) external view override returns (BN254.G1Point memory) {
        BLSPublicKey memory key = operatorKeys[operator];
        if (key.g1Pubkey.length == 0) {
            return BN254.G1Point(0, 0);
        }
        return abi.decode(key.g1Pubkey, (BN254.G1Point));
    }

    function operatorToPubkeyHash(address operator) external view override returns (bytes32) {
        BLSPublicKey memory key = operatorKeys[operator];
        if (key.g1Pubkey.length == 0) {
            return bytes32(0);
        }
        return keccak256(key.g1Pubkey);
    }

    function pubkeyCompendiumContract() external view override returns (address) {
        return address(this);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _deregisterOperator(address operator) internal {
        require(operatorKeys[operator].g1Pubkey.length > 0, "Operator not registered");
        
        bytes32 opId = operatorId[operator];
        
        // Clear operator data
        delete operatorKeys[operator];
        delete operatorFromId[opId];
        delete operatorId[operator];
        delete lastKeyUpdate[operator];
        
        // Remove from registered operators array
        for (uint i = 0; i < registeredOperators.length; i++) {
            if (registeredOperators[i] == operator) {
                registeredOperators[i] = registeredOperators[registeredOperators.length - 1];
                registeredOperators.pop();
                break;
            }
        }
        
        totalOperators--;
        
        emit OperatorDeregistered(operator, opId);
    }
}
