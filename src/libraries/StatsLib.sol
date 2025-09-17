// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

library StatsLib {
    struct PoolStats {
        uint256 totalIntents;
        uint256 matchedIntents;
        uint256 executedTrades;
        uint256 totalVolume;
        uint256 totalSavings;
        uint256 avgMatchTime;
        uint256 avgExecutionTime;
        uint256 lastUpdated;
    }

    struct UserStats {
        uint256 totalIntents;
        uint256 matchedIntents;
        uint256 totalVolume;
        uint256 totalSavings;
        uint256 avgSavings;
        uint256 lastActivity;
        uint256 successRate;
    }

    struct GlobalStats {
        uint256 totalPools;
        uint256 totalUsers;
        uint256 totalIntents;
        uint256 totalMatched;
        uint256 totalExecuted;
        uint256 totalVolume;
        uint256 totalSavings;
        uint256 totalMevSaved;
        uint256 avgMatchTime;
        uint256 successRate;
        uint256 lastUpdated;
    }

    struct TimeWindowStats {
        uint256 intents;
        uint256 matches;
        uint256 volume;
        uint256 savings;
        uint256 windowStart;
        uint256 windowEnd;
    }

    event StatsUpdated(
        bytes32 indexed statType,
        bytes32 indexed identifier,
        uint256 value,
        uint256 timestamp
    );

    function updatePoolStats(
        PoolStats storage stats,
        uint256 newIntents,
        uint256 newMatches,
        uint256 newVolume,
        uint256 newSavings,
        uint256 matchTime,
        uint256 executionTime
    ) internal {
        stats.totalIntents += newIntents;
        stats.matchedIntents += newMatches;
        if (newMatches > 0) {
            stats.executedTrades += newMatches / 2; // Each match creates one trade
        }
        stats.totalVolume += newVolume;
        stats.totalSavings += newSavings;
        
        // Update averages using weighted moving average
        if (stats.avgMatchTime == 0) {
            stats.avgMatchTime = matchTime;
        } else {
            stats.avgMatchTime = (stats.avgMatchTime * 9 + matchTime) / 10;
        }
        
        if (stats.avgExecutionTime == 0) {
            stats.avgExecutionTime = executionTime;
        } else {
            stats.avgExecutionTime = (stats.avgExecutionTime * 9 + executionTime) / 10;
        }
        
        stats.lastUpdated = block.timestamp;
        
        emit StatsUpdated("pool", keccak256("update"), newVolume, block.timestamp);
    }

    function updateUserStats(
        UserStats storage stats,
        uint256 newIntents,
        uint256 newMatches,
        uint256 newVolume,
        uint256 newSavings
    ) internal {
        stats.totalIntents += newIntents;
        stats.matchedIntents += newMatches;
        stats.totalVolume += newVolume;
        stats.totalSavings += newSavings;
        
        // Update average savings
        if (stats.matchedIntents > 0) {
            stats.avgSavings = stats.totalSavings / stats.matchedIntents;
            stats.successRate = (stats.matchedIntents * 10000) / stats.totalIntents;
        }
        
        stats.lastActivity = block.timestamp;
        
        emit StatsUpdated("user", keccak256(abi.encodePacked(msg.sender)), newVolume, block.timestamp);
    }

    function updateGlobalStats(
        GlobalStats storage stats,
        uint256 newPools,
        uint256 newUsers,
        uint256 newIntents,
        uint256 newMatches,
        uint256 newVolume,
        uint256 newSavings,
        uint256 mevSaved,
        uint256 matchTime
    ) internal {
        stats.totalPools += newPools;
        stats.totalUsers += newUsers;
        stats.totalIntents += newIntents;
        stats.totalMatched += newMatches;
        if (newMatches > 0) {
            stats.totalExecuted += newMatches / 2;
        }
        stats.totalVolume += newVolume;
        stats.totalSavings += newSavings;
        stats.totalMevSaved += mevSaved;
        
        // Update averages
        if (stats.avgMatchTime == 0) {
            stats.avgMatchTime = matchTime;
        } else {
            stats.avgMatchTime = (stats.avgMatchTime * 9 + matchTime) / 10;
        }
        
        if (stats.totalIntents > 0) {
            stats.successRate = (stats.totalMatched * 10000) / stats.totalIntents;
        }
        
        stats.lastUpdated = block.timestamp;
        
        emit StatsUpdated("global", bytes32(0), newVolume, block.timestamp);
    }

    function getSuccessRate(
        uint256 totalIntents,
        uint256 matchedIntents
    ) internal pure returns (uint256) {
        if (totalIntents == 0) return 0;
        return (matchedIntents * 10000) / totalIntents; // Basis points
    }

    function calculateSavings(
        uint256 originalGasCost,
        uint256 optimizedGasCost,
        uint256 bridgeFeesSaved,
        uint256 slippageSaved
    ) internal pure returns (uint256 totalSavings) {
        totalSavings = originalGasCost > optimizedGasCost ? 
            originalGasCost - optimizedGasCost : 0;
        totalSavings += bridgeFeesSaved + slippageSaved;
    }

    function calculateMevSaved(
        uint256 tradeVolume,
        uint256 avgMevRate
    ) internal pure returns (uint256) {
        return (tradeVolume * avgMevRate) / 10000; // avgMevRate in basis points
    }

    function getTimeWindowStats(
        TimeWindowStats[] storage windows,
        uint256 windowDuration
    ) internal view returns (TimeWindowStats memory current) {
        uint256 currentWindow = block.timestamp / windowDuration;
        uint256 windowStart = currentWindow * windowDuration;
        
        for (uint256 i = 0; i < windows.length; i++) {
            if (windows[i].windowStart == windowStart) {
                return windows[i];
            }
        }
        
        // Return empty stats if window not found
        current = TimeWindowStats({
            intents: 0,
            matches: 0,
            volume: 0,
            savings: 0,
            windowStart: windowStart,
            windowEnd: windowStart + windowDuration
        });
    }

    function updateTimeWindowStats(
        TimeWindowStats[] storage windows,
        uint256 windowDuration,
        uint256 intents,
        uint256 matches,
        uint256 volume,
        uint256 savings
    ) internal {
        uint256 currentWindow = block.timestamp / windowDuration;
        uint256 windowStart = currentWindow * windowDuration;
        
        bool found = false;
        for (uint256 i = 0; i < windows.length; i++) {
            if (windows[i].windowStart == windowStart) {
                windows[i].intents += intents;
                windows[i].matches += matches;
                windows[i].volume += volume;
                windows[i].savings += savings;
                found = true;
                break;
            }
        }
        
        if (!found) {
            windows.push(TimeWindowStats({
                intents: intents,
                matches: matches,
                volume: volume,
                savings: savings,
                windowStart: windowStart,
                windowEnd: windowStart + windowDuration
            }));
        }
    }
}