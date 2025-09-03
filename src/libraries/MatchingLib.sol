// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IntentLib.sol";

library MatchingLib {
    using IntentLib for IntentLib.TradeIntent;

    struct MatchingPool {
        bytes32[] pendingIntents;
        mapping(bytes32 => IntentLib.TradeIntent) intents;
        mapping(bytes32 => uint256) intentIndex;
        uint256 totalIntents;
        uint256 lastCleanup;
    }

    struct MatchingResult {
        bytes32[] matchedIntents;
        bytes32[] unmatchedIntents;
        IntentLib.MatchedTrade[] trades;
        uint256 totalMatched;
        uint256 totalSavings;
        uint256 avgExecutionTime;
    }

    struct MatchingStats {
        uint256 totalIntentsProcessed;
        uint256 totalMatched;
        uint256 totalExecuted;
        uint256 totalSavings;
        uint256 avgMatchTime;
        uint256 successRate;
        uint256 lastUpdated;
    }

    event MatchingAttempted(
        uint256 indexed poolSize,
        uint256 matches,
        uint256 gasUsed
    );

    event IntentExpired(
        bytes32 indexed intentId,
        address indexed user
    );

    function addIntent(
        MatchingPool storage pool,
        IntentLib.TradeIntent memory intent
    ) internal returns (bool added) {
        if (!intent.isValidIntent()) {
            return false;
        }

        bytes32 intentId = intent.intentId;
        
        if (pool.intents[intentId].user != address(0)) {
            return false; // Already exists
        }

        pool.intents[intentId] = intent;
        pool.pendingIntents.push(intentId);
        pool.intentIndex[intentId] = pool.pendingIntents.length - 1;
        pool.totalIntents++;
        
        added = true;
    }

    function removeIntent(
        MatchingPool storage pool,
        bytes32 intentId
    ) internal returns (bool removed) {
        if (pool.intents[intentId].user == address(0)) {
            return false; // Does not exist
        }

        uint256 index = pool.intentIndex[intentId];
        uint256 lastIndex = pool.pendingIntents.length - 1;
        
        if (index != lastIndex) {
            bytes32 lastIntentId = pool.pendingIntents[lastIndex];
            pool.pendingIntents[index] = lastIntentId;
            pool.intentIndex[lastIntentId] = index;
        }
        
        pool.pendingIntents.pop();
        delete pool.intents[intentId];
        delete pool.intentIndex[intentId];
        
        removed = true;
    }

    function findMatches(
        MatchingPool storage pool,
        uint256 maxMatches
    ) internal returns (MatchingResult memory result) {
        uint256 poolSize = pool.pendingIntents.length;
        if (poolSize < 2) {
            return result;
        }

        bytes32[] memory matched = new bytes32[](poolSize);
        IntentLib.MatchedTrade[] memory trades = new IntentLib.MatchedTrade[](maxMatches);
        uint256 matchCount = 0;
        uint256 tradeCount = 0;

        for (uint256 i = 0; i < poolSize && tradeCount < maxMatches; i++) {
            bytes32 intentAId = pool.pendingIntents[i];
            IntentLib.TradeIntent storage intentA = pool.intents[intentAId];
            
            if (!intentA.isActive) continue;

            for (uint256 j = i + 1; j < poolSize && tradeCount < maxMatches; j++) {
                bytes32 intentBId = pool.pendingIntents[j];
                IntentLib.TradeIntent storage intentB = pool.intents[intentBId];
                
                if (!intentB.isActive) continue;

                if (intentA.canMatch(intentB)) {
                    (uint256 amountA, uint256 amountB, bool profitable) = 
                        intentA.calculateMatchAmounts(intentB);
                    
                    if (profitable) {
                        bytes32 tradeId = IntentLib.createTradeId(
                            intentAId,
                            intentBId,
                            block.timestamp
                        );

                        trades[tradeCount] = IntentLib.MatchedTrade({
                            tradeId: tradeId,
                            intentA: intentAId,
                            intentB: intentBId,
                            amountA: amountA,
                            amountB: amountB,
                            chainA: intentA.originChain,
                            chainB: intentB.originChain,
                            userA: intentA.user,
                            userB: intentB.user,
                            tokenA: intentA.tokenIn,
                            tokenB: intentB.tokenIn,
                            isExecuted: false,
                            executionTime: 0,
                            acrossDepositId: bytes32(0)
                        });

                        matched[matchCount++] = intentAId;
                        matched[matchCount++] = intentBId;
                        tradeCount++;

                        intentA.isActive = false;
                        intentB.isActive = false;
                        break;
                    }
                }
            }
        }

        // Resize arrays to actual count
        assembly {
            mstore(matched, matchCount)
            mstore(trades, tradeCount)
        }

        result.matchedIntents = matched;
        result.trades = trades;
        result.totalMatched = matchCount;
    }

    function cleanupExpiredIntents(
        MatchingPool storage pool
    ) internal returns (uint256 cleaned) {
        bytes32[] memory toRemove = new bytes32[](pool.pendingIntents.length);
        uint256 removeCount = 0;

        for (uint256 i = 0; i < pool.pendingIntents.length; i++) {
            bytes32 intentId = pool.pendingIntents[i];
            IntentLib.TradeIntent storage intent = pool.intents[intentId];
            
            if (intent.deadline <= block.timestamp || !intent.isActive) {
                toRemove[removeCount++] = intentId;
            }
        }

        for (uint256 i = 0; i < removeCount; i++) {
            removeIntent(pool, toRemove[i]);
            emit IntentExpired(toRemove[i], pool.intents[toRemove[i]].user);
        }

        pool.lastCleanup = block.timestamp;
        cleaned = removeCount;
    }

    function getPoolStats(
        MatchingPool storage pool
    ) internal view returns (
        uint256 totalIntents,
        uint256 activeIntents,
        uint256 avgAge
    ) {
        totalIntents = pool.totalIntents;
        activeIntents = pool.pendingIntents.length;
        
        if (activeIntents > 0) {
            uint256 totalAge = 0;
            for (uint256 i = 0; i < pool.pendingIntents.length; i++) {
                bytes32 intentId = pool.pendingIntents[i];
                IntentLib.TradeIntent storage intent = pool.intents[intentId];
                totalAge += block.timestamp - intent.createdAt;
            }
            avgAge = totalAge / activeIntents;
        }
    }
}