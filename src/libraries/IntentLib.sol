// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

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
        return keccak256(abi.encodePacked(user, poolId, amount, timestamp, salt));
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
               intent.user != address(0);
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
        if (intentA.amountIn <= intentB.amountOutMinimum &&
            intentB.amountIn <= intentA.amountOutMinimum) {
            amountA = intentA.amountIn;
            amountB = intentB.amountIn;
            isProfitable = true;
        }
    }
}