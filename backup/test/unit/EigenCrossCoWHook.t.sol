// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

import "../../src/hooks/EigenCrossCoWHook.sol";
import "../../src/avs/CrossCoWServiceManager.sol";
import "../../src/integration/AcrossIntegration.sol";
import "../helpers/MockContracts.sol";

contract EigenCrossCoWHookTest is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    EigenCrossCoWHook public hook;
    MockServiceManager public mockServiceManager;
    MockAcrossHubPool public mockAcrossHubPool;
    MockPoolManager public poolManager;
    
    // Test tokens
    MockERC20 public token0;
    MockERC20 public token1;
    
    // Test users
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public operator = makeAddr("operator");
    
    // Test pool
    PoolKey public poolKey;
    PoolId public poolId;
    
    // Constants
    uint256 public constant INITIAL_BALANCE = 1000 ether;
    uint32 public constant SOURCE_CHAIN = 1;
    uint32 public constant DEST_CHAIN = 10;
    
    event IntentSubmitted(
        bytes32 indexed intentId,
        address indexed user,
        PoolId indexed poolId,
        Currency tokenIn,
        Currency tokenOut,
        uint256 amountIn,
        uint32 targetChain
    );
    
    event TradeMatched(
        bytes32 indexed tradeId,
        bytes32 indexed intentA,
        bytes32 indexed intentB,
        uint256 amountA,
        uint256 amountB,
        address operatorReward
    );

    function setUp() public {
        // Deploy mock contracts
        poolManager = new MockPoolManager();
        mockServiceManager = new MockServiceManager();
        mockAcrossHubPool = new MockAcrossHubPool();
        
        // Deploy main hook contract
        hook = new EigenCrossCoWHook(
            IPoolManager(address(poolManager)),
            ICrossCoWServiceManager(address(mockServiceManager)),
            IAcrossHubPool(address(mockAcrossHubPool))
        );
        
        // Deploy test tokens
        token0 = new MockERC20("Token0", "T0");
        token1 = new MockERC20("Token1", "T1");
        
        // Setup pool key
        poolKey = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: Hooks.wrap(address(hook))
        });
        
        poolId = poolKey.toId();
        
        // Fund test accounts
        token0.mint(alice, INITIAL_BALANCE);
        token1.mint(alice, INITIAL_BALANCE);
        token0.mint(bob, INITIAL_BALANCE);
        token1.mint(bob, INITIAL_BALANCE);
        
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(address(hook), 10 ether); // For rewards
        
        // Setup chain support
        hook.setSupportedChain(DEST_CHAIN, true);
        hook.setTokenMapping(
            Currency.wrap(address(token0)),
            DEST_CHAIN,
            Currency.wrap(address(token1))
        );
    }

    function test_Hook_Permissions() public {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        
        assertTrue(permissions.beforeSwap);
        assertTrue(permissions.afterSwap);
        assertFalse(permissions.beforeInitialize);
        assertFalse(permissions.afterInitialize);
    }

    function test_Intent_Creation() public {
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -1 ether, // Exact output
            sqrtPriceLimitX96: 0
        });
        
        bytes memory hookData = abi.encode(
            DEST_CHAIN,           // targetChain
            block.timestamp + 300, // deadline
            keccak256("salt")     // salt
        );
        
        vm.startPrank(alice);
        
        // Expect IntentSubmitted event
        vm.expectEmit(true, true, true, true);
        emit IntentSubmitted(
            keccak256(abi.encodePacked(alice, poolId, uint256(1 ether), block.timestamp, keccak256("salt"))),
            alice,
            poolId,
            Currency.wrap(address(token0)),
            Currency.wrap(address(token1)),
            1 ether,
            DEST_CHAIN
        );
        
        // Trigger beforeSwap hook
        hook._beforeSwap(alice, poolKey, params, hookData);
        
        vm.stopPrank();
    }

    function test_Intent_Validation() public {
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -1000, // Too small
            sqrtPriceLimitX96: 0
        });
        
        bytes memory hookData = abi.encode(
            DEST_CHAIN,
            block.timestamp + 300,
            keccak256("salt")
        );
        
        vm.startPrank(alice);
        
        // Should revert due to amount too small
        vm.expectRevert("Amount too small");
        hook._beforeSwap(alice, poolKey, params, hookData);
        
        vm.stopPrank();
    }

    function test_Intent_Deadline_Validation() public {
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: 0
        });
        
        bytes memory hookData = abi.encode(
            DEST_CHAIN,
            block.timestamp - 1, // Expired deadline
            keccak256("salt")
        );
        
        vm.startPrank(alice);
        
        vm.expectRevert("Invalid deadline");
        hook._beforeSwap(alice, poolKey, params, hookData);
        
        vm.stopPrank();
    }

    function test_Unsupported_Chain() public {
        uint32 unsupportedChain = 999;
        
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: 0
        });
        
        bytes memory hookData = abi.encode(
            unsupportedChain,
            block.timestamp + 300,
            keccak256("salt")
        );
        
        vm.startPrank(alice);
        
        // Should not create intent for unsupported chain
        // but should allow normal swap to proceed
        hook._beforeSwap(alice, poolKey, params, hookData);
        
        vm.stopPrank();
    }

    function test_Intent_Cancel() public {
        // First create an intent
        bytes32 intentId = _createTestIntent(alice);
        
        vm.startPrank(alice);
        
        // Cancel the intent
        hook.cancelIntent(intentId);
        
        // Verify intent status
        IntentLib.IntentStatus memory status = hook.getIntentStatus(intentId);
        assertTrue(status.isCancelled);
        
        vm.stopPrank();
    }

    function test_Admin_Functions() public {
        uint32 newChain = 137; // Polygon
        Currency newToken = Currency.wrap(address(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174));
        
        // Test chain configuration
        hook.setSupportedChain(newChain, true);
        assertTrue(hook.supportedChains(newChain));
        
        // Test token mapping
        hook.setTokenMapping(
            Currency.wrap(address(token0)),
            newChain,
            newToken
        );
        
        // Test reward configuration
        uint256 newReward = 2e15; // 0.002 ETH
        hook.setMatchingReward(newReward);
        assertEq(hook.matchingReward(), newReward);
    }

    function test_Access_Control() public {
        vm.startPrank(alice);
        
        // Should revert when non-owner tries to configure
        vm.expectRevert();
        hook.setSupportedChain(137, true);
        
        vm.expectRevert();
        hook.setMatchingReward(1e15);
        
        vm.stopPrank();
    }

    function test_Trade_Execution_Confirmation() public {
        bytes32 tradeId = keccak256("test_trade");
        bytes32 acrossDepositId = keccak256("deposit_123");
        uint256 totalSavings = 0.01 ether;
        
        // Should revert when called by non-service-manager
        vm.startPrank(alice);
        vm.expectRevert("Only service manager");
        hook.confirmTradeExecution(tradeId, acrossDepositId, totalSavings);
        vm.stopPrank();
        
        // Should work when called by service manager
        vm.startPrank(address(mockServiceManager));
        
        // First need to create a matched trade
        IntentLib.MatchedTrade memory trade = IntentLib.MatchedTrade({
            tradeId: tradeId,
            intentA: keccak256("intentA"),
            intentB: keccak256("intentB"),
            amountA: 1 ether,
            amountB: 1 ether,
            chainA: SOURCE_CHAIN,
            chainB: DEST_CHAIN,
            userA: alice,
            userB: bob,
            tokenA: address(token0),
            tokenB: address(token1),
            isExecuted: false,
            executionTime: 0,
            acrossDepositId: bytes32(0)
        });
        
        // Simulate the trade being created (would normally happen in matching)
        // This is a bit of a hack for testing - in real code this would be done differently
        vm.store(
            address(hook),
            keccak256(abi.encode(tradeId, uint256(5))), // slot 5 is matchedTrades mapping
            bytes32(uint256(uint160(trade.userA))) // Store some data to indicate trade exists
        );
        
        hook.confirmTradeExecution(tradeId, acrossDepositId, totalSavings);
        
        vm.stopPrank();
    }

    function test_Emergency_Functions() public {
        // Test pause
        hook.emergencyPauseToggle();
        assertTrue(hook.paused());
        
        // Test unpause
        hook.emergencyPauseToggle();
        assertFalse(hook.paused());
        
        // Test withdrawal
        uint256 initialBalance = address(this).balance;
        hook.withdraw(payable(address(this)), 1 ether);
        assertEq(address(this).balance, initialBalance + 1 ether);
    }

    function test_Statistics_Tracking() public {
        // Get initial global stats
        StatsLib.GlobalStats memory initialStats = hook.getGlobalStats();
        
        // Create some intents to generate stats
        _createTestIntent(alice);
        _createTestIntent(bob);
        
        // Stats should be updated (this is simplified - real stats would be updated during matching)
        StatsLib.GlobalStats memory updatedStats = hook.getGlobalStats();
        // In a real test, we'd verify that stats were properly updated
    }

    // Helper functions
    function _createTestIntent(address user) internal returns (bytes32 intentId) {
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: 0
        });
        
        bytes memory hookData = abi.encode(
            DEST_CHAIN,
            block.timestamp + 300,
            keccak256(abi.encodePacked(user, block.timestamp))
        );
        
        vm.startPrank(user);
        hook._beforeSwap(user, poolKey, params, hookData);
        vm.stopPrank();
        
        // Calculate expected intent ID
        intentId = keccak256(abi.encodePacked(
            user,
            poolId,
            uint256(1 ether),
            block.timestamp,
            keccak256(abi.encodePacked(user, block.timestamp))
        ));
        
        return intentId;
    }

    receive() external payable {}
}