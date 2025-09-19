// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HookMiner} from "v4-periphery/utils/HookMiner.sol";
import {Hooks} from "@uniswap/v4-core/libraries/Hooks.sol";

import "../src/EigenCrossCoWHook.sol";
import "../src/avs/task-managers/CrossCoWTaskManagerSimple.sol";
import "../src/avs/service-managers/CrossCoWServiceManager.sol";
import "../src/avs/registry/CrossCoWRegistryCoordinator.sol";
import "../src/avs/registry/CrossCoWStakeRegistry.sol";
import "../src/avs/registry/CrossCoWBLSApkRegistry.sol";
import "../src/avs/aggregator/CrossCoWAggregator.sol";
import "../src/integration/AcrossIntegration.sol";
import "../src/libraries/IntentLib.sol";
import "../src/avs/interfaces/IBLSApkRegistry.sol";
import "@uniswap/v4-core/types/PoolId.sol";
import "@uniswap/v4-core/types/Currency.sol";

// Test-specific hook that bypasses address validation
contract TestEigenCrossCoWHook is EigenCrossCoWHook {
    constructor(
        IPoolManager _poolManager,
        ICrossCoWServiceManager _serviceManager,
        IAcrossHubPool _acrossHubPool
    ) EigenCrossCoWHook(_poolManager, _serviceManager, _acrossHubPool) {}
    
    // Override to bypass hook address validation in tests
    function validateHookAddress(BaseHook _this) internal pure override {
        // Skip validation for tests
    }
}

// Mock contracts for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10**18);
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockPoolManager {
    function getSlot0(bytes32) external pure returns (uint160, int24, uint24, uint24, uint24, uint24, uint128) {
        return (0, 0, 0, 0, 0, 0, 0);
    }
}

contract MockAcrossHubPool {
    function deposit(
        address recipient,
        address originToken,
        uint256 amount,
        uint256 destinationChainId,
        uint64 relayerFeePct,
        uint32 quoteTimestamp,
        bytes memory message,
        uint256 maxCount
    ) external payable returns (uint32) {
        return 1; // Mock deposit ID
    }
}

/**
 * @title EigenCrossCoWHookTest
 * @notice Comprehensive test suite for EigenCrossCoW AVS
 * @dev Tests all major functionality including cross-chain matching, operator management, and slashing
 */
