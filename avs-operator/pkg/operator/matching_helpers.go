package operator

import (
	"crypto/rand"
	"fmt"
	"math/big"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
)

// validateIntent validates a trade intent
func (me *MatchingEngine) validateIntent(intent *TradeIntent) error {
	if intent.IntentId == (common.Hash{}) {
		return fmt.Errorf("intent ID cannot be empty")
	}
	
	if intent.User == (common.Address{}) {
		return fmt.Errorf("user address cannot be empty")
	}
	
	if intent.TokenIn == (common.Address{}) {
		return fmt.Errorf("tokenIn cannot be empty")
	}
	
	if intent.TokenOut == (common.Address{}) {
		return fmt.Errorf("tokenOut cannot be empty")
	}
	
	if intent.TokenIn == intent.TokenOut {
		return fmt.Errorf("tokenIn and tokenOut cannot be the same")
	}
	
	if intent.AmountIn == nil || intent.AmountIn.Cmp(big.NewInt(0)) <= 0 {
		return fmt.Errorf("amountIn must be positive")
	}
	
	if intent.AmountOutMin == nil || intent.AmountOutMin.Cmp(big.NewInt(0)) <= 0 {
		return fmt.Errorf("amountOutMin must be positive")
	}
	
	if intent.Deadline < uint64(time.Now().Unix()) {
		return fmt.Errorf("intent deadline has passed")
	}
	
	if intent.OriginChain == 0 || intent.TargetChain == 0 {
		return fmt.Errorf("origin and target chains must be specified")
	}
	
	return nil
}

// areIntentsCompatible checks if two intents can potentially be matched
func (me *MatchingEngine) areIntentsCompatible(intentA, intentB *TradeIntent) bool {
	// Check expiration
	now := time.Now()
	if intentA.ExpiresAt.Before(now) || intentB.ExpiresAt.Before(now) {
		return false
	}
	
	// Check if users are different
	if intentA.User == intentB.User {
		return false
	}
	
	// Check if intents are complementary
	if intentA.TokenIn == intentB.TokenOut && intentA.TokenOut == intentB.TokenIn {
		return true
	}
	
	return false
}

// calculateMatchQuality calculates the quality of a potential match
func (me *MatchingEngine) calculateMatchQuality(intentA, intentB *TradeIntent) float64 {
	baseQuality := 0.5
	
	// Factors that improve match quality
	
	// 1. Amount compatibility
	amountRatio := me.calculateAmountRatio(intentA.AmountIn, intentB.AmountIn)
	if amountRatio > 0.8 && amountRatio < 1.2 {
		baseQuality += 0.2
	}
	
	// 2. Time proximity (newer intents are better)
	timeDiff := intentB.CreatedAt.Sub(intentA.CreatedAt).Minutes()
	if timeDiff < 5 { // Within 5 minutes
		baseQuality += 0.1
	}
	
	// 3. Same chain trades are slightly preferred for simplicity
	if intentA.OriginChain == intentB.OriginChain {
		baseQuality += 0.05
	}
	
	// 4. Cross-chain premium (encourage cross-chain adoption)
	if intentA.OriginChain != intentB.OriginChain || intentA.TargetChain != intentB.TargetChain {
		baseQuality += 0.1 // Cross-chain trades get quality bonus
	}
	
	// 5. AI enhancement if enabled
	if me.aiEngine.enabled {
		aiScore := me.getAIMatchScore(intentA, intentB)
		baseQuality = (baseQuality + aiScore) / 2
	}
	
	// Cap at 1.0
	if baseQuality > 1.0 {
		baseQuality = 1.0
	}
	
	return baseQuality
}

// calculateAmountRatio calculates ratio between two amounts
func (me *MatchingEngine) calculateAmountRatio(amountA, amountB *big.Int) float64 {
	if amountB.Cmp(big.NewInt(0)) == 0 {
		return 0
	}
	
	ratioFloat := new(big.Float).Quo(new(big.Float).SetInt(amountA), new(big.Float).SetInt(amountB))
	ratio, _ := ratioFloat.Float64()
	return ratio
}

