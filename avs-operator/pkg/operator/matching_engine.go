package operator

import (
	"context"
	"fmt"
	"math/big"
	"time"

	"github.com/Layr-Labs/eigensdk-go/logging"
	"github.com/ethereum/go-ethereum/common"
	"github.com/eigencrosscow/avs/contracts/bindings/CrossCoWTaskManager"
)

type MatchingEngine struct {
	config         Config
	logger         logging.Logger
	aiEngine       *AIMatchingEngine
	intentPool     *IntentPool
	matchingStats  *MatchingStats
}

type AIMatchingEngine struct {
	enabled    bool
	modelPath  string
	threshold  float64
	features   []string
}

type IntentPool struct {
	intents    map[common.Hash]*TradeIntent
	byToken    map[common.Address][]*TradeIntent
	byChain    map[uint32][]*TradeIntent
	byUser     map[common.Address][]*TradeIntent
}

type TradeIntent struct {
	IntentId        common.Hash    `json:"intentId"`
	User            common.Address `json:"user"`
	PoolId          common.Hash    `json:"poolId"`
	TokenIn         common.Address `json:"tokenIn"`
	TokenOut        common.Address `json:"tokenOut"`
	AmountIn        *big.Int       `json:"amountIn"`
	AmountOutMin    *big.Int       `json:"amountOutMin"`
	Deadline        uint64         `json:"deadline"`
	OriginChain     uint32         `json:"originChain"`
	TargetChain     uint32         `json:"targetChain"`
	IsActive        bool           `json:"isActive"`
	CreatedAt       time.Time      `json:"createdAt"`
	Salt            common.Hash    `json:"salt"`
}

type MatchingStats struct {
	TotalIntents    uint64
	MatchedIntents  uint64
	ExecutedTrades  uint64
	TotalSavings    *big.Int
	AvgMatchTime    time.Duration
	SuccessRate     float64
}

type MatchingResult struct {
	TradeA          *TradeIntent
	TradeB          *TradeIntent
	MatchScore      float64
	EstimatedSaving *big.Int
	Confidence      float64
}

func NewMatchingEngine(config Config, logger logging.Logger) (*MatchingEngine, error) {
	logger = logger.With("component", "matching-engine")
	
	aiEngine := &AIMatchingEngine{
		enabled:   config.EnableAIMatching,
		threshold: 0.8, // 80% confidence threshold
		features: []string{
			"token_pair_compatibility",
			"chain_compatibility", 
			"amount_compatibility",
			"timing_compatibility",
			"user_history_score",
			"liquidity_score",
		},
	}
	
	intentPool := &IntentPool{
		intents: make(map[common.Hash]*TradeIntent),
		byToken: make(map[common.Address][]*TradeIntent),
		byChain: make(map[uint32][]*TradeIntent),
		byUser:  make(map[common.Address][]*TradeIntent),
	}
	
	matchingStats := &MatchingStats{
		TotalSavings: big.NewInt(0),
	}
	
	return &MatchingEngine{
		config:        config,
		logger:        logger,
		aiEngine:      aiEngine,
		intentPool:    intentPool,
		matchingStats: matchingStats,
	}, nil
}

func (me *MatchingEngine) Start(ctx context.Context) {
	me.logger.Info("Starting AI-powered matching engine")
	
	// Start periodic matching
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()
	
	// Start intent cleanup
	cleanupTicker := time.NewTicker(60 * time.Second)
	defer cleanupTicker.Stop()
	
	for {
		select {
		case <-ctx.Done():
			me.logger.Info("Stopping matching engine")
			return
		case <-ticker.C:
			me.runMatchingCycle()
		case <-cleanupTicker.C:
			me.cleanupExpiredIntents()
		}
	}
}

func (me *MatchingEngine) AddIntent(intent *TradeIntent) error {
	if !me.validateIntent(intent) {
		return fmt.Errorf("invalid intent: %s", intent.IntentId.Hex())
	}
	
	// Add to main pool
	me.intentPool.intents[intent.IntentId] = intent
	
	// Add to indexes for efficient lookup
	me.intentPool.byToken[intent.TokenIn] = append(me.intentPool.byToken[intent.TokenIn], intent)
	me.intentPool.byChain[intent.OriginChain] = append(me.intentPool.byChain[intent.OriginChain], intent)
	me.intentPool.byUser[intent.User] = append(me.intentPool.byUser[intent.User], intent)
	
	me.matchingStats.TotalIntents++
	
	me.logger.Info("Added intent to matching pool",
		"intentId", intent.IntentId.Hex(),
		"user", intent.User.Hex(),
		"tokenIn", intent.TokenIn.Hex(),
		"tokenOut", intent.TokenOut.Hex(),
		"amount", intent.AmountIn.String(),
		"originChain", intent.OriginChain,
		"targetChain", intent.TargetChain,
	)
	
	return nil
}

