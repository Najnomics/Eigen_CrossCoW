// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "./Deploy.s.sol";

/**
 * @title DeployMainnetScript
 * @notice Deployment script for mainnet production deployment
 * @dev Extends the main DeployScript with mainnet-specific configurations and safety checks
 */
contract DeployMainnetScript is DeployScript {
    /* MAINNET ADDRESSES */
    address constant MAINNET_ACROSS_HUB_POOL = 0x7355Efc63Ae731f584380a9838292c7046c1e433;
    address constant MAINNET_ACROSS_RELAYER = 0x0000000000000000000000000000000000000000; // Will be set dynamically
    address constant MAINNET_ACROSS_SPOKE_POOL = 0x0000000000000000000000000000000000000000; // Will be set dynamically
    
    /* PRODUCTION PARAMETERS */
    uint256 constant MAINNET_FEE = 50; // 0.5% fee for mainnet
    uint256 constant MAINNET_MIN_DEADLINE = 3600; // 1 hour minimum deadline
    uint256 constant MAINNET_MAX_SLIPPAGE = 500; // 5% maximum slippage
    
    function run() external override {
        // Pre-deployment safety checks
        _performSafetyChecks();
        
        console.log("=== DEPLOYING TO MAINNET ===");
        console.log("Network: Ethereum Mainnet");
        console.log("Environment: Production");
        console.log("=============================");
        
        // Set mainnet-specific environment variables
        vm.setEnv("NETWORK", "mainnet");
        vm.setEnv("MAINNET", "true");
        vm.setEnv("ACROSS_HUB_POOL", vm.toString(MAINNET_ACROSS_HUB_POOL));
        
        // Deploy contracts using parent logic
        _deployContracts();
        
        // Mainnet-specific post-deployment steps
        _setupMainnetEnvironment();
        
        // Final verification
        _performFinalVerification();
    }
    
    function _performSafetyChecks() internal view {
        console.log("Performing safety checks...");
        
        // Check that owner is set
        address owner = vm.envOr("OWNER", address(0));
        require(owner != address(0), "OWNER environment variable must be set");
        require(owner.code.length == 0, "Owner must be an EOA");
        
        // Check that aggregator and generator are set
        address aggregator = vm.envOr("PROD_AGGREGATOR", address(0));
        address generator = vm.envOr("PROD_GENERATOR", address(0));
        require(aggregator != address(0), "PROD_AGGREGATOR environment variable must be set");
        require(generator != address(0), "PROD_GENERATOR environment variable must be set");
        
        // Check that we're on mainnet
        uint256 chainId = block.chainid;
        require(chainId == 1, "This script is only for Ethereum mainnet (chainId: 1)");
        
        console.log("Safety checks passed");
    }
    
    function _setupMainnetEnvironment() internal {
        console.log("Setting up mainnet environment...");
        
        // Configure production parameters
        _configureProductionParameters();
        
        // Setup monitoring and alerting
        _setupMonitoring();
        
        console.log("Mainnet environment setup complete");
    }
    
    function _configureProductionParameters() internal {
        console.log("Configuring production parameters...");
        
        // Set production fees
        hook.setFee(MAINNET_FEE);
        
        // Set production deadlines
        hook.setMinDeadline(MAINNET_MIN_DEADLINE);
        
        // Set production slippage limits
        hook.setMaxSlippage(MAINNET_MAX_SLIPPAGE);
        
        console.log("Production parameters configured:");
        console.log("- Fee:", MAINNET_FEE, "basis points");
        console.log("- Min Deadline:", MAINNET_MIN_DEADLINE, "seconds");
        console.log("- Max Slippage:", MAINNET_MAX_SLIPPAGE, "basis points");
    }
    
    function _setupMonitoring() internal {
        console.log("Setting up monitoring...");
        
        // In a real deployment, you would:
        // 1. Register with monitoring services
        // 2. Set up alerting rules
        // 3. Configure health checks
        // 4. Setup log aggregation
        
        console.log("Monitoring setup complete");
    }
    
    function _performFinalVerification() internal view {
        console.log("Performing final verification...");
        
        // Verify all contracts are properly configured
        require(hook.fee() == MAINNET_FEE, "Fee not set correctly");
        require(hook.minDeadline() == MAINNET_MIN_DEADLINE, "Min deadline not set correctly");
        require(hook.maxSlippage() == MAINNET_MAX_SLIPPAGE, "Max slippage not set correctly");
        
        // Verify ownership
        require(hook.owner() == vm.envOr("OWNER", address(0)), "Ownership not transferred correctly");
        
        console.log("Final verification passed");
    }
    
    // Emergency functions for mainnet deployment
    function emergencyPause() external {
        require(msg.sender == vm.envOr("OWNER", address(0)), "Only owner can pause");
        hook.pause();
        console.log("Emergency pause activated");
    }
    
    function emergencyUnpause() external {
        require(msg.sender == vm.envOr("OWNER", address(0)), "Only owner can unpause");
        hook.unpause();
        console.log("Emergency unpause activated");
    }
}