// calculateMatchAmounts calculates the final amounts for a match
func (me *MatchingEngine) calculateMatchAmounts(intentA, intentB *TradeIntent) (*big.Int, *big.Int, *big.Int) {
	// Simplified pricing - use smaller amount for both
	amountA := new(big.Int).Set(intentA.AmountIn)
	amountB := new(big.Int).Set(intentB.AmountIn)
	
	// Use minimum of the two amounts
	if amountA.Cmp(amountB) > 0 {
		amountA.Set(amountB)
	} else {
		amountB.Set(amountA)
	}
	
	// Calculate estimated fees (simplified)
	estimatedFee := new(big.Int).Set(amountA)
	estimatedFee.Div(estimatedFee, big.NewInt(1000)) // 0.1% fee
	
	// Cross-chain trades have additional fees
	if intentA.OriginChain != intentB.OriginChain {
		crossChainFee := new(big.Int).Set(amountA)
		crossChainFee.Div(crossChainFee, big.NewInt(200)) // Additional 0.5% for cross-chain
		estimatedFee.Add(estimatedFee, crossChainFee)
	}
	
	return amountA, amountB, estimatedFee
}

// generateTradeId generates a unique trade ID for a match
func (me *MatchingEngine) generateTradeId(intentA, intentB *TradeIntent) common.Hash {
	data := append(intentA.IntentId.Bytes(), intentB.IntentId.Bytes()...)
	timestamp := make([]byte, 8)
	copy(timestamp, big.NewInt(time.Now().Unix()).Bytes())
	data = append(data, timestamp...)
	
	return crypto.Keccak256Hash(data)
}

// getAIMatchScore gets AI-powered match score
func (me *MatchingEngine) getAIMatchScore(intentA, intentB *TradeIntent) float64 {
	if !me.aiEngine.enabled {
		return 0.5 // Default neutral score
	}
	
	// Simplified AI scoring - in production, this would call ML model
	features := me.extractFeatures(intentA, intentB)
	
	// Mock AI scoring based on features
	score := 0.5
	
	// Volume compatibility
	volumeRatio := me.calculateAmountRatio(intentA.AmountIn, intentB.AmountIn)
	if volumeRatio > 0.8 && volumeRatio < 1.2 {
		score += 0.15
	}
	
	// Token popularity (mock)
	if me.isPopularToken(intentA.TokenIn) && me.isPopularToken(intentB.TokenIn) {
		score += 0.1
	}
	
	// Chain activity (mock)
	if me.isActiveChain(intentA.OriginChain) && me.isActiveChain(intentB.OriginChain) {
		score += 0.1
	}
	
	return score
}

// extractFeatures extracts features for AI processing
func (me *MatchingEngine) extractFeatures(intentA, intentB *TradeIntent) map[string]float64 {
	return map[string]float64{
		"volume_ratio":    me.calculateAmountRatio(intentA.AmountIn, intentB.AmountIn),
		"time_diff":       intentB.CreatedAt.Sub(intentA.CreatedAt).Minutes(),
		"chain_diff":      float64(intentA.OriginChain - intentB.OriginChain),
		"token_popularity": me.getTokenPopularityScore(intentA.TokenIn, intentB.TokenIn),
		"user_history":    me.getUserHistoryScore(intentA.User, intentB.User),
	}
}

// isPopularToken checks if a token is popular (mock implementation)
func (me *MatchingEngine) isPopularToken(token common.Address) bool {
	// In production, this would query actual token data
	popularTokens := map[string]bool{
		"0xA0b86a33e6441C4c27D3F50c9d6D14bDf12F4e6e": true, // USDC
		"0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2": true, // WETH
		"0x6B175474E89094C44Da98b954EedeAC495271d0F": true, // DAI
	}
	return popularTokens[token.Hex()]
}

// isActiveChain checks if a chain is active (mock implementation)
func (me *MatchingEngine) isActiveChain(chainId uint32) bool {
	activeChains := map[uint32]bool{
		1:     true, // Ethereum
		10:    true, // Optimism
		137:   true, // Polygon
		42161: true, // Arbitrum
		8453:  true, // Base
	}
	return activeChains[chainId]
}

// getTokenPopularityScore calculates token popularity score
func (me *MatchingEngine) getTokenPopularityScore(tokenA, tokenB common.Address) float64 {
	scoreA := 0.5
	scoreB := 0.5
	
	if me.isPopularToken(tokenA) {
		scoreA = 0.8
	}
	if me.isPopularToken(tokenB) {
		scoreB = 0.8
	}
	
	return (scoreA + scoreB) / 2
}

// getUserHistoryScore calculates user history score
func (me *MatchingEngine) getUserHistoryScore(userA, userB common.Address) float64 {
	// Mock implementation - in production, query user trading history
	return 0.5 // Neutral score
}

