// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IAVSDirectory {
    struct OperatorAVSRegistrationStatus {
        address operator;
        address avs;
        uint32 status;
    }

    function registerOperatorToAVS(
        address operator,
        bytes calldata operatorSignature
    ) external;

    function deregisterOperatorFromAVS(address operator) external;

    function updateAVSMetadataURI(string calldata metadataURI) external;

    function isOperatorRegistered(address operator, address avs) external view returns (bool);
    
    function getOperatorRestakedStrategies(address operator) external view returns (address[] memory);

    event OperatorAVSRegistrationStatusUpdated(address indexed operator, address indexed avs, uint32 status);
    event AVSMetadataURIUpdated(address indexed avs, string metadataURI);
}