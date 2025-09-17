// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {CrossCoWTaskHook} from "@project/l2-contracts/CrossCoWTaskHook.sol";

contract DeployCrossCoWL2Contracts is Script {
    using stdJson for string;

    struct Context {
        address avs;
        uint256 avsPrivateKey;
        uint256 deployerPrivateKey;
        address crossCoWHook;  // Address of the main CrossCoW Hook (deployed separately)
        address serviceManager;  // Address of the L1 service manager
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

        // Deploy CrossCoW Task Hook (connector to main hook)
        CrossCoWTaskHook taskHook = new CrossCoWTaskHook(
            context.crossCoWHook,
            context.serviceManager
        );
        console.log("CrossCoWTaskHook deployed to:", address(taskHook));
        console.log("Connected to main CrossCoW Hook at:", context.crossCoWHook);
        console.log("Connected to service manager at:", context.serviceManager);

        vm.stopBroadcast();

        vm.startBroadcast(context.avsPrivateKey);
        console.log("AVS address:", context.avs);

        // TODO: Implement any additional L2 setup for task hook
        // - Configure task fees
        // - Set up task type validations
        // - Connect with main CrossCoW Hook

        vm.stopBroadcast();

        // Output the deployed contracts
        Output[] memory outputs = new Output[](1);
        outputs[0] = Output("CrossCoWTaskHook", address(taskHook));

        _writeOutput(environment, outputs);
    }

    function _readContext(string memory environment, string memory _context) internal view returns (Context memory) {
        string memory contextJson = vm.readFile(string.concat(".hourglass/context/", environment, ".json"));

        Context memory context;
        context.avs = contextJson.readAddress(".avs.address");
        context.avsPrivateKey = contextJson.readUint(".avs.privateKey");
        context.deployerPrivateKey = contextJson.readUint(".deployer.privateKey");
        
        // Read L2-specific configuration for connector
        context.crossCoWHook = contextJson.readAddress(".l2.crossCoWHook");  // Main hook address
        context.serviceManager = contextJson.readAddress(".l1.serviceManager");  // L1 service manager

        return context;
    }

    function _writeOutput(string memory environment, Output[] memory outputs) internal {
        string memory outputDir = string.concat(".hourglass/context/", environment, "/");
        string memory outputFile = string.concat(outputDir, "l2-contracts.json");

        string memory json = "";
        for (uint256 i = 0; i < outputs.length; i++) {
            json = vm.serializeAddress(json, outputs[i].name, outputs[i].contractAddress);
        }

        vm.writeFile(outputFile, json);
        console.log("L2 contract addresses written to:", outputFile);
    }
}