// findCircularMatches finds circular matches (3+ way trades)
func (me *MatchingEngine) findCircularMatches(ctx context.Context, excludeMatches []*MatchedTrade) []*CircularMatch {
	var circularMatches []*CircularMatch
	
	// Get excluded intent IDs
	excluded := make(map[common.Hash]bool)
	for _, match := range excludeMatches {
		excluded[match.IntentA] = true
		excluded[match.IntentB] = true
	}
	
	// Find 3-way circular matches
	me.intentPool.mutex.RLock()
	defer me.intentPool.mutex.RUnlock()
	
	var availableIntents []*TradeIntent
	for _, intent := range me.intentPool.intents {
		if !excluded[intent.IntentId] && intent.IsActive {
			availableIntents = append(availableIntents, intent)
		}
	}
	
	// Try to form circular matches
	for i := 0; i < len(availableIntents); i++ {
		for j := i + 1; j < len(availableIntents); j++ {
			for k := j + 1; k < len(availableIntents); k++ {
				if circular := me.evaluateCircularMatch(availableIntents[i], availableIntents[j], availableIntents[k]); circular != nil {
					circularMatches = append(circularMatches, circular)
					// Mark intents as used
					excluded[availableIntents[i].IntentId] = true
					excluded[availableIntents[j].IntentId] = true
					excluded[availableIntents[k].IntentId] = true
				}
			}
		}
	}
	
	return circularMatches
}

// evaluateCircularMatch evaluates if three intents can form a circular match
func (me *MatchingEngine) evaluateCircularMatch(intentA, intentB, intentC *TradeIntent) *CircularMatch {
	// Check if intents form a valid circle: A -> B -> C -> A
	if intentA.TokenOut != intentB.TokenIn ||
		intentB.TokenOut != intentC.TokenIn ||
		intentC.TokenOut != intentA.TokenIn {
		return nil
	}
	
	// Calculate circular match quality
	quality := me.calculateCircularQuality(intentA, intentB, intentC)
	if quality < me.config.MinMatchQuality {
		return nil
	}
	
	// Generate trade ID
	tradeId := me.generateCircularTradeId(intentA, intentB, intentC)
	
	return &CircularMatch{
		TradeId:      tradeId,
		Intents:      []common.Hash{intentA.IntentId, intentB.IntentId, intentC.IntentId},
		Users:        []common.Address{intentA.User, intentB.User, intentC.User},
		Tokens:       []common.Address{intentA.TokenIn, intentB.TokenIn, intentC.TokenIn},
		Amounts:      []*big.Int{intentA.AmountIn, intentB.AmountIn, intentC.AmountIn},
		Chains:       []uint32{intentA.OriginChain, intentB.OriginChain, intentC.OriginChain},
		MatchQuality: quality,
		EstimatedFee: me.calculateCircularFee(intentA, intentB, intentC),
		CreatedAt:    time.Now(),
	}
}

// calculateCircularQuality calculates quality for circular matches
func (me *MatchingEngine) calculateCircularQuality(intentA, intentB, intentC *TradeIntent) float64 {
	baseQuality := 0.4 // Circular matches are inherently more complex
	
	// Amount balance check
	totalIn := new(big.Int).Add(intentA.AmountIn, intentB.AmountIn)
	totalIn.Add(totalIn, intentC.AmountIn)
	avgAmount := new(big.Int).Div(totalIn, big.NewInt(3))
	
	// Check how balanced the amounts are
	balanceScore := 0.0
	for _, intent := range []*TradeIntent{intentA, intentB, intentC} {
		ratio := me.calculateAmountRatio(intent.AmountIn, avgAmount)
		if ratio > 0.7 && ratio < 1.3 {
			balanceScore += 0.1
		}
	}
	
	baseQuality += balanceScore
	
	// Cross-chain bonus
	chainSet := make(map[uint32]bool)
	chainSet[intentA.OriginChain] = true
	chainSet[intentB.OriginChain] = true
	chainSet[intentC.OriginChain] = true
	
	if len(chainSet) > 1 {
		baseQuality += 0.15 // Cross-chain circular bonus
	}
	
	return baseQuality
}

// calculateCircularFee calculates fees for circular matches
func (me *MatchingEngine) calculateCircularFee(intentA, intentB, intentC *TradeIntent) *big.Int {
	totalValue := new(big.Int).Add(intentA.AmountIn, intentB.AmountIn)
	totalValue.Add(totalValue, intentC.AmountIn)
	
	// Base fee: 0.15%
	fee := new(big.Int).Div(totalValue, big.NewInt(666))
	
	// Cross-chain additional fee
	chainSet := make(map[uint32]bool)
	chainSet[intentA.OriginChain] = true
	chainSet[intentB.OriginChain] = true
	chainSet[intentC.OriginChain] = true
	
	if len(chainSet) > 1 {
		crossChainFee := new(big.Int).Div(totalValue, big.NewInt(400)) // Additional 0.25%
		fee.Add(fee, crossChainFee)
	}
	
	return fee
}