contract EigenCrossCoWHookTest is Test {
    /* CONTRACTS */
    TestEigenCrossCoWHook public hook;
    CrossCoWTaskManagerSimple public taskManager;
    CrossCoWServiceManager public serviceManager;
    CrossCoWRegistryCoordinator public registryCoordinator;
    CrossCoWStakeRegistry public stakeRegistry;
    CrossCoWBLSApkRegistry public blsApkRegistry;
    CrossCoWAggregator public aggregator;
    AcrossIntegration public acrossIntegration;
    
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    MockPoolManager public poolManager;
    MockAcrossHubPool public acrossHubPool;
    
    /* ADDRESSES */
    address public owner = address(0x1);
    address public operator1 = address(0x2);
    address public operator2 = address(0x3);
    address public user1 = address(0x4);
    address public user2 = address(0x5);
    address public aggregatorAddr = address(0x6);
    address public generator = address(0x7);
    
    /* CONSTANTS */
    uint256 public constant INITIAL_BALANCE = 1000000 * 10**18;
    uint256 public constant STAKE_AMOUNT = 10 ether;
    uint256 public constant TRADE_AMOUNT = 1000 * 10**18;
    
    function _createValidSignature(address operator, string memory suffix) internal pure returns (bytes memory) {
        // Create a 65-byte signature for operator registration
        bytes memory signature = new bytes(65);
        
        // Fill with deterministic data based on operator and suffix
        bytes32 operatorHash = keccak256(abi.encodePacked(operator, suffix));
        
        // Fill first 32 bytes (r)
        for (uint i = 0; i < 32; i++) {
            signature[i] = operatorHash[i];
        }
        
        // Fill next 32 bytes (s)
        bytes32 sHash = keccak256(abi.encodePacked(operator, suffix, "s"));
        for (uint i = 32; i < 64; i++) {
            signature[i] = sHash[i - 32];
        }
        
        // Set recovery ID (v)
        signature[64] = 0x1e;
        
        return signature;
    }
    
    function setUp() public {
        // Set up the owner address
        vm.startPrank(owner);
        
        // Deploy mock tokens
        tokenA = new MockERC20("TokenA", "TKA");
        tokenB = new MockERC20("TokenB", "TKB");
        
        // Deploy mock contracts
        poolManager = new MockPoolManager();
        acrossHubPool = new MockAcrossHubPool();
        
        // Deploy registry contracts
        stakeRegistry = new CrossCoWStakeRegistry(address(0)); // ETH staking
        blsApkRegistry = new CrossCoWBLSApkRegistry();
        registryCoordinator = new CrossCoWRegistryCoordinator(
            address(stakeRegistry),
            address(blsApkRegistry)
        );
        
        // Deploy service manager
        serviceManager = new CrossCoWServiceManager(
            address(registryCoordinator),
            address(stakeRegistry),
            address(blsApkRegistry)
        );
        
        // Deploy aggregator
        aggregator = new CrossCoWAggregator();
        
        // Deploy across integration
        acrossIntegration = new AcrossIntegration(
            IAcrossHubPool(address(acrossHubPool))
        );
        
        // Deploy task manager
        taskManager = new CrossCoWTaskManagerSimple(
            owner,
            address(aggregator),
            generator,
            payable(address(acrossIntegration))
        );
        
        // Deploy test hook (bypasses address validation)
        hook = new TestEigenCrossCoWHook(
            IPoolManager(address(poolManager)),
            serviceManager,
            IAcrossHubPool(address(acrossHubPool))
        );
        
        // Setup initial state
        taskManager.setAggregator(address(aggregator));
        vm.stopPrank();
        
        // Fund test accounts
        tokenA.mint(user1, INITIAL_BALANCE);
        tokenA.mint(user2, INITIAL_BALANCE);
        tokenB.mint(user1, INITIAL_BALANCE);
        tokenB.mint(user2, INITIAL_BALANCE);
        
        // Fund with ETH
        vm.deal(operator1, 100 ether);
        vm.deal(operator2, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }

    function testInitialization() public {
        assertEq(address(hook.poolManager()), address(poolManager));
        assertEq(address(hook.serviceManager()), address(serviceManager));
        assertEq(address(hook.acrossHubPool()), address(acrossHubPool));
        assertTrue(hook.owner() == owner);
    }

    function testOperatorRegistration() public {
        // Register operator1
        vm.startPrank(operator1);
        
        // Register with BLS APK registry
        // Create BLS public key registration params
        BN254.G1Point memory pubkeyG1 = BN254.G1Point(1, 2);
        BN254.G2Point memory pubkeyG2 = BN254.G2Point([uint256(1), uint256(2)], [uint256(3), uint256(4)]);
        BN254.G1Point memory signature = BN254.G1Point(5, 6);
        
        IBLSApkRegistry.PubkeyRegistrationParams memory params = IBLSApkRegistry.PubkeyRegistrationParams({
            pubkeyRegistrationSignature: signature,
            pubkeyG1: pubkeyG1,
            pubkeyG2: pubkeyG2
        });
        
        blsApkRegistry.registerBLSPublicKey(
            operator1,
            params,
            signature
        );
        
        // Register with stake registry
        stakeRegistry.registerOperator(operator1, bytes32(uint256(uint160(operator1))), uint96(STAKE_AMOUNT));
        
        // Register with service manager
        serviceManager.registerOperator{value: STAKE_AMOUNT}(_createValidSignature(operator1, "signature1"));
        
        vm.stopPrank();
        
        // Verify registration
        assertTrue(serviceManager.isOperatorRegistered(operator1));
        assertTrue(stakeRegistry.isOperatorStaked(operator1));
        assertTrue(blsApkRegistry.isOperatorRegistered(operator1));
    }

    function testCrossChainTradeMatching() public {
        // Setup: Register operators first
        _registerOperator(operator1);
        _registerOperator(operator2);
        
        // Create trade intents
        IntentLib.TradeIntent memory intent1 = IntentLib.TradeIntent({
            intentId: bytes32(uint256(1)),
            user: user1,
            poolId: PoolId.wrap(bytes32(uint256(1))),
            tokenIn: Currency.wrap(address(tokenA)),
            tokenOut: Currency.wrap(address(tokenB)),
            amountIn: TRADE_AMOUNT,
            amountOutMinimum: TRADE_AMOUNT * 95 / 100,
            deadline: block.timestamp + 3600,
            originChain: 1,
            targetChain: 2,
            isActive: true,
            createdAt: block.timestamp,
            salt: bytes32(uint256(1))
        });
        
        IntentLib.TradeIntent memory intent2 = IntentLib.TradeIntent({
            intentId: bytes32(uint256(2)),
            user: user2,
            poolId: PoolId.wrap(bytes32(uint256(2))),
            tokenIn: Currency.wrap(address(tokenB)),
            tokenOut: Currency.wrap(address(tokenA)),
            amountIn: TRADE_AMOUNT,
            amountOutMinimum: TRADE_AMOUNT * 95 / 100,
            deadline: block.timestamp + 3600,
            originChain: 2,
            targetChain: 1,
            isActive: true,
            createdAt: block.timestamp,
            salt: bytes32(uint256(2))
        });
        
        // Create matched trade
        IntentLib.MatchedTrade memory matchedTrade = IntentLib.MatchedTrade({
            tradeId: keccak256(abi.encodePacked("trade1")),
            intentA: keccak256(abi.encode(intent1)),
            intentB: keccak256(abi.encode(intent2)),
            amountA: TRADE_AMOUNT,
            amountB: TRADE_AMOUNT,
            chainA: 1,
            chainB: 2,
            userA: user1,
            userB: user2,
            tokenA: Currency.wrap(address(tokenA)),
            tokenB: Currency.wrap(address(tokenB)),
            isExecuted: false,
            executionTime: 0,
            acrossDepositId: bytes32(0)
        });
        
        // Process matched trade
        vm.prank(generator);
        serviceManager.processMatchedTrade(matchedTrade);
        
        // Verify task was created
        ICrossCoWServiceManager.MatchingTask memory task = serviceManager.getTask(0);
        assertEq(task.tradeId, matchedTrade.tradeId);
        assertTrue(task.assignedOperator != address(0));
    }

    function testTaskExecution() public {
        // Setup: Register operator and create task
        _registerOperator(operator1);
        _createTestTask();
        
        // Submit task response
        ICrossCoWServiceManager.TaskResponse memory response = ICrossCoWServiceManager.TaskResponse({
            taskIndex: 0,
            tradeId: keccak256(abi.encodePacked("trade1")),
            success: true,
            acrossDepositId: keccak256(abi.encodePacked("deposit1")),
            gasUsed: 100000,
            executionTime: block.timestamp,
            signature: _createValidSignature(operator1, "response_signature")
        });
        
        vm.prank(operator1);
        serviceManager.submitTaskResponse(response);
        
        // Verify task completion
        ICrossCoWServiceManager.MatchingTask memory task = serviceManager.getTask(0);
        assertTrue(task.isComplete);
        
        // Verify operator stats
        ICrossCoWServiceManager.OperatorInfo memory operatorInfo = serviceManager.getOperatorInfo(operator1);
        assertEq(operatorInfo.successCount, 1);
    }

    function testOperatorSlashing() public {
        // Setup: Register operator
        _registerOperator(operator1);
        
        // Slash operator
        vm.prank(owner);
        serviceManager.slashOperator(operator1, 1 ether, "Test slashing");
        
        // Verify slashing
        ICrossCoWServiceManager.OperatorInfo memory operatorInfo = serviceManager.getOperatorInfo(operator1);
        assertTrue(operatorInfo.stake < STAKE_AMOUNT);
    }

    function testAggregatorFunctionality() public {
        // Setup: Register operators
        _registerOperator(operator1);
        _registerOperator(operator2);
        
        // Submit task to aggregator
        bytes32 taskHash = keccak256(abi.encodePacked("task1"));
        vm.prank(owner);
        aggregator.submitTask(0, taskHash);
        
        // Submit responses
        bytes32 responseHash1 = keccak256(abi.encodePacked("response1"));
        bytes32 responseHash2 = keccak256(abi.encodePacked("response2"));
        
        vm.prank(operator1);
        aggregator.submitResponse(0, responseHash1, abi.encodePacked("sig1"));
        
        vm.prank(operator2);
        aggregator.submitResponse(0, responseHash2, abi.encodePacked("sig2"));
        
        // Verify aggregation
        CrossCoWAggregator.AggregatedResponse memory aggResponse = aggregator.getAggregatedResponse(0);
        assertTrue(aggResponse.responseHash != bytes32(0));
        assertEq(aggResponse.operators.length, 2);
    }

    function testPauseUnpause() public {
        // Test service manager pause
        vm.prank(owner);
        serviceManager.pauseOperations();
        
        // Should fail when paused
        vm.expectRevert();
        serviceManager.registerOperator{value: STAKE_AMOUNT}(_createValidSignature(operator2, "signature2"));
        
        // Unpause
        vm.prank(owner);
        serviceManager.unpauseOperations();
        
        // Should work when unpaused
        _registerOperator(operator1);
        assertTrue(serviceManager.isOperatorRegistered(operator1));
    }

    function testEmergencyFunctions() public {
        // Test emergency withdraw
        uint256 initialBalance = address(serviceManager).balance;
        
        vm.prank(owner);
        serviceManager.emergencyWithdraw();
        
        assertEq(address(serviceManager).balance, 0);
        assertGt(owner.balance, initialBalance);
    }

    function testTaskTimeout() public {
        // Setup: Register operator and create task
        _registerOperator(operator1);
        _createTestTask();
        
        // Fast forward time past deadline
        vm.warp(block.timestamp + 400); // Past 5 minute deadline
        
        // Handle expired tasks
        serviceManager.handleExpiredTasks();
        
        // Verify task is marked as complete
        ICrossCoWServiceManager.MatchingTask memory task = serviceManager.getTask(0);
        assertTrue(task.isComplete);
    }

    function testMultipleOperators() public {
        // Register multiple operators
        _registerOperator(operator1);
        _registerOperator(operator2);
        
        // Create multiple tasks
        for (uint i = 0; i < 5; i++) {
            _createTestTask();
        }
        
        // Verify tasks are distributed among operators
        address[] memory activeOperators = serviceManager.getActiveOperators();
        assertEq(activeOperators.length, 2);
        
        // Check task assignments
        for (uint i = 0; i < 5; i++) {
            ICrossCoWServiceManager.MatchingTask memory task = serviceManager.getTask(uint32(i));
            assertTrue(task.assignedOperator == operator1 || task.assignedOperator == operator2);
        }
    }

    function testStakeManagement() public {
        // Register operator
        _registerOperator(operator1);
        
        // Check initial stake
        ICrossCoWServiceManager.OperatorInfo memory operatorInfo = serviceManager.getOperatorInfo(operator1);
        assertEq(operatorInfo.stake, STAKE_AMOUNT);
        
        // Update stake
        vm.prank(operator1);
        stakeRegistry.updateStake(operator1, STAKE_AMOUNT * 2);
        
        // Verify stake update
        operatorInfo = serviceManager.getOperatorInfo(operator1);
        assertEq(operatorInfo.stake, STAKE_AMOUNT * 2);
    }

    function testRewardDistribution() public {
        // Setup: Register operator and create task
        _registerOperator(operator1);
        _createTestTask();
        
        // Submit successful response
        ICrossCoWServiceManager.TaskResponse memory response = ICrossCoWServiceManager.TaskResponse({
            taskIndex: 0,
            tradeId: keccak256(abi.encodePacked("trade1")),
            success: true,
            acrossDepositId: keccak256(abi.encodePacked("deposit1")),
            gasUsed: 100000,
            executionTime: block.timestamp,
            signature: _createValidSignature(operator1, "response_signature")
        });
        
        vm.prank(operator1);
        serviceManager.submitTaskResponse(response);
        
        // Verify reward
        ICrossCoWServiceManager.OperatorInfo memory operatorInfo = serviceManager.getOperatorInfo(operator1);
        assertGt(operatorInfo.totalRewards, 0);
    }

    // Helper functions
    function _registerOperator(address operator) internal {
        vm.startPrank(operator);
        
        // Register with BLS APK registry
        // Create BLS public key registration params
        BN254.G1Point memory pubkeyG1 = BN254.G1Point(1, 2);
        BN254.G2Point memory pubkeyG2 = BN254.G2Point([uint256(1), uint256(2)], [uint256(3), uint256(4)]);
        BN254.G1Point memory signature = BN254.G1Point(5, 6);
        
        IBLSApkRegistry.PubkeyRegistrationParams memory params = IBLSApkRegistry.PubkeyRegistrationParams({
            pubkeyRegistrationSignature: signature,
            pubkeyG1: pubkeyG1,
            pubkeyG2: pubkeyG2
        });
        
        blsApkRegistry.registerBLSPublicKey(
            operator,
            params,
            signature
        );
        
        // Register with stake registry
        stakeRegistry.registerOperator(operator, bytes32(uint256(uint160(operator))), uint96(STAKE_AMOUNT));
        
        // Register with service manager
        serviceManager.registerOperator{value: STAKE_AMOUNT}(_createValidSignature(operator2, "signature2"));
        
        vm.stopPrank();
    }
    
    function _createTestTask() internal {
        IntentLib.TradeIntent memory intent1 = IntentLib.TradeIntent({
            intentId: bytes32(uint256(1)),
            user: user1,
            poolId: PoolId.wrap(bytes32(uint256(1))),
            tokenIn: Currency.wrap(address(tokenA)),
            tokenOut: Currency.wrap(address(tokenB)),
            amountIn: TRADE_AMOUNT,
            amountOutMinimum: TRADE_AMOUNT * 95 / 100,
            deadline: block.timestamp + 3600,
            originChain: 1,
            targetChain: 2,
            isActive: true,
            createdAt: block.timestamp,
            salt: bytes32(uint256(1))
        });
        
        IntentLib.TradeIntent memory intent2 = IntentLib.TradeIntent({
            intentId: bytes32(uint256(2)),
            user: user2,
            poolId: PoolId.wrap(bytes32(uint256(2))),
            tokenIn: Currency.wrap(address(tokenB)),
            tokenOut: Currency.wrap(address(tokenA)),
            amountIn: TRADE_AMOUNT,
            amountOutMinimum: TRADE_AMOUNT * 95 / 100,
            deadline: block.timestamp + 3600,
            originChain: 2,
            targetChain: 1,
            isActive: true,
            createdAt: block.timestamp,
            salt: bytes32(uint256(2))
        });
        
        IntentLib.MatchedTrade memory matchedTrade = IntentLib.MatchedTrade({
            tradeId: keccak256(abi.encodePacked("trade", block.timestamp)),
            intentA: keccak256(abi.encode(intent1)),
            intentB: keccak256(abi.encode(intent2)),
            amountA: TRADE_AMOUNT,
            amountB: TRADE_AMOUNT,
            chainA: 1,
            chainB: 2,
            userA: user1,
            userB: user2,
            tokenA: Currency.wrap(address(tokenA)),
            tokenB: Currency.wrap(address(tokenB)),
            isExecuted: false,
            executionTime: 0,
            acrossDepositId: bytes32(0)
        });
        
        vm.prank(generator);
        serviceManager.processMatchedTrade(matchedTrade);
    }
}