func (me *MatchingEngine) runMatchingCycle() {
	startTime := time.Now()
	
	matches := me.findMatches()
	
	if len(matches) > 0 {
		me.logger.Info("Found potential matches", "count", len(matches))
		
		for _, match := range matches {
			if me.aiEngine.enabled {
				// Use AI to validate and score the match
				if me.validateMatchWithAI(match) {
					me.processMatch(match)
				}
			} else {
				// Use simple rule-based matching
				if me.validateMatchRules(match) {
					me.processMatch(match)
				}
			}
		}
	}
	
	matchingTime := time.Since(startTime)
	me.matchingStats.AvgMatchTime = matchingTime
	
	if len(matches) > 0 {
		me.logger.Debug("Matching cycle completed",
			"duration", matchingTime,
			"potentialMatches", len(matches),
			"totalIntents", len(me.intentPool.intents),
		)
	}
}

func (me *MatchingEngine) findMatches() []*MatchingResult {
	var matches []*MatchingResult
	
	// Get all active intents
	var intents []*TradeIntent
	for _, intent := range me.intentPool.intents {
		if intent.IsActive && intent.Deadline > uint64(time.Now().Unix()) {
			intents = append(intents, intent)
		}
	}
	
	// Find potential matches using nested loop (O(n²) - can be optimized)
	for i := 0; i < len(intents); i++ {
		for j := i + 1; j < len(intents); j++ {
			intentA := intents[i]
			intentB := intents[j]
			
			if me.canMatch(intentA, intentB) {
				matchScore := me.calculateMatchScore(intentA, intentB)
				if matchScore > 0.5 { // Basic threshold
					matches = append(matches, &MatchingResult{
						TradeA:     intentA,
						TradeB:     intentB,
						MatchScore: matchScore,
						EstimatedSaving: me.calculateEstimatedSavings(intentA, intentB),
						Confidence: matchScore,
					})
				}
			}
		}
	}
	
	return matches
}

func (me *MatchingEngine) canMatch(intentA, intentB *TradeIntent) bool {
	// Basic matching criteria
	return intentA.IsActive &&
		   intentB.IsActive &&
		   intentA.User != intentB.User &&
		   intentA.TokenOut == intentB.TokenIn &&
		   intentA.TokenIn == intentB.TokenOut &&
		   intentA.OriginChain == intentB.TargetChain &&
		   intentA.TargetChain == intentB.OriginChain
}

func (me *MatchingEngine) calculateMatchScore(intentA, intentB *TradeIntent) float64 {
	score := 0.0
	
	// Token compatibility (30%)
	if intentA.TokenOut == intentB.TokenIn && intentA.TokenIn == intentB.TokenOut {
		score += 0.3
	}
	
	// Chain compatibility (25%)
	if intentA.OriginChain == intentB.TargetChain && intentA.TargetChain == intentB.OriginChain {
		score += 0.25
	}
	
	// Amount compatibility (25%)
	amountRatio := me.calculateAmountCompatibility(intentA.AmountIn, intentB.AmountIn)
	score += 0.25 * amountRatio
	
	// Timing compatibility (20%)
	timingScore := me.calculateTimingCompatibility(intentA.Deadline, intentB.Deadline)
	score += 0.2 * timingScore
	
	return score
}

func (me *MatchingEngine) calculateAmountCompatibility(amountA, amountB *big.Int) float64 {
	if amountA.Cmp(big.NewInt(0)) == 0 || amountB.Cmp(big.NewInt(0)) == 0 {
		return 0.0
	}
	
	// Calculate ratio and normalize to 0-1 range
	var ratio *big.Float
	if amountA.Cmp(amountB) > 0 {
		ratio = new(big.Float).Quo(new(big.Float).SetInt(amountB), new(big.Float).SetInt(amountA))
	} else {
		ratio = new(big.Float).Quo(new(big.Float).SetInt(amountA), new(big.Float).SetInt(amountB))
	}
	
	ratioFloat, _ := ratio.Float64()
	return ratioFloat
}

func (me *MatchingEngine) calculateTimingCompatibility(deadlineA, deadlineB uint64) float64 {
	now := uint64(time.Now().Unix())
	
	// Both should have reasonable time left
	timeLeftA := deadlineA - now
	timeLeftB := deadlineB - now
	
	if timeLeftA < 60 || timeLeftB < 60 { // Less than 1 minute
		return 0.0
	}
	
	// Prefer matches where both have similar time left
	timeDiff := int64(timeLeftA) - int64(timeLeftB)
	if timeDiff < 0 {
		timeDiff = -timeDiff
	}
	
	// Normalize: closer deadlines get higher score
	if timeDiff < 60 { // Within 1 minute
		return 1.0
	} else if timeDiff < 300 { // Within 5 minutes
		return 0.8
	} else if timeDiff < 900 { // Within 15 minutes
		return 0.6
	} else {
		return 0.4
	}
}

