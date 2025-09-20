// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "./Deploy.s.sol";

/**
 * @title DeployTestnetScript
 * @notice Deployment script specifically for testnet environments (Sepolia, Holesky, etc.)
 * @dev Extends the main DeployScript with testnet-specific configurations
 */
contract DeployTestnetScript is DeployScript {
    function run() external override {
        console.log("=== DEPLOYING TO TESTNET ===");
        console.log("Network: Testnet");
        console.log("Environment: Development");
        console.log("=============================");
        
        // Set testnet-specific environment variables
        vm.setEnv("NETWORK", "testnet");
        vm.setEnv("MAINNET", "false");
        vm.setEnv("ACROSS_HUB_POOL", "0x0000000000000000000000000000000000000000");
        vm.setEnv("AGGREGATOR", "0x1234567890123456789012345678901234567890");
        vm.setEnv("GENERATOR", "0x2345678901234567890123456789012345678901");
        
        // Deploy contracts using parent logic
        _deployContracts();
        
        // Testnet-specific post-deployment steps
        _setupTestnetEnvironment();
    }
    
    function _setupTestnetEnvironment() internal {
        console.log("Setting up testnet environment...");
        
        // Add test operators
        _addTestOperators();
        
        // Configure test parameters
        _configureTestParameters();
        
        console.log("Testnet environment setup complete");
    }
    
    function _addTestOperators() internal {
        // Add mock operators for testing
        address[] memory testOperators = new address[](3);
        testOperators[0] = 0x1111111111111111111111111111111111111111;
        testOperators[1] = 0x2222222222222222222222222222222222222222;
        testOperators[2] = 0x3333333333333333333333333333333333333333;
        
        for (uint i = 0; i < testOperators.length; i++) {
            console.log("Adding test operator:", testOperators[i]);
            // Note: In real deployment, you would call the actual registration functions
        }
    }
    
    function _configureTestParameters() internal {
        console.log("Configuring test parameters...");
        
        // Set lower fees for testnet
        hook.setFee(100); // 1% fee for testnet
        
        // Set lower minimum deadlines for testing
        hook.setMinDeadline(300); // 5 minutes for testnet
        
        console.log("Test parameters configured");
    }
}
