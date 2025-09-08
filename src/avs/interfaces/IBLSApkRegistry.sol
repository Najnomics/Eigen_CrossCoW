// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IBLSApkRegistry {
    struct ApkUpdate {
        bytes24 apkHash;
        uint32 updateBlockNumber;
        uint32 nextUpdateBlockNumber;
    }

    struct PubkeyRegistrationParams {
        BN254.G1Point pubkeyRegistrationSignature;
        BN254.G1Point pubkeyG1;
        BN254.G2Point pubkeyG2;
    }

    function registerBLSPublicKey(
        address operator,
        PubkeyRegistrationParams calldata params,
        BN254.G1Point calldata pubkeyRegistrationMessageHash
    ) external;

    function registerOperator(
        address operator,
        bytes calldata quorumNumbers
    ) external;

    function deregisterOperator(
        address operator,
        bytes calldata quorumNumbers
    ) external;

    function getApk(uint8 quorumNumber) external view returns (BN254.G1Point memory);

    function getApkHash(uint8 quorumNumber) external view returns (bytes32);

    function getApkUpdateAtIndex(uint8 quorumNumber, uint256 index)
        external
        view
        returns (ApkUpdate memory);

    function getOperatorFromPubkeyHash(bytes32 pubkeyHash) external view returns (address);

    function getOperatorId(address operator) external view returns (bytes32);

    function getRegisteredPubkey(address operator) external view returns (BN254.G1Point memory, bytes32);

    event NewPubkeyRegistration(address indexed operator, BN254.G1Point pubkeyG1, BN254.G2Point pubkeyG2);
}

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