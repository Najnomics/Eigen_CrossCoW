// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IAllocationManager} from "@eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IKeyRegistrar} from "@eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";

import {TaskAVSRegistrar} from "@project/l1-contracts/TaskAVSRegistrar.sol";
import {CrossCoWServiceManager} from "@project/l1-contracts/CrossCoWServiceManager.sol";

contract DeployCrossCoWL1Contracts is Script {
    using stdJson for string;

    struct Context {
        address avs;
        uint256 avsPrivateKey;
        uint256 deployerPrivateKey;
        IAllocationManager allocationManager;
        IKeyRegistrar keyRegistrar;
        TaskAVSRegistrar taskAVSRegistrar;
    }

    struct Output {
        string name;
        address contractAddress;
    }

    function run(string memory environment, string memory _context) public {
        // Read the context
        Context memory context = _readContext(environment, _context);

        vm.startBroadcast(context.deployerPrivateKey);
        console.log("Deployer address:", vm.addr(context.deployerPrivateKey));

        // Deploy CrossCoW Service Manager
        CrossCoWServiceManager crossCoWServiceManager = new CrossCoWServiceManager(
            context.allocationManager,
            context.keyRegistrar,
            address(context.taskAVSRegistrar)
        );
        console.log("CrossCoWServiceManager deployed to:", address(crossCoWServiceManager));

        vm.stopBroadcast();

        vm.startBroadcast(context.avsPrivateKey);
        console.log("AVS address:", context.avs);

        // TODO: Implement any additional AVS setup for CrossCoW
        // - Configure CrossCoW parameters
        // - Set up reward mechanisms
        // - Initialize operator requirements

        vm.stopBroadcast();

        // Output the deployed contracts
        Output[] memory outputs = new Output[](1);
        outputs[0] = Output("CrossCoWServiceManager", address(crossCoWServiceManager));

        _writeOutput(environment, outputs);
    }

    function _readContext(string memory environment, string memory _context) internal view returns (Context memory) {
        string memory contextJson = vm.readFile(string.concat(".hourglass/context/", environment, ".json"));

        Context memory context;
        context.avs = contextJson.readAddress(".avs.address");
        context.avsPrivateKey = contextJson.readUint(".avs.privateKey");
        context.deployerPrivateKey = contextJson.readUint(".deployer.privateKey");
        context.allocationManager = IAllocationManager(contextJson.readAddress(".contracts.allocationManager"));
        context.keyRegistrar = IKeyRegistrar(contextJson.readAddress(".contracts.keyRegistrar"));
        context.taskAVSRegistrar = TaskAVSRegistrar(contextJson.readAddress(".contracts.taskAVSRegistrar"));

        return context;
    }

    function _writeOutput(string memory environment, Output[] memory outputs) internal {
        string memory outputDir = string.concat(".hourglass/context/", environment, "/");
        string memory outputFile = string.concat(outputDir, "l1-contracts.json");

        string memory json = "";
        for (uint256 i = 0; i < outputs.length; i++) {
            json = vm.serializeAddress(json, outputs[i].name, outputs[i].contractAddress);
        }

        vm.writeFile(outputFile, json);
        console.log("L1 contract addresses written to:", outputFile);
    }
}