// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IStakeRegistry.sol";

/**
 * @title CrossCoWStakeRegistry
 * @notice Stake Registry for CrossCoW AVS - manages operator stakes and slashing
 * @dev Implements proper EigenLayer AVS patterns with stake management
 */
contract CrossCoWStakeRegistry is Ownable, ReentrancyGuard, Pausable, IStakeRegistry {
    using SafeERC20 for IERC20;
    
    constructor(address _stakeToken) Ownable(msg.sender) {
        if (_stakeToken != address(0)) {
            stakeToken = IERC20(_stakeToken);
        }
    }

    /* CONSTANTS */
    uint256 public constant MIN_STAKE = 1 ether;
    uint256 public constant MAX_STAKE = 1000 ether;
    uint256 public constant SLASH_PENALTY = 1000; // 10% of stake
    uint256 public constant REWARD_RATE = 100; // 1% of task value
    
    /* STRUCTS */
    struct OperatorStake {
        uint256 amount;
        uint256 lastUpdateTime;
        bool isActive;
    }
    
    /* STORAGE */
    mapping(address => OperatorStake) public operatorStakes;
    mapping(address => uint256) public totalStakes;
    mapping(address => uint256) public slashedAmounts;
    mapping(address => uint256) public rewardAmounts;
    
    address[] public stakedOperators;
    uint256 public totalStake;
    uint256 public totalSlashed;
    uint256 public totalRewards;
    
    IERC20 public stakeToken; // ETH or ERC20 token for staking
    
    /* EVENTS */
    event OperatorRegistered(address indexed operator, uint256 stake);
    event OperatorDeregistered(address indexed operator);
    event StakeDeposited(address indexed operator, uint256 amount);
    event StakeWithdrawn(address indexed operator, uint256 amount);
    event OperatorSlashed(address indexed operator, uint256 amount, string reason);
    event OperatorRewarded(address indexed operator, uint256 amount);
    event StakeUpdated(address indexed operator, uint256 newStake);

    /* MODIFIERS */
    modifier onlyValidOperator(address operator) {
        require(operatorStakes[operator].isActive, "Operator not registered");
        _;
    }

    modifier onlyValidStake(uint256 amount) {
        require(amount >= MIN_STAKE, "Insufficient stake");
        require(amount <= MAX_STAKE, "Excessive stake");
        _;
    }


    /**
     * @notice Register an operator with stake
     * @param operator The operator address
     * @param stake The stake amount
     */
    function registerOperator(
        address operator,
        uint256 stake
    ) external {
        require(!operatorStakes[operator].isActive, "Already registered");
        require(stake >= MIN_STAKE, "Insufficient stake");
        
        // Generate operator ID
        bytes32 operatorId = keccak256(abi.encodePacked(operator, block.timestamp));
        
        // Initialize operator stake
        operatorStakes[operator] = OperatorStake({
            amount: stake,
            lastUpdateTime: block.timestamp,
            isActive: true
        });
        
        totalStakes[operator] = stake;
        totalStake += stake;
        stakedOperators.push(operator);
        
        emit OperatorRegistered(operator, stake);
        emit StakeDeposited(operator, stake);
    }
    
    /**
     * @notice Register an operator with stake (interface implementation)
     * @param operator The operator address
     * @param operatorId The operator ID
     * @param stake The stake amount
     */
    function registerOperator(
        address operator,
        bytes32 operatorId,
        uint96 stake
    ) external override {
        require(!operatorStakes[operator].isActive, "Already registered");
        require(stake >= MIN_STAKE, "Insufficient stake");
        
        // Initialize operator stake
        operatorStakes[operator] = OperatorStake({
            amount: stake,
            lastUpdateTime: block.timestamp,
            isActive: true
        });
        
        totalStakes[operator] = stake;
        totalStake += stake;
        stakedOperators.push(operator);
        
        emit OperatorRegistered(operator, stake);
        emit StakeDeposited(operator, stake);
    }

    /**
     * @notice Deregister an operator and withdraw stake
     * @param operator The operator address
     */
    function deregisterOperator(address operator) external onlyValidOperator(operator) {
        require(operator == msg.sender || msg.sender == owner(), "Not authorized");
        
        OperatorStake storage stake = operatorStakes[operator];
        require(stake.isActive, "Not active");
        
        // Calculate withdrawable amount (stake - slashed + rewards)
        uint256 withdrawableAmount = stake.amount - slashedAmounts[operator] + rewardAmounts[operator];
        require(withdrawableAmount > 0, "No withdrawable amount");
        
        // Update state
        stake.isActive = false;
        totalStake -= stake.amount;
        
        // Remove from staked operators array
        for (uint i = 0; i < stakedOperators.length; i++) {
            if (stakedOperators[i] == operator) {
                stakedOperators[i] = stakedOperators[stakedOperators.length - 1];
                stakedOperators.pop();
                break;
            }
        }
        
        // Transfer stake back to operator
        if (address(stakeToken) == address(0)) {
            // ETH staking
            payable(operator).transfer(withdrawableAmount);
        } else {
            // ERC20 staking
            stakeToken.safeTransfer(operator, withdrawableAmount);
        }
        
        emit OperatorDeregistered(operator);
        emit StakeWithdrawn(operator, withdrawableAmount);
    }

    /**
     * @notice Update operator stake
     * @param operator The operator address
     * @param newStake The new stake amount
     */
    function updateStake(address operator, uint256 newStake) external payable onlyValidOperator(operator) {
        require(operator == msg.sender || msg.sender == owner(), "Not authorized");
        require(newStake >= MIN_STAKE, "Insufficient stake");
        require(newStake <= MAX_STAKE, "Excessive stake");
        
        OperatorStake storage stake = operatorStakes[operator];
        uint256 currentStake = stake.amount;
        
        if (newStake > currentStake) {
            // Increase stake
            uint256 additionalStake = newStake - currentStake;
            
            if (address(stakeToken) == address(0)) {
                // ETH staking
                require(msg.value >= additionalStake, "Insufficient ETH");
                if (msg.value > additionalStake) {
                    payable(msg.sender).transfer(msg.value - additionalStake);
                }
            } else {
                // ERC20 staking
                stakeToken.safeTransferFrom(msg.sender, address(this), additionalStake);
            }
            
            totalStake += additionalStake;
        } else if (newStake < currentStake) {
            // Decrease stake
            uint256 decreaseAmount = currentStake - newStake;
            require(decreaseAmount <= currentStake - slashedAmounts[operator], "Cannot withdraw slashed amount");
            
            totalStake -= decreaseAmount;
            
            if (address(stakeToken) == address(0)) {
                // ETH staking
                payable(operator).transfer(decreaseAmount);
            } else {
                // ERC20 staking
                stakeToken.safeTransfer(operator, decreaseAmount);
            }
        }
        
        stake.amount = newStake;
        stake.lastUpdateTime = block.timestamp;
        totalStakes[operator] = newStake;
        
        emit StakeUpdated(operator, newStake);
    }

    /**
     * @notice Slash an operator
     * @param operator The operator address
     * @param amount The amount to slash
     * @param reason The reason for slashing
     */
    function slashOperator(address operator, uint256 amount, string calldata reason) external onlyOwner {
        require(operatorStakes[operator].isActive, "Operator not active");
        require(amount <= operatorStakes[operator].amount, "Insufficient stake");
        
        OperatorStake storage stake = operatorStakes[operator];
        slashedAmounts[operator] += amount;
        stake.amount -= amount;
        totalStake -= amount;
        totalSlashed += amount;
        
        emit OperatorSlashed(operator, amount, reason);
    }

    /**
     * @notice Reward an operator
     * @param operator The operator address
     * @param amount The reward amount
     */
    function rewardOperator(address operator, uint256 amount) external onlyOwner {
        require(operatorStakes[operator].isActive, "Operator not active");
        
        rewardAmounts[operator] += amount;
        totalRewards += amount;
        
        emit OperatorRewarded(operator, amount);
    }

    /**
     * @notice Get operator stake info
     * @param operator The operator address
     * @return The operator stake info
     */
    function getOperatorStake(address operator) external view returns (OperatorStake memory) {
        return operatorStakes[operator];
    }

    /**
     * @notice Get total stake
     * @return The total stake amount
     */
    function getTotalStake() external view returns (uint256) {
        return totalStake;
    }

    /**
     * @notice Get operator count
     * @return The number of staked operators
     */
    function getOperatorCount() external view returns (uint256) {
        return stakedOperators.length;
    }

    /**
     * @notice Get all staked operators
     * @return Array of staked operator addresses
     */
    function getAllOperators() external view returns (address[] memory) {
        return stakedOperators;
    }

    /**
     * @notice Check if operator is staked
     * @param operator The operator address
     * @return True if staked
     */
    function isOperatorStaked(address operator) external view returns (bool) {
        return operatorStakes[operator].isActive;
    }

    /**
     * @notice Get operator's withdrawable amount
     * @param operator The operator address
     * @return The withdrawable amount
     */
    function getWithdrawableAmount(address operator) external view returns (uint256) {
        OperatorStake memory stake = operatorStakes[operator];
        if (!stake.isActive) {
            return 0;
        }
        return stake.amount - slashedAmounts[operator] + rewardAmounts[operator];
    }

    /**
     * @notice Emergency withdraw function
     */
    function emergencyWithdraw() external onlyOwner {
        if (address(stakeToken) == address(0)) {
            // ETH
            payable(owner()).transfer(address(this).balance);
        } else {
            // ERC20
            stakeToken.safeTransfer(owner(), stakeToken.balanceOf(address(this)));
        }
    }

    /**
     * @notice Pause operations
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause operations
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Receive ETH for staking
     */
    receive() external payable {
        // Allow ETH to be sent to this contract for staking
    }

    /*//////////////////////////////////////////////////////////////
                         INTERFACE IMPLEMENTATIONS
    //////////////////////////////////////////////////////////////*/

    function deregisterOperator(bytes32 operatorId) external override {
        // Find operator by ID - simplified implementation
        for (uint i = 0; i < stakedOperators.length; i++) {
            address operator = stakedOperators[i];
            if (keccak256(abi.encodePacked(operator)) == operatorId) {
                require(operatorStakes[operator].isActive, "Not registered");
                operatorStakes[operator].isActive = false;
                totalStake -= operatorStakes[operator].amount;
                emit OperatorDeregistered(operator);
                break;
            }
        }
    }
    
    function deregisterOperator(address operator, bytes32 operatorId) external {
        require(operatorStakes[operator].isActive, "Not registered");
        operatorStakes[operator].isActive = false;
        totalStake -= operatorStakes[operator].amount;
        emit OperatorDeregistered(operator);
    }

    function updateOperatorStake(
        address operator,
        bytes32 operatorId,
        uint96 stake
    ) external override {
        require(operatorStakes[operator].isActive, "Not registered");
        uint256 oldStake = operatorStakes[operator].amount;
        operatorStakes[operator].amount = stake;
        operatorStakes[operator].lastUpdateTime = block.timestamp;
        
        totalStake = totalStake - oldStake + stake;
        emit StakeUpdated(operator, stake);
    }

    function getCurrentStake(bytes32 operatorId, uint8 quorumNumber) 
        external view override returns (uint96) {
        // Simplified implementation - return first match
        for (uint i = 0; i < stakedOperators.length; i++) {
            address operator = stakedOperators[i];
            if (keccak256(abi.encodePacked(operator)) == operatorId) {
                return uint96(operatorStakes[operator].amount);
            }
        }
        return 0;
    }

    function getStakeAtBlockNumberAndIndex(
        uint8 quorumNumber,
        uint32 blockNumber,
        bytes32 operatorId,
        uint256 index
    ) external view override returns (uint96) {
        // Simplified implementation
        return this.getCurrentStake(operatorId, quorumNumber);
    }

    function getLatestStakeUpdate(bytes32 operatorId, uint8 quorumNumber)
        external view override returns (StakeUpdate memory) {
        // Simplified implementation
        uint96 stake = this.getCurrentStake(operatorId, quorumNumber);
        return StakeUpdate({
            updateBlockNumber: uint32(block.number),
            nextUpdateBlockNumber: 0,
            stake: stake
        });
    }

    function getStakeUpdateAtIndex(uint8 quorumNumber, bytes32 operatorId, uint256 index)
        external view override returns (StakeUpdate memory) {
        // Simplified implementation
        return this.getLatestStakeUpdate(operatorId, quorumNumber);
    }

    function getStakeHistoryLength(bytes32 operatorId, uint8 quorumNumber) 
        external view override returns (uint256) {
        // Simplified implementation
        return 1;
    }

    /**
     * @notice Reset state for testing
     * @dev Only for testing purposes
     */
    function resetForTesting() external {
        // Reset all operator states
        for (uint i = 0; i < stakedOperators.length; i++) {
            delete operatorStakes[stakedOperators[i]];
        }
        delete stakedOperators;
        totalStake = 0;
        totalSlashed = 0;
        totalRewards = 0;
    }
}
