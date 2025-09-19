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

// Test-specific registry coordinator that bypasses signature validation
// Test version of CrossCoWAggregator that bypasses signature validation
contract TestCrossCoWAggregator {
    address public serviceManager;
    address public registryCoordinator;
    address public stakeRegistry;
    address public blsApkRegistry;
    
    uint32 public latestTaskIndex;
    bool public paused;
    
    struct OperatorResponse {
        address operator;
        bytes32 responseHash;
        bytes signature;
        uint256 timestamp;
        bool isValid;
    }
    
    struct AggregatedResponse {
        bytes32 responseHash;
        address[] operators;
        uint256 timestamp;
        bool isFinalized;
        bool isChallenged;
        bytes32 taskHash;
    }
    
    mapping(uint32 => bytes32) public taskHashes;
    mapping(uint32 => mapping(address => OperatorResponse)) public operatorResponses;
    mapping(uint32 => address[]) public respondingOperators;
    mapping(uint32 => AggregatedResponse) public aggregatedResponses;
    
    event TaskReceived(uint32 indexed taskIndex, bytes32 indexed taskHash);
    event OperatorResponseReceived(uint32 indexed taskIndex, address indexed operator, bytes32 responseHash);
    
    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }
    
    function setServiceManager(address _serviceManager) external {
        serviceManager = _serviceManager;
    }
    
    function setRegistryCoordinator(address _registryCoordinator) external {
        registryCoordinator = _registryCoordinator;
    }
    
    function setStakeRegistry(address _stakeRegistry) external {
        stakeRegistry = _stakeRegistry;
    }
    
    function setBlsApkRegistry(address _blsApkRegistry) external {
        blsApkRegistry = _blsApkRegistry;
    }
    
    function submitTask(uint32 taskIndex, bytes32 taskHash) external whenNotPaused {
        require(taskIndex == latestTaskIndex, "Invalid task index");
        taskHashes[taskIndex] = taskHash;
        latestTaskIndex++;
        emit TaskReceived(taskIndex, taskHash);
    }
    
    function submitResponse(
        uint32 taskIndex,
        bytes32 responseHash,
        bytes calldata signature
    ) external whenNotPaused {
        require(taskHashes[taskIndex] != bytes32(0), "Task not found");
        require(operatorResponses[taskIndex][msg.sender].operator == address(0), "Already responded");
        
        // Skip signature validation for tests
        
        // Store operator response
        operatorResponses[taskIndex][msg.sender] = OperatorResponse({
            operator: msg.sender,
            responseHash: responseHash,
            signature: signature,
            timestamp: block.timestamp,
            isValid: true
        });
        
        respondingOperators[taskIndex].push(msg.sender);
        
        emit OperatorResponseReceived(taskIndex, msg.sender, responseHash);
        
        // Auto-aggregate responses for testing
        _aggregateResponses(taskIndex);
    }
    
    function _aggregateResponses(uint32 taskIndex) internal {
        address[] memory operators = respondingOperators[taskIndex];
        if (operators.length >= 2) { // MIN_OPERATORS for testing
            bytes32 responseHash = keccak256(abi.encodePacked("aggregated", taskIndex));
            aggregatedResponses[taskIndex] = AggregatedResponse({
                responseHash: responseHash,
                operators: operators,
                timestamp: block.timestamp,
                isFinalized: false,
                isChallenged: false,
                taskHash: taskHashes[taskIndex]
            });
        }
    }
    
    function getAggregatedResponse(uint32 taskIndex) external view returns (AggregatedResponse memory) {
        return aggregatedResponses[taskIndex];
    }
    
    function finalizeResponse(uint32 taskIndex, bytes32 responseHash) external {
        aggregatedResponses[taskIndex].isFinalized = true;
    }
    
    function challengeResponse(uint32 taskIndex, address operator, string calldata reason, bytes calldata signature) external {
        aggregatedResponses[taskIndex].isChallenged = true;
    }
    
    function resolveChallenge(uint32 taskIndex, bool operatorWins) external {
        aggregatedResponses[taskIndex].isChallenged = false;
    }
    
    function getTaskStatistics(uint32 taskIndex) external view returns (uint256, uint256, uint256) {
        return (respondingOperators[taskIndex].length, 0, 0);
    }
    
    function pause() external {
        paused = true;
    }
    
    function unpause() external {
        paused = false;
    }
    
    function emergencyFinalizeTask(uint32 taskIndex) external {
        aggregatedResponses[taskIndex].isFinalized = true;
    }
}