// generateCircularTradeId generates ID for circular matches
func (me *MatchingEngine) generateCircularTradeId(intentA, intentB, intentC *TradeIntent) common.Hash {
	data := append(intentA.IntentId.Bytes(), intentB.IntentId.Bytes()...)
	data = append(data, intentC.IntentId.Bytes()...)
	
	timestamp := make([]byte, 8)
	copy(timestamp, big.NewInt(time.Now().Unix()).Bytes())
	data = append(data, timestamp...)
	
	// Add circular marker
	data = append(data, []byte("CIRCULAR")...)
	
	return crypto.Keccak256Hash(data)
}

// RemoveIntent removes an intent from the pool
func (me *MatchingEngine) RemoveIntent(intentId common.Hash) error {
	me.mutex.Lock()
	defer me.mutex.Unlock()
	
	me.intentPool.mutex.Lock()
	defer me.intentPool.mutex.Unlock()
	
	intent, exists := me.intentPool.intents[intentId]
	if !exists {
		return fmt.Errorf("intent not found: %s", intentId.Hex())
	}
	
	// Remove from main map
	delete(me.intentPool.intents, intentId)
	
	// Remove from indexes
	me.removeFromTokenIndex(intent)
	me.removeFromChainIndex(intent)
	me.removeFromUserIndex(intent)
	
	me.logger.Info("Removed intent from pool", "intentId", intentId.Hex())
	return nil
}

// Helper methods for index management
func (me *MatchingEngine) removeFromTokenIndex(intent *TradeIntent) {
	// Remove from tokenIn index
	if intents, exists := me.intentPool.byToken[intent.TokenIn]; exists {
		for i, existingIntent := range intents {
			if existingIntent.IntentId == intent.IntentId {
				me.intentPool.byToken[intent.TokenIn] = append(intents[:i], intents[i+1:]...)
				break
			}
		}
	}
	
	// Remove from tokenOut index
	if intents, exists := me.intentPool.byToken[intent.TokenOut]; exists {
		for i, existingIntent := range intents {
			if existingIntent.IntentId == intent.IntentId {
				me.intentPool.byToken[intent.TokenOut] = append(intents[:i], intents[i+1:]...)
				break
			}
		}
	}
}

func (me *MatchingEngine) removeFromChainIndex(intent *TradeIntent) {
	// Remove from origin chain index
	if intents, exists := me.intentPool.byChain[intent.OriginChain]; exists {
		for i, existingIntent := range intents {
			if existingIntent.IntentId == intent.IntentId {
				me.intentPool.byChain[intent.OriginChain] = append(intents[:i], intents[i+1:]...)
				break
			}
		}
	}
	
	// Remove from target chain index
	if intents, exists := me.intentPool.byChain[intent.TargetChain]; exists {
		for i, existingIntent := range intents {
			if existingIntent.IntentId == intent.IntentId {
				me.intentPool.byChain[intent.TargetChain] = append(intents[:i], intents[i+1:]...)
				break
			}
		}
	}
}

func (me *MatchingEngine) removeFromUserIndex(intent *TradeIntent) {
	if intents, exists := me.intentPool.byUser[intent.User]; exists {
		for i, existingIntent := range intents {
			if existingIntent.IntentId == intent.IntentId {
				me.intentPool.byUser[intent.User] = append(intents[:i], intents[i+1:]...)
				break
			}
		}
	}
}

// GetStats returns current matching statistics
func (me *MatchingEngine) GetStats() *MatchingStats {
	me.matchingStats.mutex.RLock()
	defer me.matchingStats.mutex.RUnlock()
	
	return &MatchingStats{
		TotalIntents:      me.matchingStats.TotalIntents,
		SuccessfulMatches: me.matchingStats.SuccessfulMatches,
		CrossChainMatches: me.matchingStats.CrossChainMatches,
		SameChainMatches:  me.matchingStats.SameChainMatches,
		FailedMatches:     me.matchingStats.FailedMatches,
		TotalVolume:       new(big.Int).Set(me.matchingStats.TotalVolume),
		AverageSavings:    new(big.Int).Set(me.matchingStats.AverageSavings),
	}
}