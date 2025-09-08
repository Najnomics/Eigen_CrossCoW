// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../src/hooks/EigenCrossCoWHook.sol";
import "../src/avs/CrossCoWServiceManager.sol";
import "../src/integration/AcrossIntegration.sol";

contract Deploy is Script {
    
    // Network configurations
    struct NetworkConfig {
        address poolManager;
        address avsDirectory;
        address registryCoordinator;
        address stakeRegistry;
        address blsApkRegistry;
        address acrossHubPool;
        bool isTestnet;
    }
    
    mapping(uint256 => NetworkConfig) public networkConfigs;
    
    // Deployment tracking
    address public deployedServiceManager;
    address public deployedAcrossIntegration;
    address public deployedHook;
    
    function setUp() public {
        _initializeNetworkConfigs();
    }
    
    function run() external {
        uint256 chainId = block.chainid;
        NetworkConfig memory config = networkConfigs[chainId];
        
        require(config.poolManager != address(0), "Unsupported network");
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying on chain:", chainId);
        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy CrossCoW Service Manager
        console.log("\n=== Deploying CrossCoW Service Manager ===");
        deployedServiceManager = _deployServiceManager(config);
        
        // 2. Deploy Across Integration
        console.log("\n=== Deploying Across Integration ===");
        deployedAcrossIntegration = _deployAcrossIntegration(config);
        
        // 3. Deploy EigenCrossCoW Hook
        console.log("\n=== Deploying EigenCrossCoW Hook ===");
        deployedHook = _deployHook(config);
        
        // 4. Configure contracts
        console.log("\n=== Configuring Contracts ===");
        _configureContracts(config);
        
        vm.stopBroadcast();
        
        // 5. Verify contracts
        if (!config.isTestnet) {
            console.log("\n=== Contract Verification ===");
            _logVerificationCommands(chainId);
        }
        
        console.log("\n=== Deployment Summary ===");
        _logDeploymentSummary();
    }
    
    function _deployServiceManager(NetworkConfig memory config) internal returns (address) {
        CrossCoWServiceManager serviceManager = new CrossCoWServiceManager(
            IAVSDirectory(config.avsDirectory),
            IRegistryCoordinator(config.registryCoordinator),
            IStakeRegistry(config.stakeRegistry),
            IBLSApkRegistry(config.blsApkRegistry)
        );
        
        console.log("CrossCoWServiceManager deployed at:", address(serviceManager));
        return address(serviceManager);
    }
    
    function _deployAcrossIntegration(NetworkConfig memory config) internal returns (address) {
        AcrossIntegration acrossIntegration = new AcrossIntegration(
            IAcrossHubPool(config.acrossHubPool)
        );
        
        console.log("AcrossIntegration deployed at:", address(acrossIntegration));
        return address(acrossIntegration);
    }
    
    function _deployHook(NetworkConfig memory config) internal returns (address) {
        EigenCrossCoWHook hook = new EigenCrossCoWHook(
            IPoolManager(config.poolManager),
            ICrossCoWServiceManager(deployedServiceManager),
            IAcrossHubPool(config.acrossHubPool)
        );
        
        console.log("EigenCrossCoWHook deployed at:", address(hook));
        return address(hook);
    }
    
    function _configureContracts(NetworkConfig memory config) internal {
        CrossCoWServiceManager serviceManager = CrossCoWServiceManager(payable(deployedServiceManager));
        AcrossIntegration acrossIntegration = AcrossIntegration(deployedAcrossIntegration);
        EigenCrossCoWHook hook = EigenCrossCoWHook(deployedHook);
        
        // Configure service manager
        serviceManager.authorizeHook(deployedHook, true);
        console.log("Hook authorized in service manager");
        
        // Configure Across integration
        acrossIntegration.authorizeCaller(deployedServiceManager, true);
        acrossIntegration.authorizeCaller(deployedHook, true);
        console.log("Callers authorized in Across integration");
        
        // Configure supported chains
        if (block.chainid == 1) { // Mainnet
            _configureMainnetChains(hook, acrossIntegration);
        } else { // Testnet
            _configureTestnetChains(hook, acrossIntegration);
        }
        
        // Fund service manager with initial rewards
        if (msg.sender.balance > 1 ether) {
            serviceManager.fundRewardPool{value: 0.5 ether}();
            console.log("Service manager funded with 0.5 ETH");
        }
        
        // Fund hook with matching rewards
        if (msg.sender.balance > 0.5 ether) {
            payable(deployedHook).transfer(0.1 ether);
            console.log("Hook funded with 0.1 ETH for matching rewards");
        }
    }
    
    function _configureMainnetChains(EigenCrossCoWHook hook, AcrossIntegration acrossIntegration) internal {
        // Configure supported chains
        hook.setSupportedChain(10, true);    // Optimism
        hook.setSupportedChain(42161, true); // Arbitrum
        hook.setSupportedChain(8453, true);  // Base
        hook.setSupportedChain(137, true);   // Polygon
        
        // Configure Across integration chains
        acrossIntegration.configureChain(10, 0x6f26Bf09B1C792e3228e5467807a900A503c0281, true, 500); // Optimism
        acrossIntegration.configureChain(42161, 0xe35e9842fceaCA96570B734083f4a58e8F7C5f2A, true, 500); // Arbitrum
        acrossIntegration.configureChain(8453, 0x09aea4b2242abC8bb4BB78D537A67a245A7bEC64, true, 500); // Base
        acrossIntegration.configureChain(137, 0x9295ee1d8C5b022Be115A2AD3c30C72E34e7F096, true, 600); // Polygon
        
        console.log("Mainnet chains configured");
        
        // Configure token mappings (USDC example)
        _configureUSDCMappings(hook);
    }
    
    function _configureTestnetChains(EigenCrossCoWHook hook, AcrossIntegration acrossIntegration) internal {
        // Configure testnet chains
        hook.setSupportedChain(11155111, true); // Sepolia
        hook.setSupportedChain(84532, true);    // Base Sepolia
        
        // Configure testnet Across integration
        acrossIntegration.configureChain(11155111, address(0), true, 500); // Mock address for testnet
        acrossIntegration.configureChain(84532, address(0), true, 500);    // Mock address for testnet
        
        console.log("Testnet chains configured");
    }
    
    function _configureUSDCMappings(EigenCrossCoWHook hook) internal {
        address USDC_MAINNET = 0xA0b86a33e6441C4c27D3F50c9d6D14bDf12F4e6e;
        address USDC_OPTIMISM = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
        address USDC_ARBITRUM = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
        address USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        address USDC_POLYGON = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
        
        // Mainnet -> L2s
        hook.setTokenMapping(Currency.wrap(USDC_MAINNET), 10, Currency.wrap(USDC_OPTIMISM));
        hook.setTokenMapping(Currency.wrap(USDC_MAINNET), 42161, Currency.wrap(USDC_ARBITRUM));
        hook.setTokenMapping(Currency.wrap(USDC_MAINNET), 8453, Currency.wrap(USDC_BASE));
        hook.setTokenMapping(Currency.wrap(USDC_MAINNET), 137, Currency.wrap(USDC_POLYGON));
        
        console.log("USDC token mappings configured");
    }
    
    function _initializeNetworkConfigs() internal {
        // Ethereum Mainnet
        networkConfigs[1] = NetworkConfig({
            poolManager: 0x0000000000000000000000000000000000000001, // Replace with actual V4 PoolManager
            avsDirectory: 0x135DDa560e946695d6f155dACaFC6f1F25C1F5AF,
            registryCoordinator: 0x0000000000000000000000000000000000000000, // Replace with actual
            stakeRegistry: 0x0000000000000000000000000000000000000000, // Replace with actual
            blsApkRegistry: 0x0000000000000000000000000000000000000000, // Replace with actual
            acrossHubPool: 0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5,
            isTestnet: false
        });
        
        // Ethereum Sepolia
        networkConfigs[11155111] = NetworkConfig({
            poolManager: 0x0000000000000000000000000000000000000001, // Replace with testnet address
            avsDirectory: 0x055733000064333CaDDbC92763c58BF0192fFeBf,
            registryCoordinator: 0x0000000000000000000000000000000000000000, // Replace with testnet
            stakeRegistry: 0x0000000000000000000000000000000000000000, // Replace with testnet
            blsApkRegistry: 0x0000000000000000000000000000000000000000, // Replace with testnet
            acrossHubPool: 0x0000000000000000000000000000000000000000, // Replace with testnet
            isTestnet: true
        });
        
        // Add more networks as needed
    }
    
    function _logVerificationCommands(uint256 chainId) internal view {
        console.log("To verify contracts, run:");
        console.log("");
        
        console.log("forge verify-contract --chain-id", chainId, "--etherscan-api-key $ETHERSCAN_API_KEY");
        console.log("  ", deployedServiceManager, "src/avs/CrossCoWServiceManager.sol:CrossCoWServiceManager");
        console.log("");
        
        console.log("forge verify-contract --chain-id", chainId, "--etherscan-api-key $ETHERSCAN_API_KEY");
        console.log("  ", deployedAcrossIntegration, "src/integration/AcrossIntegration.sol:AcrossIntegration");
        console.log("");
        
        console.log("forge verify-contract --chain-id", chainId, "--etherscan-api-key $ETHERSCAN_API_KEY");
        console.log("  ", deployedHook, "src/hooks/EigenCrossCoWHook.sol:EigenCrossCoWHook");
    }
    
    function _logDeploymentSummary() internal view {
        console.log("CrossCoWServiceManager:", deployedServiceManager);
        console.log("AcrossIntegration:", deployedAcrossIntegration);
        console.log("EigenCrossCoWHook:", deployedHook);
        console.log("");
        console.log("Next steps:");
        console.log("1. Update operator config with service manager address");
        console.log("2. Register operators with the AVS");
        console.log("3. Fund the service manager reward pool");
        console.log("4. Test with small trades");
        console.log("");
        console.log("Deployment complete! 🎉");
    }
}