contract TestRegistryCoordinator {
    IStakeRegistry public stakeRegistry;
    IBLSApkRegistry public blsApkRegistry;
    
    mapping(address => bool) public operators;
    address[] public registeredOperators;
    
    event OperatorRegistered(address indexed operator);
    
    constructor(address _stakeRegistry, address _blsApkRegistry) {
        stakeRegistry = IStakeRegistry(_stakeRegistry);
        blsApkRegistry = IBLSApkRegistry(_blsApkRegistry);
    }
    
    function registerOperator(
        bytes calldata quorumNumbers,
        string calldata socket,
        bytes calldata params,
        bytes calldata operatorSignature
    ) external {
        // Decode the actual operator address from params
        address operator = abi.decode(params, (address));
        
        require(!operators[operator], "Already registered");
        require(registeredOperators.length < 1000, "Max operators reached");
        
        // Skip signature validation for tests
        // Just register the operator
        
        // Generate operator ID
        bytes32 newOperatorId = keccak256(abi.encodePacked(
            operator,
            block.timestamp,
            block.number
        ));
        
        // Register with stake registry (use the actual operator)
        stakeRegistry.registerOperator(operator, newOperatorId, uint96(1 ether));
        
        // Skip BLS APK registry registration for tests
        // The service manager doesn't actually need it for basic functionality
        
        operators[operator] = true;
        registeredOperators.push(operator);
        
        emit OperatorRegistered(operator);
    }
    
    function deregisterOperator(bytes calldata quorumNumbers) external {
        require(operators[msg.sender], "Not registered");
        
        // Deregister from registries
        stakeRegistry.deregisterOperator(keccak256(abi.encodePacked(msg.sender, "operator_id")));
        
        // Skip BLS APK registry deregistration for tests
        
        operators[msg.sender] = false;
        
        // Remove from array
        for (uint i = 0; i < registeredOperators.length; i++) {
            if (registeredOperators[i] == msg.sender) {
                registeredOperators[i] = registeredOperators[registeredOperators.length - 1];
                registeredOperators.pop();
                break;
            }
        }
    }
    
    function isOperatorRegistered(address operator) external view returns (bool) {
        return operators[operator];
    }
    
    function getOperatorId(address operator) external view returns (bytes32) {
        require(operators[operator], "Operator not registered");
        return keccak256(abi.encodePacked(operator, "operator_id"));
    }
    
    function getQuorumBitmap(address operator) external view returns (uint192) {
        require(operators[operator], "Operator not registered");
        return 1; // Simple bitmap for tests
    }
    
    function updateQuorumBitmap(bytes32 operatorId, uint192 newBitmap) external {
        // Mock implementation for tests
        // In real implementation, this would update the quorum bitmap
        // For tests, we just emit an event to indicate the call was made
        emit OperatorRegistered(address(0)); // Mock event
    }
    
    function getCurrentQuorumBitmap(bytes32 operatorId) external view returns (uint192) {
        // Mock implementation for tests
        return 1; // Simple bitmap for tests
    }
    
    function getAllOperators() external view returns (address[] memory) {
        return registeredOperators;
    }
    
    function resetForTesting() external {
        // Reset all operator states
        for (uint i = 0; i < registeredOperators.length; i++) {
            delete operators[registeredOperators[i]];
        }
        delete registeredOperators;
    }
}

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
    TestRegistryCoordinator public registryCoordinator;
    CrossCoWStakeRegistry public stakeRegistry;
    CrossCoWBLSApkRegistry public blsApkRegistry;
    TestCrossCoWAggregator public aggregator;
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
        registryCoordinator = new TestRegistryCoordinator(
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
        aggregator = new TestCrossCoWAggregator();
        
        // Set aggregator dependencies
        aggregator.setServiceManager(address(serviceManager));
        aggregator.setRegistryCoordinator(address(registryCoordinator));
        aggregator.setStakeRegistry(address(stakeRegistry));
        aggregator.setBlsApkRegistry(address(blsApkRegistry));
        
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
        
        // Register with service manager (this will handle stake registry registration through registry coordinator)
        serviceManager.registerOperator{value: STAKE_AMOUNT}(_createValidSignature(operator1, "signature1"));
        
        vm.stopPrank();
        
        // Verify registration
        assertTrue(serviceManager.isOperatorRegistered(operator1));
        assertTrue(stakeRegistry.isOperatorStaked(operator1));
        assertTrue(blsApkRegistry.isOperatorRegistered(operator1));
    }

    function testCrossChainTradeMatching() public {
        _resetForTesting();
        
        // Use unique addresses for this test
        address testOperator1 = vm.addr(0x2001);
        address testOperator2 = vm.addr(0x2002);
        
        // Give operators enough ETH for registration
        vm.deal(testOperator1, 20 ether);
        vm.deal(testOperator2, 20 ether);
        
        // Setup: Register operators first
        _registerOperator(testOperator1);
        _registerOperator(testOperator2);
        
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
        _resetForTesting();
        
        // Use unique addresses for this test
        address testOperator1 = vm.addr(0x1001);
        address testOperator2 = vm.addr(0x1002);
        
        // Give operators enough ETH for registration
        vm.deal(testOperator1, 20 ether);
        vm.deal(testOperator2, 20 ether);
        
        // Setup: Register operators
        _registerOperator(testOperator1);
        _registerOperator(testOperator2);
        
        // Submit task to aggregator
        bytes32 taskHash = keccak256(abi.encodePacked("task1"));
        vm.prank(owner);
        aggregator.submitTask(0, taskHash);
        
        // Submit responses
        bytes32 responseHash1 = keccak256(abi.encodePacked("response1"));
        bytes32 responseHash2 = keccak256(abi.encodePacked("response2"));
        
        vm.prank(testOperator1);
        aggregator.submitResponse(0, responseHash1, abi.encodePacked("sig1"));
        
        vm.prank(testOperator2);
        aggregator.submitResponse(0, responseHash2, abi.encodePacked("sig2"));
        
        // Verify aggregation
        TestCrossCoWAggregator.AggregatedResponse memory aggResponse = aggregator.getAggregatedResponse(0);
        assertTrue(aggResponse.responseHash != bytes32(0));
        assertEq(aggResponse.operators.length, 2);
    }

    function testPauseUnpause() public {
        _resetForTesting();
        
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
        // Give service manager some ETH to withdraw
        vm.deal(address(serviceManager), 1 ether);
        
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
        _resetForTesting();
        
        // Use unique addresses for this test
        address testOperator1 = vm.addr(0x3001);
        address testOperator2 = vm.addr(0x3002);
        
        // Give operators enough ETH for registration
        vm.deal(testOperator1, 20 ether);
        vm.deal(testOperator2, 20 ether);
        
        // Register multiple operators
        _registerOperator(testOperator1);
        _registerOperator(testOperator2);
        
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
        _resetForTesting();
        
        // Give operator enough ETH for staking
        vm.deal(operator1, 10 ether);
        
        // Register operator
        _registerOperator(operator1);
        
        // Check initial stake
        ICrossCoWServiceManager.OperatorInfo memory operatorInfo = serviceManager.getOperatorInfo(operator1);
        assertEq(operatorInfo.stake, STAKE_AMOUNT);
        
        // Update stake (operator needs to have enough ETH)
        // Note: stakeRegistry has 1 ETH staked, so to update to 20 ETH requires 19 ETH
        vm.startPrank(operator1);
        vm.deal(operator1, STAKE_AMOUNT * 3);
        // Ensure operator has enough ETH for the transaction
        assertEq(operator1.balance, STAKE_AMOUNT * 3);
        stakeRegistry.updateStake{value: STAKE_AMOUNT * 2 - 1 ether}(operator1, STAKE_AMOUNT * 2);
        vm.stopPrank();
        
        // Verify stake update in the stake registry
        assertEq(stakeRegistry.getOperatorStake(operator1).amount, STAKE_AMOUNT * 2);
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
        
        // Register with service manager (this will handle stake registry registration through registry coordinator)
        serviceManager.registerOperator{value: STAKE_AMOUNT}(_createValidSignature(operator, "signature"));
        
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

    function _resetForTesting() internal {
        vm.startPrank(owner);
        // Reset service manager state
        serviceManager.resetForTesting();
        vm.stopPrank();
        
        // Reset registry coordinator state
        registryCoordinator.resetForTesting();
        
        // Reset BLS APK registry state
        blsApkRegistry.resetForTesting();
        
        // Reset stake registry state
        stakeRegistry.resetForTesting();
    }
}
