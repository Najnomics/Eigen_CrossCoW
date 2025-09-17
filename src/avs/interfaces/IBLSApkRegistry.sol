// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IBLSApkRegistry
 * @notice Interface for BLS public key registry
 */
interface IBLSApkRegistry {
    struct PubkeyRegistrationParams {
        BN254.G1Point pubkeyRegistrationSignature;
        BN254.G1Point pubkeyG1;
        BN254.G2Point pubkeyG2;
    }

    // Events
    event NewPubkeyRegistration(address indexed operator, BN254.G1Point pubkeyG1, BN254.G2Point pubkeyG2);
    event OperatorAddedToQuorums(address indexed operator, uint8[] quorumNumbers);
    event OperatorRemovedFromQuorums(address indexed operator, uint8[] quorumNumbers);

    // Functions
    function registerBLSPublicKey(
        address operator,
        PubkeyRegistrationParams calldata params,
        BN254.G1Point calldata pubkeyRegistrationMessageHash
    ) external;

    function registerOperator(address operator, uint8[] calldata quorumNumbers) external;

    function deregisterOperator(address operator, uint8[] calldata quorumNumbers) external;

    function getOperatorFromPubkeyHash(bytes32 pubkeyHash) external view returns (address);

    function getOperatorId(address operator) external view returns (bytes32);

    function getRegisteredPubkey(address operator) external view returns (BN254.G1Point memory, bytes32);

    function pubkeyHashToOperator(bytes32 pubkeyHash) external view returns (address);

    function operatorToPubkey(address operator) external view returns (BN254.G1Point memory);

    function operatorToPubkeyHash(address operator) external view returns (bytes32);

    function pubkeyCompendiumContract() external view returns (address);
}

// BN254 library interface
library BN254 {
    struct G1Point {
        uint256 X;
        uint256 Y;
    }

    struct G2Point {
        uint256[2] X;
        uint256[2] Y;
    }
}