func (me *MatchingEngine) calculateEstimatedSavings(intentA, intentB *TradeIntent) *big.Int {
	// Simplified savings calculation
	// In practice, this would consider:
	// - Gas fees saved by avoiding individual swaps
	// - Bridge fees saved by matching cross-chain
	// - Slippage reduction
	// - MEV protection value
	
	totalVolume := new(big.Int).Add(intentA.AmountIn, intentB.AmountIn)
	
	// Estimate 1% savings on total volume
	savings := new(big.Int).Div(totalVolume, big.NewInt(100))
	
	return savings
}

func (me *MatchingEngine) validateMatchWithAI(match *MatchingResult) bool {
	if !me.aiEngine.enabled {
		return false
	}
	
	// Extract features for AI model
	features := me.extractMatchFeatures(match)
	
	// Run AI model prediction (placeholder)
	prediction := me.runAIPrediction(features)
	
	return prediction.Confidence > me.aiEngine.threshold
}

func (me *MatchingEngine) validateMatchRules(match *MatchingResult) bool {
	// Simple rule-based validation
	return match.MatchScore > 0.7 && // High match score
		   match.EstimatedSaving.Cmp(big.NewInt(0)) > 0 && // Positive savings
		   match.TradeA.Deadline > uint64(time.Now().Unix())+60 && // At least 1 minute left
		   match.TradeB.Deadline > uint64(time.Now().Unix())+60
}

func (me *MatchingEngine) processMatch(match *MatchingResult) {
	me.logger.Info("Processing matched trades",
		"intentA", match.TradeA.IntentId.Hex(),
		"intentB", match.TradeB.IntentId.Hex(),
		"matchScore", match.MatchScore,
		"estimatedSaving", match.EstimatedSaving.String(),
	)
	
	// Mark intents as matched (remove from active pool)
	match.TradeA.IsActive = false
	match.TradeB.IsActive = false
	
	// Create matched trade for execution
	matchedTrade := MatchedTrade{
		TradeId:     common.BytesToHash([]byte(fmt.Sprintf("%s_%s", match.TradeA.IntentId.Hex(), match.TradeB.IntentId.Hex()))),
		IntentA:     match.TradeA.IntentId,
		IntentB:     match.TradeB.IntentId,
		AmountA:     match.TradeA.AmountIn,
		AmountB:     match.TradeB.AmountIn,
		ChainA:      match.TradeA.OriginChain,
		ChainB:      match.TradeB.OriginChain,
		UserA:       match.TradeA.User,
		UserB:       match.TradeB.User,
		TokenA:      match.TradeA.TokenIn,
		TokenB:      match.TradeB.TokenIn,
		IsExecuted:  false,
		ExecutionTime: 0,
	}
	
	// Update stats
	me.matchingStats.MatchedIntents += 2
	me.matchingStats.TotalSavings.Add(me.matchingStats.TotalSavings, match.EstimatedSaving)
	me.matchingStats.SuccessRate = float64(me.matchingStats.MatchedIntents) / float64(me.matchingStats.TotalIntents)
	
	me.logger.Info("Successfully matched trades for execution",
		"tradeId", matchedTrade.TradeId.Hex(),
		"userA", matchedTrade.UserA.Hex(),
		"userB", matchedTrade.UserB.Hex(),
		"chainA", matchedTrade.ChainA,
		"chainB", matchedTrade.ChainB,
	)
}

func (me *MatchingEngine) cleanupExpiredIntents() {
	now := uint64(time.Now().Unix())
	expiredCount := 0
	
	for intentId, intent := range me.intentPool.intents {
		if intent.Deadline <= now {
			// Remove expired intent
			delete(me.intentPool.intents, intentId)
			expiredCount++
			
			// Remove from indexes (simplified - would need proper cleanup)
			me.removeFromIndexes(intent)
		}
	}
	
	if expiredCount > 0 {
		me.logger.Info("Cleaned up expired intents", "count", expiredCount)
	}
}

func (me *MatchingEngine) removeFromIndexes(intent *TradeIntent) {
	// Remove from token index
	if intents, exists := me.intentPool.byToken[intent.TokenIn]; exists {
		for i, existing := range intents {
			if existing.IntentId == intent.IntentId {
				me.intentPool.byToken[intent.TokenIn] = append(intents[:i], intents[i+1:]...)
				break
			}
		}
	}
	
	// Similar cleanup for other indexes...
}

func (me *MatchingEngine) validateIntent(intent *TradeIntent) bool {
	return intent.User != common.Address{} &&
		   intent.TokenIn != common.Address{} &&
		   intent.TokenOut != common.Address{} &&
		   intent.AmountIn.Cmp(big.NewInt(0)) > 0 &&
		   intent.Deadline > uint64(time.Now().Unix()) &&
		   intent.IsActive
}

