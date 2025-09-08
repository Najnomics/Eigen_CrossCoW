// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../src/avs/interfaces/ICrossCoWServiceManager.sol";
import "../../src/integration/interfaces/IAcrossHubPool.sol";
import "../../src/libraries/IntentLib.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

contract MockPoolManager {
    mapping(bytes32 => bytes32) public slots;
    
    function getSlot0(bytes32 poolId) external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 protocolFee,
        uint24 swapFee
    ) {
        // Return mock values
        return (1 << 96, 0, 0, 3000); // Price = 1, tick = 0, fees = 0 and 0.3%
    }
}

contract MockServiceManager is ICrossCoWServiceManager {
    mapping(address => bool) public registeredOperators;
    mapping(uint32 => MatchingTask) public tasks;
    uint32 public taskCounter;
    
    function registerOperator(bytes calldata) external payable override {
        registeredOperators[msg.sender] = true;
        emit OperatorRegistered(msg.sender, msg.value);
    }
    
    function deregisterOperator() external override {
        registeredOperators[msg.sender] = false;
        emit OperatorDeregistered(msg.sender);
    }
    
    function processMatchedTrade(IntentLib.MatchedTrade calldata trade) external override {
        uint32 taskIndex = taskCounter++;
        
        tasks[taskIndex] = MatchingTask({
            taskIndex: taskIndex,
            tradeId: trade.tradeId,
            trade: trade,
            taskCreatedBlock: uint32(block.number),
            deadline: block.timestamp + 300,
            isComplete: false,
            assignedOperator: msg.sender
        });
        
        emit TaskCreated(taskIndex, trade.tradeId, msg.sender);
    }
    
    function submitTaskResponse(TaskResponse calldata response) external override {
        require(registeredOperators[msg.sender], "Not registered");
        
        MatchingTask storage task = tasks[response.taskIndex];
        task.isComplete = true;
        
        emit TaskCompleted(response.taskIndex, response.tradeId, response.success);
    }
    
    function slashOperator(address, uint256 amount, string calldata reason) external override {
        emit OperatorSlashed(msg.sender, amount, reason);
    }
    
    function updateTaskTimeout(uint256) external override {
        // Mock implementation
    }
    
    function pauseOperations() external override {
        // Mock implementation
    }
    
    function unpauseOperations() external override {
        // Mock implementation
    }
    
    // View functions
    function getOperatorInfo(address operator) external view override returns (OperatorInfo memory) {
        return OperatorInfo({
            operatorAddress: operator,
            stake: registeredOperators[operator] ? 32 ether : 0,
            isActive: registeredOperators[operator],
            lastTaskTime: 0,
            successCount: 0,
            failureCount: 0,
            totalRewards: 0
        });
    }
    
    function getTask(uint32 taskIndex) external view override returns (MatchingTask memory) {
        return tasks[taskIndex];
    }
    
    function getActiveOperators() external view override returns (address[] memory) {
        // Simplified - return empty array
        return new address[](0);
    }
    
    function getTotalStake() external pure override returns (uint256) {
        return 100 ether; // Mock value
    }
    
    function isOperatorRegistered(address operator) external view override returns (bool) {
        return registeredOperators[operator];
    }
}

contract MockAcrossHubPool is IAcrossHubPool {
    uint32 private depositCounter = 1;
    mapping(uint32 => DepositInfo) public deposits;
    
    struct DepositInfo {
        address depositor;
        address recipient;
        address inputToken;
        address outputToken;
        uint256 inputAmount;
        uint256 outputAmount;
        uint256 destinationChainId;
    }
    
    function depositV3(
        address depositor,
        address recipient,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId,
        address, // exclusiveRelayer
        uint32, // quoteTimestamp
        uint32, // fillDeadline
        uint32, // exclusivityDeadline
        bytes calldata // message
    ) external payable override returns (uint32 depositId) {
        depositId = depositCounter++;
        
        deposits[depositId] = DepositInfo({
            depositor: depositor,
            recipient: recipient,
            inputToken: inputToken,
            outputToken: outputToken,
            inputAmount: inputAmount,
            outputAmount: outputAmount,
            destinationChainId: destinationChainId
        });
        
        emit FundsDeposited(
            inputAmount,
            block.chainid,
            destinationChainId,
            1000, // 1% fee
            depositId,
            uint32(block.timestamp),
            depositor,
            recipient,
            outputToken,
            ""
        );
        
        return depositId;
    }
    
    function depositV3Now(
        address depositor,
        address recipient,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId,
        address exclusiveRelayer,
        uint32 fillDeadline,
        uint32 exclusivityDeadline,
        bytes calldata message
    ) external payable override returns (uint32 depositId) {
        return depositV3(
            depositor,
            recipient,
            inputToken,
            outputToken,
            inputAmount,
            outputAmount,
            destinationChainId,
            exclusiveRelayer,
            uint32(block.timestamp),
            fillDeadline,
            exclusivityDeadline,
            message
        );
    }
    
    function speedUpV3Deposit(
        address,
        uint32,
        uint256,
        address,
        bytes calldata
    ) external override {
        // Mock implementation
    }
    
    function fillV3Relay(
        address,
        address,
        address,
        address,
        address,
        uint256,
        uint256,
        uint256,
        uint32,
        uint32,
        uint32,
        bytes calldata
    ) external override {
        // Mock implementation
    }
    
    function enableL1TokenForLiquidityProvision(address) external override {
        // Mock implementation
    }
    
    function disableL1TokenForLiquidityProvision(address) external override {
        // Mock implementation
    }
    
    function addLiquidity(address, uint256) external payable override {
        // Mock implementation
    }
    
    function removeLiquidity(address, uint256, bool) external override {
        // Mock implementation
    }
    
    function pooledTokens(address) external pure override returns (PooledToken memory) {
        return PooledToken({
            lpToken: address(0),
            isEnabled: true,
            lastLpFeeUpdate: uint32(block.timestamp),
            utilizedReserves: 0,
            liquidReserves: 1000000 ether,
            undistributedLpFees: 0
        });
    }
    
    function getCurrentTime() external view override returns (uint32) {
        return uint32(block.timestamp);
    }
    
    function liquidityUtilizationCurrent(address) external pure override returns (uint256) {
        return 5000; // 50% utilization
    }
    
    function liquidityUtilizationPostRelay(address, uint256) external pure override returns (uint256) {
        return 5500; // 55% utilization after relay
    }
    
    function sync(address) external override {
        // Mock implementation
    }
}