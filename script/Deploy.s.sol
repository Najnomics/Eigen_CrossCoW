// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../src/EigenCrossCoWHook.sol";
import "../src/avs/task-managers/CrossCoWTaskManagerSimple.sol";
import "../src/avs/service-managers/CrossCoWServiceManager.sol";
import "../src/avs/registry/CrossCoWRegistryCoordinator.sol";
import "../src/avs/registry/CrossCoWStakeRegistry.sol";
import "../src/avs/registry/CrossCoWBLSApkRegistry.sol";
import "../src/avs/aggregator/CrossCoWAggregator.sol";
import "../src/integration/AcrossIntegration.sol";

/**
 * @title DeployScript
 * @notice Comprehensive deployment script for EigenCrossCoW AVS
 * @dev Deploys all contracts in the correct order with proper initialization
 */
contract DeployScript is Script {
    /* CONTRACTS */
    EigenCrossCoWHook public hook;
    CrossCoWTaskManagerSimple public taskManager;
    CrossCoWServiceManager public serviceManager;
    CrossCoWRegistryCoordinator public registryCoordinator;
    CrossCoWStakeRegistry public stakeRegistry;
    CrossCoWBLSApkRegistry public blsApkRegistry;
    CrossCoWAggregator public aggregator;
    AcrossIntegration public acrossIntegration;
    
    /* ADDRESSES */
    address public owner;
    address public aggregatorAddr;
    address public generator;
    address public acrossHubPool;
    address public acrossRelayer;
    address public acrossSpokePool;
    
    /* CONFIGURATION */
    bool public isTestnet = true;
    string public networkName;
    
    function run() external {
        // Get deployment parameters
        owner = vm.envOr("OWNER", msg.sender);
        aggregatorAddr = vm.envOr("AGGREGATOR", address(0x1234567890123456789012345678901234567890));
        generator = vm.envOr("GENERATOR", address(0x2345678901234567890123456789012345678901));
        acrossHubPool = vm.envOr("ACROSS_HUB_POOL", address(0x3456789012345678901234567890123456789012));
        acrossRelayer = vm.envOr("ACROSS_RELAYER", address(0x4567890123456789012345678901234567890123));
        acrossSpokePool = vm.envOr("ACROSS_SPOKE_POOL", address(0x5678901234567890123456789012345678901234));
        
        networkName = vm.envOr("NETWORK", string("localhost"));
        isTestnet = !vm.envOr("MAINNET", false);
        
        console.log("Deploying EigenCrossCoW AVS on", networkName);
        console.log("Owner:", owner);
        console.log("Aggregator:", aggregatorAddr);
        console.log("Generator:", generator);
        console.log("Is Testnet:", isTestnet);
        
        // Deploy contracts
        vm.startBroadcast(owner);
        
        _deployRegistryContracts();
        _deployServiceManager();
        _deployAggregator();
        _deployTaskManager();
        _deployAcrossIntegration();
        _deployMainHook();
        _configureContracts();
        
        vm.stopBroadcast();
        
        // Verify deployment
        _verifyDeployment();
        
        // Print deployment summary
        _printDeploymentSummary();
    }
    
    function _deployRegistryContracts() internal {
        console.log("Deploying registry contracts...");
        
        // Deploy stake registry (ETH staking)
        stakeRegistry = new CrossCoWStakeRegistry();
        console.log("StakeRegistry deployed at:", address(stakeRegistry));
        
        // Deploy BLS APK registry
        blsApkRegistry = new CrossCoWBLSApkRegistry();
        console.log("BLSApkRegistry deployed at:", address(blsApkRegistry));
        
        // Deploy registry coordinator
        registryCoordinator = new CrossCoWRegistryCoordinator(
            address(stakeRegistry),
            address(blsApkRegistry)
        );
        console.log("RegistryCoordinator deployed at:", address(registryCoordinator));
    }
    
    function _deployServiceManager() internal {
        console.log("Deploying service manager...");
        
        serviceManager = new CrossCoWServiceManager(
            address(registryCoordinator),
            address(stakeRegistry),
            address(blsApkRegistry)
        );
        console.log("ServiceManager deployed at:", address(serviceManager));
    }
    
    function _deployAggregator() internal {
        console.log("Deploying aggregator...");
        
        aggregator = new CrossCoWAggregator();
        console.log("Aggregator deployed at:", address(aggregator));
    }
    
    function _deployTaskManager() internal {
        console.log("Deploying task manager...");
        
        taskManager = new CrossCoWTaskManagerSimple(
            owner,
            address(aggregator),
            generator,
            payable(address(0)) // Will be set after across integration deployment
        );
        console.log("TaskManager deployed at:", address(taskManager));
    }
    
    function _deployAcrossIntegration() internal {
        console.log("Deploying across integration...");
        
        acrossIntegration = new AcrossIntegration(IAcrossHubPool(acrossHubPool));
        console.log("AcrossIntegration deployed at:", address(acrossIntegration));
    }
    
    function _deployMainHook() internal {
        console.log("Deploying main hook...");
        
        // Mock pool manager for now
        address mockPoolManager = address(0x1234567890123456789012345678901234567890);
        
        hook = new EigenCrossCoWHook(
            IPoolManager(mockPoolManager),
            ICrossCoWServiceManager(serviceManager),
            IAcrossHubPool(acrossHubPool)
        );
        console.log("EigenCrossCoWHook deployed at:", address(hook));
    }
    
    function _configureContracts() internal {
        console.log("Configuring contracts...");
        
        // Set aggregator in task manager
        taskManager.setAggregator(address(aggregator));
        
        // Transfer ownership if needed
        if (owner != msg.sender) {
            hook.transferOwnership(owner);
            taskManager.transferOwnership(owner);
            serviceManager.transferOwnership(owner);
            registryCoordinator.transferOwnership(owner);
            stakeRegistry.transferOwnership(owner);
            blsApkRegistry.transferOwnership(owner);
            aggregator.transferOwnership(owner);
        }
        
        console.log("Contracts configured successfully");
    }
    
    function _verifyDeployment() internal view {
        console.log("Verifying deployment...");
        
        // Check that all contracts are deployed
        require(address(hook) != address(0), "Hook not deployed");
        require(address(taskManager) != address(0), "TaskManager not deployed");
        require(address(serviceManager) != address(0), "ServiceManager not deployed");
        require(address(registryCoordinator) != address(0), "RegistryCoordinator not deployed");
        require(address(stakeRegistry) != address(0), "StakeRegistry not deployed");
        require(address(blsApkRegistry) != address(0), "BLSApkRegistry not deployed");
        require(address(aggregator) != address(0), "Aggregator not deployed");
        require(address(acrossIntegration) != address(0), "AcrossIntegration not deployed");
        
        // Check that contracts are properly connected
        require(address(hook.serviceManager()) == address(serviceManager), "Hook not connected to ServiceManager");
        
        console.log("Deployment verification successful");
    }
    
    function _printDeploymentSummary() internal view {
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Network:", networkName);
        console.log("Owner:", owner);
        console.log("Is Testnet:", isTestnet);
        console.log("\nContract Addresses:");
        console.log("EigenCrossCoWHook:", address(hook));
        console.log("CrossCoWTaskManagerSimple:", address(taskManager));
        console.log("CrossCoWServiceManager:", address(serviceManager));
        console.log("CrossCoWRegistryCoordinator:", address(registryCoordinator));
        console.log("CrossCoWStakeRegistry:", address(stakeRegistry));
        console.log("CrossCoWBLSApkRegistry:", address(blsApkRegistry));
        console.log("CrossCoWAggregator:", address(aggregator));
        console.log("AcrossIntegration:", address(acrossIntegration));
        console.log("\nNext Steps:");
        console.log("1. Register operators with the ServiceManager");
        console.log("2. Configure Across Protocol parameters");
        console.log("3. Set up monitoring and alerting");
        console.log("4. Deploy to mainnet when ready");
        console.log("========================");
    }
    
    // Helper function to save addresses to file
    function saveAddresses() external {
        string memory addresses = string(abi.encodePacked(
            "EigenCrossCoWHook=", vm.toString(address(hook)), "\n",
            "CrossCoWTaskManagerSimple=", vm.toString(address(taskManager)), "\n",
            "CrossCoWServiceManager=", vm.toString(address(serviceManager)), "\n",
            "CrossCoWRegistryCoordinator=", vm.toString(address(registryCoordinator)), "\n",
            "CrossCoWStakeRegistry=", vm.toString(address(stakeRegistry)), "\n",
            "CrossCoWBLSApkRegistry=", vm.toString(address(blsApkRegistry)), "\n",
            "CrossCoWAggregator=", vm.toString(address(aggregator)), "\n",
            "AcrossIntegration=", vm.toString(address(acrossIntegration)), "\n"
        ));
        
        vm.writeFile("deployment-addresses.txt", addresses);
        console.log("Addresses saved to deployment-addresses.txt");
    }
}
