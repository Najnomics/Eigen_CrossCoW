// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IAcrossHubPool.sol";
import "../libraries/IntentLib.sol";

contract AcrossIntegration is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    uint256 public constant MAX_UINT256 = type(uint256).max;
    uint256 public constant BASIS_POINTS = 10000;
    uint32 public constant DEFAULT_FILL_DEADLINE_BUFFER = 1800; // 30 minutes

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    IAcrossHubPool public immutable acrossHubPool;
    
    // Chain ID mappings
    mapping(uint32 => bool) public supportedChains;
    mapping(uint32 => address) public spokePoolAddresses;
    
    // Token mappings: sourceChain => sourceToken => destChain => destToken
    mapping(uint32 => mapping(address => mapping(uint32 => address))) public tokenMappings;
    
    // Fee configuration
    uint256 public protocolFeeBps = 10; // 0.1%
    mapping(uint32 => uint256) public maxRelayerFeeBps; // per chain
    
    // Execution tracking
    mapping(bytes32 => DepositInfo) public deposits;
    mapping(bytes32 => bool) public executedTrades;
    
    // Authorized callers
    mapping(address => bool) public authorizedCallers;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    struct DepositInfo {
        uint32 depositId;
        bytes32 tradeId;
        address depositor;
        address recipient;
        address inputToken;
        address outputToken;
        uint256 inputAmount;
        uint256 outputAmount;
        uint32 originChainId;
        uint32 destinationChainId;
        uint32 quoteTimestamp;
        uint32 fillDeadline;
        bool isCompleted;
        uint256 actualOutputAmount;
    }

    struct BridgeParams {
        address inputToken;
        address outputToken;
        uint256 inputAmount;
        uint256 outputAmount;
        uint32 destinationChainId;
        address recipient;
        uint32 fillDeadline;
        uint32 exclusivityDeadline;
        address exclusiveRelayer;
        bytes message;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event CrossChainTradeInitiated(
        bytes32 indexed tradeId,
        uint32 indexed depositId,
        address indexed depositor,
        address recipient,
        uint32 originChainId,
        uint32 destinationChainId,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    );
    
    event CrossChainTradeCompleted(
        bytes32 indexed tradeId,
        uint32 indexed depositId,
        uint256 actualOutputAmount,
        bool success
    );
    
    event ChainConfigured(
        uint32 indexed chainId,
        address spokePool,
        bool supported
    );
    
    event TokenMappingUpdated(
        uint32 indexed sourceChain,
        address indexed sourceToken,
        uint32 indexed destChain,
        address destToken
    );
    
    event ProtocolFeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);
    event CallerAuthorized(address indexed caller, bool authorized);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    modifier onlyAuthorized() {
        require(authorizedCallers[msg.sender] || msg.sender == owner(), "Unauthorized caller");
        _;
    }
    
    modifier validChain(uint32 chainId) {
        require(supportedChains[chainId], "Unsupported chain");
        _;
    }
    
    modifier validTokenMapping(uint32 sourceChain, address sourceToken, uint32 destChain) {
        require(
            tokenMappings[sourceChain][sourceToken][destChain] != address(0),
            "Invalid token mapping"
        );
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(IAcrossHubPool _acrossHubPool) Ownable(msg.sender) {
        acrossHubPool = _acrossHubPool;
        
        // Initialize common chain configurations
        _configureSupportedChains();
        _configureTokenMappings();
    }

    /*//////////////////////////////////////////////////////////////
                          EXECUTION FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function executeCrossChainTrade(
        IntentLib.MatchedTrade calldata trade,
        BridgeParams calldata bridgeParams
    ) external onlyAuthorized nonReentrant returns (uint32 depositId) {
        require(!executedTrades[trade.tradeId], "Trade already executed");
        
        // Validate trade parameters
        _validateTradeParams(trade, bridgeParams);
        
        // Mark trade as executed to prevent replay
        executedTrades[trade.tradeId] = true;
        
        // Handle token transfers and approvals
        _prepareTokenTransfers(bridgeParams);
        
        // Execute deposit via Across Hub Pool
        depositId = _executeAcrossDeposit(trade.tradeId, bridgeParams);
        
        // Store deposit information for tracking
        deposits[trade.tradeId] = DepositInfo({
            depositId: depositId,
            tradeId: trade.tradeId,
            depositor: msg.sender,
            recipient: bridgeParams.recipient,
            inputToken: bridgeParams.inputToken,
            outputToken: bridgeParams.outputToken,
            inputAmount: bridgeParams.inputAmount,
            outputAmount: bridgeParams.outputAmount,
            originChainId: uint32(block.chainid),
            destinationChainId: bridgeParams.destinationChainId,
            quoteTimestamp: uint32(block.timestamp),
            fillDeadline: bridgeParams.fillDeadline,
            isCompleted: false,
            actualOutputAmount: 0
        });
        
        emit CrossChainTradeInitiated(
            trade.tradeId,
            depositId,
            msg.sender,
            bridgeParams.recipient,
            uint32(block.chainid),
            bridgeParams.destinationChainId,
            bridgeParams.inputToken,
            bridgeParams.outputToken,
            bridgeParams.inputAmount,
            bridgeParams.outputAmount
        );
        
        return depositId;
    }
    
    function _executeAcrossDeposit(
        bytes32 tradeId,
        BridgeParams memory params
    ) internal returns (uint32 depositId) {
        
        // Calculate protocol fee
        uint256 protocolFee = (params.inputAmount * protocolFeeBps) / BASIS_POINTS;
        uint256 netInputAmount = params.inputAmount - protocolFee;
        
        // Call Across Hub Pool deposit function
        try acrossHubPool.depositV3{value: params.inputToken == address(0) ? netInputAmount : 0}(
            address(this), // depositor
            params.recipient,
            params.inputToken,
            params.outputToken,
            netInputAmount,
            params.outputAmount,
            params.destinationChainId,
            params.exclusiveRelayer,
            uint32(block.timestamp),
            params.fillDeadline,
            params.exclusivityDeadline,
            params.message
        ) returns (uint32 _depositId) {
            depositId = _depositId;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Across deposit failed: ", reason)));
        } catch {
            revert("Across deposit failed with unknown error");
        }
        
        // Transfer protocol fee to treasury (if any)
        if (protocolFee > 0) {
            _transferProtocolFee(params.inputToken, protocolFee);
        }
    }
    
    function _prepareTokenTransfers(BridgeParams memory params) internal {
        if (params.inputToken == address(0)) {
            // ETH deposit
            require(msg.value >= params.inputAmount, "Insufficient ETH");
        } else {
            // ERC20 token deposit
            IERC20 token = IERC20(params.inputToken);
            
            // Transfer tokens from caller
            token.safeTransferFrom(msg.sender, address(this), params.inputAmount);
            
            // Approve Across Hub Pool for spending
            if (token.allowance(address(this), address(acrossHubPool)) < params.inputAmount) {
                token.forceApprove(address(acrossHubPool), MAX_UINT256);
            }
        }
    }
    
    function _transferProtocolFee(address token, uint256 amount) internal {
        if (amount == 0) return;
        
        if (token == address(0)) {
            // ETH fee
            payable(owner()).transfer(amount);
        } else {
            // ERC20 fee
            IERC20(token).safeTransfer(owner(), amount);
        }
    }

    /*//////////////////////////////////////////////////////////////
                         VALIDATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _validateTradeParams(
        IntentLib.MatchedTrade calldata trade,
        BridgeParams calldata params
    ) internal view {
        require(trade.isExecuted == false, "Trade already marked as executed");
        require(params.inputAmount > 0, "Invalid input amount");
        require(params.outputAmount > 0, "Invalid output amount");
        require(params.recipient != address(0), "Invalid recipient");
        require(params.fillDeadline > block.timestamp + 300, "Fill deadline too soon"); // At least 5 minutes
        
        // Validate chain support
        require(supportedChains[params.destinationChainId], "Destination chain not supported");
        
        // Validate token mapping
        require(
            tokenMappings[uint32(block.chainid)][params.inputToken][params.destinationChainId] == params.outputToken,
            "Invalid token mapping"
        );
        
        // Validate fee limits
        uint256 impliedFeeBps = ((params.inputAmount - params.outputAmount) * BASIS_POINTS) / params.inputAmount;
        require(impliedFeeBps <= maxRelayerFeeBps[params.destinationChainId], "Fee exceeds maximum");
    }

    /*//////////////////////////////////////////////////////////////
                           CALLBACK FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    // This would be called by a monitoring service or relayer when fill is confirmed
    function confirmTradeCompletion(
        bytes32 tradeId,
        uint32 depositId,
        uint256 actualOutputAmount,
        bool success
    ) external onlyAuthorized {
        DepositInfo storage deposit = deposits[tradeId];
        require(deposit.depositId == depositId, "Deposit ID mismatch");
        require(!deposit.isCompleted, "Trade already confirmed");
        
        deposit.isCompleted = true;
        deposit.actualOutputAmount = actualOutputAmount;
        
        emit CrossChainTradeCompleted(tradeId, depositId, actualOutputAmount, success);
    }

    /*//////////////////////////////////////////////////////////////
                        CONFIGURATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function configureChain(
        uint32 chainId,
        address spokePool,
        bool supported,
        uint256 maxFeeBps
    ) external onlyOwner {
        supportedChains[chainId] = supported;
        spokePoolAddresses[chainId] = spokePool;
        maxRelayerFeeBps[chainId] = maxFeeBps;
        
        emit ChainConfigured(chainId, spokePool, supported);
    }
    
    function setTokenMapping(
        uint32 sourceChain,
        address sourceToken,
        uint32 destChain,
        address destToken
    ) external onlyOwner validChain(sourceChain) validChain(destChain) {
        tokenMappings[sourceChain][sourceToken][destChain] = destToken;
        
        emit TokenMappingUpdated(sourceChain, sourceToken, destChain, destToken);
    }
    
    function setProtocolFee(uint256 newFeeBps) external onlyOwner {
        require(newFeeBps <= 100, "Fee too high"); // Max 1%
        uint256 oldFeeBps = protocolFeeBps;
        protocolFeeBps = newFeeBps;
        
        emit ProtocolFeeUpdated(oldFeeBps, newFeeBps);
    }
    
    function authorizeCaller(address caller, bool authorized) external onlyOwner {
        authorizedCallers[caller] = authorized;
        emit CallerAuthorized(caller, authorized);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function getDepositInfo(bytes32 tradeId) external view returns (DepositInfo memory) {
        return deposits[tradeId];
    }
    
    function getTokenMapping(
        uint32 sourceChain,
        address sourceToken,
        uint32 destChain
    ) external view returns (address) {
        return tokenMappings[sourceChain][sourceToken][destChain];
    }
    
    function isTradeExecuted(bytes32 tradeId) external view returns (bool) {
        return executedTrades[tradeId];
    }
    
    function calculateProtocolFee(uint256 amount) external view returns (uint256) {
        return (amount * protocolFeeBps) / BASIS_POINTS;
    }

    /*//////////////////////////////////////////////////////////////
                          EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function emergencyWithdraw(address token, address to, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            payable(to).transfer(amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL CONFIGURATION
    //////////////////////////////////////////////////////////////*/
    
    function _configureSupportedChains() internal {
        // Ethereum Mainnet
        supportedChains[1] = true;
        maxRelayerFeeBps[1] = 500; // 5%
        
        // Optimism
        supportedChains[10] = true;
        maxRelayerFeeBps[10] = 300; // 3%
        
        // Arbitrum One
        supportedChains[42161] = true;
        maxRelayerFeeBps[42161] = 300; // 3%
        
        // Base
        supportedChains[8453] = true;
        maxRelayerFeeBps[8453] = 300; // 3%
        
        // Polygon
        supportedChains[137] = true;
        maxRelayerFeeBps[137] = 400; // 4%
    }
    
    function _configureTokenMappings() internal {
        // USDC mappings
        address USDC_MAINNET = 0xA0b86a33e6441C4c27D3F50c9d6D14bDf12F4e6e;
        address USDC_OPTIMISM = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
        address USDC_ARBITRUM = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
        address USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        address USDC_POLYGON = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
        
        // Ethereum -> L2s
        tokenMappings[1][USDC_MAINNET][10] = USDC_OPTIMISM;
        tokenMappings[1][USDC_MAINNET][42161] = USDC_ARBITRUM;
        tokenMappings[1][USDC_MAINNET][8453] = USDC_BASE;
        tokenMappings[1][USDC_MAINNET][137] = USDC_POLYGON;
        
        // L2s -> Ethereum
        tokenMappings[10][USDC_OPTIMISM][1] = USDC_MAINNET;
        tokenMappings[42161][USDC_ARBITRUM][1] = USDC_MAINNET;
        tokenMappings[8453][USDC_BASE][1] = USDC_MAINNET;
        tokenMappings[137][USDC_POLYGON][1] = USDC_MAINNET;
        
        // Inter-L2 mappings
        tokenMappings[10][USDC_OPTIMISM][42161] = USDC_ARBITRUM;
        tokenMappings[42161][USDC_ARBITRUM][10] = USDC_OPTIMISM;
        tokenMappings[10][USDC_OPTIMISM][8453] = USDC_BASE;
        tokenMappings[8453][USDC_BASE][10] = USDC_OPTIMISM;
    }
    
    receive() external payable {}
}