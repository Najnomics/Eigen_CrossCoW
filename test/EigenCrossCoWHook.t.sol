// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../src/EigenCrossCoWHook.sol";
import "../src/avs/task-managers/CrossCoWTaskManagerSimple.sol";
import "../src/avs/service-managers/CrossCoWServiceManager.sol";
import "../src/avs/registry/CrossCoWRegistryCoordinator.sol";
import "../src/avs/registry/CrossCoWStakeRegistry.sol";
import "../src/avs/registry/CrossCoWBLSApkRegistry.sol";
import "../src/avs/aggregator/CrossCoWAggregator.sol";
import "../src/integration/AcrossIntegration.sol";
import "../src/libraries/IntentLib.sol";

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
    EigenCrossCoWHook public hook;
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
    
    function setUp() public {
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
        aggregator = new CrossCoWAggregator(
            address(serviceManager),
            address(registryCoordinator),
            address(stakeRegistry),
            address(blsApkRegistry),
            address(0) // Task manager will be deployed later
        );
        
        // Deploy across integration
        acrossIntegration = new AcrossIntegration(
            address(acrossHubPool),
            address(0), // Mock relayer
            address(0)  // Mock spoke pool
        );
        
        // Deploy task manager
        taskManager = new CrossCoWTaskManagerSimple(
            owner,
            address(aggregator),
            generator,
            payable(address(acrossIntegration))
        );
        
        // Deploy main hook
        hook = new EigenCrossCoWHook(
            IPoolManager(address(poolManager)),
            address(taskManager),
            address(serviceManager),
            address(acrossIntegration)
        );
        
        // Setup initial state
        vm.startPrank(owner);
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
        assertEq(address(hook.taskManager()), address(taskManager));
        assertEq(address(hook.serviceManager()), address(serviceManager));
        assertEq(address(hook.acrossIntegration()), address(acrossIntegration));
        assertTrue(hook.owner() == owner);
    }

    function testOperatorRegistration() public {
        // Register operator1
        vm.startPrank(operator1);
        
        // Register with BLS APK registry
        blsApkRegistry.registerOperator(
            operator1,
            keccak256(abi.encodePacked(operator1, "key1")),
            IBLSApkRegistry.BLSPublicKey({
                g1Pubkey: abi.encodePacked(operator1, "g1"),
                g2Pubkey: abi.encodePacked(operator1, "g2")
            })
        );
        
        // Register with stake registry
        stakeRegistry.registerOperator{value: STAKE_AMOUNT}(operator1, STAKE_AMOUNT);
        
        // Register with service manager
        serviceManager.registerOperator{value: STAKE_AMOUNT}(abi.encodePacked("signature1"));
        
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
        IntentLib.Intent memory intent1 = IntentLib.Intent({
            user: user1,
            inputToken: address(tokenA),
            outputToken: address(tokenB),
            inputAmount: TRADE_AMOUNT,
            minOutputAmount: TRADE_AMOUNT * 95 / 100, // 5% slippage
            sourceChain: 1,
            destinationChain: 2,
            deadline: uint32(block.timestamp + 3600),
            signature: abi.encodePacked("signature1")
        });
        
        IntentLib.Intent memory intent2 = IntentLib.Intent({
            user: user2,
            inputToken: address(tokenB),
            outputToken: address(tokenA),
            inputAmount: TRADE_AMOUNT,
            minOutputAmount: TRADE_AMOUNT * 95 / 100, // 5% slippage
            sourceChain: 2,
            destinationChain: 1,
            deadline: uint32(block.timestamp + 3600),
            signature: abi.encodePacked("signature2")
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
            signature: abi.encodePacked("signature")
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
        serviceManager.registerOperator{value: STAKE_AMOUNT}(abi.encodePacked("signature"));
        
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
            ICrossCoWServiceManager.MatchingTask memory task = serviceManager.getTask(i);
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
            signature: abi.encodePacked("signature")
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
        blsApkRegistry.registerOperator(
            operator,
            keccak256(abi.encodePacked(operator, "key")),
            IBLSApkRegistry.BLSPublicKey({
                g1Pubkey: abi.encodePacked(operator, "g1"),
                g2Pubkey: abi.encodePacked(operator, "g2")
            })
        );
        
        // Register with stake registry
        stakeRegistry.registerOperator{value: STAKE_AMOUNT}(operator, STAKE_AMOUNT);
        
        // Register with service manager
        serviceManager.registerOperator{value: STAKE_AMOUNT}(abi.encodePacked("signature"));
        
        vm.stopPrank();
    }
    
    function _createTestTask() internal {
        IntentLib.Intent memory intent1 = IntentLib.Intent({
            user: user1,
            inputToken: address(tokenA),
            outputToken: address(tokenB),
            inputAmount: TRADE_AMOUNT,
            minOutputAmount: TRADE_AMOUNT * 95 / 100,
            sourceChain: 1,
            destinationChain: 2,
            deadline: uint32(block.timestamp + 3600),
            signature: abi.encodePacked("signature1")
        });
        
        IntentLib.Intent memory intent2 = IntentLib.Intent({
            user: user2,
            inputToken: address(tokenB),
            outputToken: address(tokenA),
            inputAmount: TRADE_AMOUNT,
            minOutputAmount: TRADE_AMOUNT * 95 / 100,
            sourceChain: 2,
            destinationChain: 1,
            deadline: uint32(block.timestamp + 3600),
            signature: abi.encodePacked("signature2")
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