// AI-related functions (placeholder implementations)
func (me *MatchingEngine) extractMatchFeatures(match *MatchingResult) []float64 {
	return []float64{
		match.MatchScore,
		float64(match.TradeA.OriginChain),
		float64(match.TradeB.OriginChain),
		// Add more features...
	}
}

type AIPrediction struct {
	Confidence float64
	Score      float64
}

func (me *MatchingEngine) runAIPrediction(features []float64) AIPrediction {
	// Placeholder AI prediction
	// In a real implementation, this would:
	// 1. Load trained ML model
	// 2. Run inference on features
	// 3. Return prediction confidence
	
	avgScore := 0.0
	for _, feature := range features {
		avgScore += feature
	}
	avgScore /= float64(len(features))
	
	return AIPrediction{
		Confidence: avgScore,
		Score:      avgScore,
	}
}

func (me *MatchingEngine) GetStats() *MatchingStats {
	return me.matchingStats
}

// Helper functions for proper matching
func (me *MatchingEngine) calculateBridgeFee(amount *big.Int, sourceChain, destChain uint32) *big.Int {
	// Basic bridge fee calculation - 0.1% of amount + base fee
	baseFee := big.NewInt(1000000000000000) // 0.001 ETH base fee
	percentageFee := new(big.Int).Div(amount, big.NewInt(1000)) // 0.1%
	return new(big.Int).Add(baseFee, percentageFee)
}

func (me *MatchingEngine) generateExecutionProof(match *MatchingResult) []byte {
	// Generate a basic execution proof - in production would be cryptographic proof
	proofData := fmt.Sprintf("match_%s_%s_%d", 
		match.TradeA.IntentId.Hex(), 
		match.TradeB.IntentId.Hex(), 
		time.Now().Unix())
	return []byte(proofData)
}

// FindOptimalMatches finds optimal matches for the given intents
func (me *MatchingEngine) FindOptimalMatches(intents []CrossCoWTaskManager.Intent, maxSlippage *big.Int) ([]*MatchedTrade, error) {
	me.logger.Info("Finding optimal matches", "intentCount", len(intents))
	
	// Convert intents to TradeIntent format
	tradeIntents := make([]*TradeIntent, len(intents))
	for i, intent := range intents {
		tradeIntents[i] = &TradeIntent{
			IntentId:     common.BytesToHash([]byte(fmt.Sprintf("intent_%d", i))),
			User:         intent.User,
			TokenIn:      intent.InputToken,
			TokenOut:     intent.OutputToken,
			AmountIn:     intent.InputAmount,
			AmountOutMin: intent.MinOutputAmount,
			Deadline:     uint64(intent.Deadline),
			OriginChain:  intent.SourceChain,
			TargetChain:  intent.DestinationChain,
			IsActive:     true,
			CreatedAt:    time.Now(),
			Salt:         common.Hash{},
		}
	}
	
	// Add intents to pool
	for _, intent := range tradeIntents {
		if err := me.AddIntent(intent); err != nil {
			me.logger.Error("Error adding intent", "err", err)
			continue
		}
	}
	
	// Find matches
	matches := me.findMatches()
	
	// Convert to MatchedTrade format - CRITICAL FIX
	matchedTrades := make([]*MatchedTrade, 0, len(matches))
	intentIndexMap := make(map[common.Hash]uint32)
	
	// Create mapping from intent hash to index
	for i, intent := range tradeIntents {
		intentIndexMap[intent.IntentId] = uint32(i)
	}
	
	for _, match := range matches {
		// Map actual intent IDs to indices
		intentAIndex, foundA := intentIndexMap[match.TradeA.IntentId]
		intentBIndex, foundB := intentIndexMap[match.TradeB.IntentId]
		
		if !foundA || !foundB {
			me.logger.Error("Could not map intent IDs to indices", 
				"intentA", match.TradeA.IntentId.Hex(),
				"intentB", match.TradeB.IntentId.Hex())
			continue
		}
		
		// Calculate proper execution amount and bridge fee
		executionAmount := match.TradeA.AmountIn
		bridgeFee := me.calculateBridgeFee(executionAmount, match.TradeA.OriginChain, match.TradeB.OriginChain)
		
		matchedTrades = append(matchedTrades, &MatchedTrade{
			IntentAIndex:    intentAIndex,
			IntentBIndex:    intentBIndex,
			ExecutionAmount: executionAmount,
			BridgeFee:       bridgeFee,
			ExecutionProof:  me.generateExecutionProof(match),
		})
	}
	
	me.logger.Info("Found matches", "count", len(matchedTrades))
	return matchedTrades, nil
}