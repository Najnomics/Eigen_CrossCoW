// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IAcrossHubPool {
    struct RelayerRefundLeaf {
        uint256 amountToReturn;
        uint256 chainId;
        uint256[] refundAmounts;
        uint32 leafId;
        address l2TokenAddress;
        address[] refundAddresses;
    }

    struct PooledToken {
        address lpToken;
        bool isEnabled;
        uint32 lastLpFeeUpdate;
        int256 utilizedReserves;
        uint256 liquidReserves;
        uint256 undistributedLpFees;
    }

    // Events
    event FundsDeposited(
        uint256 amount,
        uint256 originChainId,
        uint256 destinationChainId,
        int64 relayerFeePct,
        uint32 indexed depositId,
        uint32 quoteTimestamp,
        address indexed depositor,
        address recipient,
        address indexed destinationToken,
        bytes message
    );

    event TokensBridged(
        uint256 amountToRelay,
        uint256 originChainId,
        uint256 destinationChainId,
        int64 relayerFeePct,
        uint32 indexed depositId,
        uint32 quoteTimestamp,
        address indexed depositor,
        address recipient,
        address destinationToken,
        address realizedLpFeePct,
        uint32 fillDeadline,
        uint32 exclusivityDeadline,
        address exclusiveRelayer,
        bytes message
    );

    // Core functions
    function depositV3(
        address depositor,
        address recipient,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId,
        address exclusiveRelayer,
        uint32 quoteTimestamp,
        uint32 fillDeadline,
        uint32 exclusivityDeadline,
        bytes calldata message
    ) external payable returns (uint32 depositId);

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
    ) external payable returns (uint32 depositId);

    function speedUpV3Deposit(
        address depositor,
        uint32 depositId,
        uint256 updatedOutputAmount,
        address updatedRecipient,
        bytes calldata updatedMessage
    ) external;

    function fillV3Relay(
        address depositor,
        address recipient,
        address exclusiveRelayer,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 originChainId,
        uint32 depositId,
        uint32 fillDeadline,
        uint32 exclusivityDeadline,
        bytes calldata message
    ) external;

    // Admin functions
    function enableL1TokenForLiquidityProvision(address l1Token) external;
    function disableL1TokenForLiquidityProvision(address l1Token) external;
    function addLiquidity(address l1Token, uint256 l1TokenAmount) external payable;
    function removeLiquidity(address l1Token, uint256 lpTokenAmount, bool sendEth) external;

    // View functions
    function pooledTokens(address token) external view returns (PooledToken memory);
    function getCurrentTime() external view returns (uint32);
    function liquidityUtilizationCurrent(address token) external view returns (uint256);
    function liquidityUtilizationPostRelay(address token, uint256 relayedAmount) external view returns (uint256);
    function sync(address l1Token) external;
}