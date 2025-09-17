// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Currency} from "@uniswap/v4-core/types/Currency.sol";
import {PoolId} from "@uniswap/v4-core/types/PoolId.sol";

library IntentLib {
    struct TradeIntent {
        bytes32 intentId;
        address user;
        PoolId poolId;
        Currency tokenIn;
        Currency tokenOut;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint256 deadline;
        uint32 originChain;
        uint32 targetChain;
        bool isActive;
        uint256 createdAt;
        bytes32 salt;
    }

    struct MatchedTrade {
        bytes32 tradeId;
        bytes32 intentA;
        bytes32 intentB;
        uint256 amountA;
        uint256 amountB;
        uint32 chainA;
        uint32 chainB;
        address userA;
        address userB;
        Currency tokenA;
        Currency tokenB;
        bool isExecuted;
        uint256 executionTime;
        bytes32 acrossDepositId;
    }

    struct IntentStatus {
        bool isMatched;
        bool isExecuted;
        bool isCancelled;
        bytes32 matchId;
        uint256 matchTime;
        uint256 executionTime;
        uint256 finalAmount;
    }

    event IntentCreated(
        bytes32 indexed intentId,
        address indexed user,
        PoolId indexed poolId,
        Currency tokenIn,
        Currency tokenOut,
        uint256 amountIn,
        uint32 originChain,
        uint32 targetChain
    );

    event IntentMatched(
        bytes32 indexed tradeId,
        bytes32 indexed intentA,
        bytes32 indexed intentB,
        uint256 amountA,
        uint256 amountB
    );

    event IntentExecuted(
        bytes32 indexed intentId,
        bytes32 indexed tradeId,
        uint256 finalAmount
    );

    event IntentCancelled(
        bytes32 indexed intentId,
        address indexed user
    );

    function createIntentId(
        address user,
        PoolId poolId,
        uint256 amount,
        uint256 timestamp,
        bytes32 salt
    ) internal pure returns (bytes32) {
        // CRITICAL FIX: Add block.number and more entropy to prevent replay attacks
        return keccak256(abi.encodePacked(
            user, 
            poolId, 
            amount, 
            timestamp,
            block.number,      // Adds block-specific entropy
            block.prevrandao,  // Additional entropy
            salt
        ));
    }
    
    function createIntentIdWithNonce(
        address user,
        PoolId poolId,
        uint256 amount,
        uint256 timestamp,
        uint256 nonce,
        bytes32 salt
    ) internal pure returns (bytes32) {
        // CRITICAL FIX: Use nonce for uniqueness and prevent replay attacks
        return keccak256(abi.encodePacked(
            user, 
            poolId, 
            amount, 
            timestamp,
            nonce,             // User-specific nonce for uniqueness
            block.number,      // Block-specific entropy
            block.prevrandao,  // Additional entropy
            salt
        ));
    }

    function createTradeId(
        bytes32 intentA,
        bytes32 intentB,
        uint256 timestamp
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(intentA, intentB, timestamp));
    }

    function isValidIntent(TradeIntent memory intent) internal view returns (bool) {
        return intent.isActive &&
               intent.deadline > block.timestamp &&
               intent.amountIn > 0 &&
               intent.amountOutMinimum > 0 &&
               intent.amountOutMinimum <= intent.amountIn && // Sanity check
               intent.user != address(0) &&
               Currency.unwrap(intent.tokenIn) != Currency.unwrap(intent.tokenOut); // Can't swap same token
    }

    function canMatch(
        TradeIntent memory intentA,
        TradeIntent memory intentB
    ) internal pure returns (bool) {
        return intentA.isActive &&
               intentB.isActive &&
               intentA.tokenOut == intentB.tokenIn &&
               intentA.tokenIn == intentB.tokenOut &&
               intentA.originChain == intentB.targetChain &&
               intentA.targetChain == intentB.originChain &&
               intentA.user != intentB.user;
    }

    function calculateMatchAmounts(
        TradeIntent memory intentA,
        TradeIntent memory intentB
    ) internal pure returns (uint256 amountA, uint256 amountB, bool isProfitable) {
        // CRITICAL FIX: Proper matching logic
        // IntentA wants to sell amountA.amountIn of tokenA for tokenB
        // IntentB wants to sell amountB.amountIn of tokenB for tokenA
        // They can match if:
        // 1. IntentA gets at least intentA.amountOutMinimum of tokenB
        // 2. IntentB gets at least intentB.amountOutMinimum of tokenA
        
        if (intentA.amountIn >= intentB.amountOutMinimum &&
            intentB.amountIn >= intentA.amountOutMinimum) {
            // Both parties can get at least their minimum required
            amountA = intentA.amountIn;
            amountB = intentB.amountIn;
            isProfitable = true;
        } else {
            // Try partial matching
            uint256 maxAmountA = intentB.amountOutMinimum;
            uint256 maxAmountB = intentA.amountOutMinimum;
            
            if (maxAmountA <= intentA.amountIn && maxAmountB <= intentB.amountIn) {
                amountA = maxAmountA;
                amountB = maxAmountB;
                isProfitable = true;
            }
        }
    }
}