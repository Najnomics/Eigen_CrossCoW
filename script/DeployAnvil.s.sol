// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "./Deploy.s.sol";

/**
 * @title DeployAnvilScript
 * @notice Deployment script for local Anvil development environment
 * @dev Extends the main DeployScript with Anvil-specific configurations and mock contracts
 */
contract DeployAnvilScript is DeployScript {
    /* ANVIL CONFIGURATION */
    address constant ANVIL_DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address constant ANVIL_AGGREGATOR = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address constant ANVIL_GENERATOR = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    
    /* MOCK CONTRACTS */
    address public mockPoolManager;
    address public mockAcrossHubPool;
    
    function run() external override {
        console.log("=== DEPLOYING TO ANVIL ===");
        console.log("Network: Anvil Local");
        console.log("Environment: Development");
        console.log("==========================");
        
        // Deploy mock contracts first
        _deployMockContracts();
        
        // Update environment with mock addresses
        vm.setEnv("ACROSS_HUB_POOL", vm.toString(mockAcrossHubPool));
        vm.setEnv("NETWORK", "anvil");
        vm.setEnv("MAINNET", "false");
        vm.setEnv("OWNER", vm.toString(ANVIL_DEPLOYER));
        vm.setEnv("AGGREGATOR", vm.toString(ANVIL_AGGREGATOR));
        vm.setEnv("GENERATOR", vm.toString(ANVIL_GENERATOR));
        
        // Deploy contracts using parent logic
        _deployContracts();
        
        // Anvil-specific post-deployment setup
        _setupAnvilEnvironment();
        
        // Print useful information for development
        _printDevelopmentInfo();
    }
    
    function _deployMockContracts() internal {
        console.log("Deploying mock contracts for Anvil...");
        
        vm.startBroadcast(ANVIL_DEPLOYER);
        
        // Deploy mock PoolManager
        MockPoolManager mockPM = new MockPoolManager();
        mockPoolManager = address(mockPM);
        console.log("MockPoolManager deployed at:", mockPoolManager);
        
        // Deploy mock Across Hub Pool
        MockAcrossHubPool mockAHP = new MockAcrossHubPool();
        mockAcrossHubPool = address(mockAHP);
        console.log("MockAcrossHubPool deployed at:", mockAcrossHubPool);
        
        vm.stopBroadcast();
        
        console.log("Mock contracts deployed successfully");
    }
    
    function _setupAnvilEnvironment() internal {
        console.log("Setting up Anvil environment...");
        
        // Configure development parameters
        _configureDevelopmentParameters();
        
        // Setup test accounts with ETH
        _setupTestAccounts();
        
        // Register test operators
        _registerTestOperators();
        
        console.log("Anvil environment setup complete");
    }
    
    function _configureDevelopmentParameters() internal {
        console.log("Configuring development parameters...");
        
        // Set low fees for testing
        hook.setFee(10); // 0.1% fee for development
        
        // Set short deadlines for testing
        hook.setMinDeadline(60); // 1 minute for development
        
        // Set high slippage for testing
        hook.setMaxSlippage(1000); // 10% for development
        
        console.log("Development parameters configured");
    }
    
    function _setupTestAccounts() internal {
        console.log("Setting up test accounts...");
        
        // Fund test accounts with ETH
        address[] memory testAccounts = new address[](5);
        testAccounts[0] = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // Account 1
        testAccounts[1] = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; // Account 2
        testAccounts[2] = 0x90F79bf6EB2c4f870365E785982E1f101E93b906; // Account 3
        testAccounts[3] = 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65; // Account 4
        testAccounts[4] = 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc; // Account 5
        
        for (uint i = 0; i < testAccounts.length; i++) {
            vm.deal(testAccounts[i], 1000 ether);
            console.log("Funded account with 1000 ETH");
        }
    }
    
    function _registerTestOperators() internal {
        console.log("Registering test operators...");
        
        // Register operators for testing
        address[] memory operators = new address[](3);
        operators[0] = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        operators[1] = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
        operators[2] = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;
        
        for (uint i = 0; i < operators.length; i++) {
            console.log("Registering operator:", operators[i]);
            // Note: In real deployment, you would call the actual registration functions
            // with proper BLS keys and stakes
        }
    }
    
    function _printDevelopmentInfo() internal view {
        console.log("\n=== ANVIL DEVELOPMENT INFO ===");
        console.log("Deployer Account:", ANVIL_DEPLOYER);
        console.log("Aggregator Account:", ANVIL_AGGREGATOR);
        console.log("Generator Account:", ANVIL_GENERATOR);
        console.log("\nContract Addresses:");
        console.log("EigenCrossCoWHook:", address(hook));
        console.log("CrossCoWServiceManager:", address(serviceManager));
        console.log("CrossCoWAggregator:", address(aggregator));
        console.log("CrossCoWTaskManager:", address(taskManager));
        console.log("\nMock Contracts:");
        console.log("MockPoolManager:", mockPoolManager);
        console.log("MockAcrossHubPool:", mockAcrossHubPool);
        console.log("\nTest Commands:");
        console.log("forge test --match-contract EigenCrossCoWHookTest");
        console.log("forge test --match-contract CrossCoWAggregatorComprehensiveTest");
        console.log("forge test --match-contract CrossCoWServiceManagerComprehensiveTest");
        console.log("\nUseful Anvil Commands:");
        console.log("anvil --fork-url $MAINNET_RPC_URL");
        console.log("cast send --rpc-url anvil --private-key $PRIVATE_KEY");
        console.log("========================");
    }
}

// Mock contracts for Anvil testing
contract MockPoolManager {
    // Mock implementation for testing
    function getSwapFee() external pure returns (uint24) {
        return 3000; // 0.3% fee
    }
    
    function getLiquidity() external pure returns (uint128) {
        return 1000000 ether; // Mock liquidity
    }
}

contract MockAcrossHubPool {
    // Mock implementation for testing
    function deposit(
        address,
        address,
        uint256,
        uint256,
        uint256,
        uint256,
        bytes calldata
    ) external payable {
        // Mock deposit function
    }
    
    function getCurrentTime() external view returns (uint256) {
        return block.timestamp;
    }
}
