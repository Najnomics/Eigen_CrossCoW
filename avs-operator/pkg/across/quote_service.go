package across

import (
	"encoding/json"
	"fmt"
	"math/big"
	"net/http"
	"time"

	"github.com/Layr-Labs/eigensdk-go/logging"
	"github.com/ethereum/go-ethereum/common"
)

// QuoteService handles getting quotes from Across Protocol API
type QuoteService struct {
	apiUrl     string
	logger     logging.Logger
	httpClient *http.Client
}

// QuoteRequest represents a request for a bridge quote
type QuoteRequest struct {
	OriginChainId      uint32         `json:"originChainId"`
	DestinationChainId uint32         `json:"destinationChainId"`
	InputToken         common.Address `json:"inputToken"`
	OutputToken        common.Address `json:"outputToken"`
	Amount            *big.Int       `json:"amount"`
	Recipient         common.Address `json:"recipient"`
	Message           []byte         `json:"message"`
}

// QuoteResponse represents the API response for a quote
type QuoteResponse struct {
	InputAmount       *big.Int      `json:"inputAmount"`
	OutputAmount      *big.Int      `json:"outputAmount"`
	BridgeFee         *big.Int      `json:"bridgeFee"`
	RelayerGasFee     *big.Int      `json:"relayerGasFee"`
	LpFee            *big.Int      `json:"lpFee"`
	TotalFee         *big.Int      `json:"totalFee"`
	EstimatedTime    time.Duration `json:"estimatedTime"`
	Confidence       float64       `json:"confidence"`
	QuoteTimestamp   uint32        `json:"quoteTimestamp"`
	ExpiresAt        time.Time     `json:"expiresAt"`
}

// NewQuoteService creates a new quote service
func NewQuoteService(apiUrl string, logger logging.Logger) *QuoteService {
	return &QuoteService{
		apiUrl: apiUrl,
		logger: logger.With("component", "quote-service"),
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

// GetQuote retrieves a quote for the given parameters
func (qs *QuoteService) GetQuote(request QuoteRequest) (*BridgeQuote, error) {
	qs.logger.Debug("Getting quote from API",
		"originChain", request.OriginChainId,
		"destChain", request.DestinationChainId,
		"amount", request.Amount.String(),
	)

	// In a real implementation, this would make HTTP request to Across API
	// For now, we'll return a mock quote
	quote := &BridgeQuote{
		InputAmount:    request.Amount,
		BridgeFee:      qs.calculateBridgeFee(request.Amount, request.OriginChainId, request.DestinationChainId),
		RelayerGasFee:  qs.calculateRelayerFee(request.Amount, request.OriginChainId, request.DestinationChainId),
		LpFee:         qs.calculateLpFee(request.Amount),
		EstimatedTime: qs.estimateTime(request.OriginChainId, request.DestinationChainId),
		Confidence:    0.95,
	}

	// Calculate total fee and output amount
	quote.TotalFee = new(big.Int).Add(quote.BridgeFee, quote.RelayerGasFee)
	quote.TotalFee.Add(quote.TotalFee, quote.LpFee)
	
	quote.OutputAmount = new(big.Int).Sub(quote.InputAmount, quote.TotalFee)

	qs.logger.Debug("Generated quote",
		"bridgeFee", quote.BridgeFee.String(),
		"outputAmount", quote.OutputAmount.String(),
		"estimatedTime", quote.EstimatedTime,
	)

	return quote, nil
}

// calculateBridgeFee calculates the bridge fee based on amount and chains
func (qs *QuoteService) calculateBridgeFee(amount *big.Int, originChain, destChain uint32) *big.Int {
	// Base fee of 0.1%
	baseFee := new(big.Int).Mul(amount, big.NewInt(10))
	baseFee.Div(baseFee, big.NewInt(10000))
	
	// Add chain-specific multiplier
	multiplier := qs.getChainMultiplier(originChain, destChain)
	bridgeFee := new(big.Int).Mul(baseFee, big.NewInt(multiplier))
	bridgeFee.Div(bridgeFee, big.NewInt(100))
	
	return bridgeFee
}

// calculateRelayerFee calculates the relayer gas fee
func (qs *QuoteService) calculateRelayerFee(amount *big.Int, originChain, destChain uint32) *big.Int {
	// Base relayer fee of 0.15%
	relayerFee := new(big.Int).Mul(amount, big.NewInt(15))
	relayerFee.Div(relayerFee, big.NewInt(10000))
	
	return relayerFee
}

// calculateLpFee calculates the liquidity provider fee
func (qs *QuoteService) calculateLpFee(amount *big.Int) *big.Int {
	// LP fee of 0.05%
	lpFee := new(big.Int).Mul(amount, big.NewInt(5))
	lpFee.Div(lpFee, big.NewInt(10000))
	
	return lpFee
}

// getChainMultiplier returns fee multiplier for chain pairs
func (qs *QuoteService) getChainMultiplier(originChain, destChain uint32) int64 {
	// Fee multipliers based on chain complexity
	multipliers := map[string]int64{
		"1-10":    100, // ETH -> Optimism
		"1-137":   110, // ETH -> Polygon
		"1-42161": 105, // ETH -> Arbitrum
		"1-8453":  100, // ETH -> Base
		"10-1":    110, // Optimism -> ETH
		"137-1":   120, // Polygon -> ETH
		"42161-1": 105, // Arbitrum -> ETH
		"8453-1":  100, // Base -> ETH
	}
	
	key := fmt.Sprintf("%d-%d", originChain, destChain)
	if multiplier, exists := multipliers[key]; exists {
		return multiplier
	}
	
	return 150 // Default higher fee for unknown pairs
}

// estimateTime estimates bridge completion time
func (qs *QuoteService) estimateTime(originChain, destChain uint32) time.Duration {
	baseTimes := map[string]time.Duration{
		"1-10":    2 * time.Minute,  // ETH -> Optimism
		"1-137":   5 * time.Minute,  // ETH -> Polygon
		"1-42161": 3 * time.Minute,  // ETH -> Arbitrum
		"1-8453":  2 * time.Minute,  // ETH -> Base
		"10-1":    15 * time.Minute, // Optimism -> ETH
		"137-1":   30 * time.Minute, // Polygon -> ETH
		"42161-1": 15 * time.Minute, // Arbitrum -> ETH
		"8453-1":  15 * time.Minute, // Base -> ETH
	}
	
	key := fmt.Sprintf("%d-%d", originChain, destChain)
	if duration, exists := baseTimes[key]; exists {
		return duration
	}
	
	return 10 * time.Minute // Default estimate
}

// makeAPIRequest makes an HTTP request to the Across API (for future implementation)
func (qs *QuoteService) makeAPIRequest(request QuoteRequest) (*QuoteResponse, error) {
	// This would implement actual API communication
	// For now, return mock response
	
	response := &QuoteResponse{
		InputAmount:     request.Amount,
		QuoteTimestamp: uint32(time.Now().Unix()),
		ExpiresAt:      time.Now().Add(5 * time.Minute),
	}
	
	return response, nil
}

// validateQuoteRequest validates the quote request parameters
func (qs *QuoteService) validateQuoteRequest(request QuoteRequest) error {
	if request.Amount == nil || request.Amount.Cmp(big.NewInt(0)) <= 0 {
		return fmt.Errorf("invalid amount")
	}
	
	if request.InputToken == (common.Address{}) {
		return fmt.Errorf("invalid input token")
	}
	
	if request.OutputToken == (common.Address{}) {
		return fmt.Errorf("invalid output token")
	}
	
	if request.OriginChainId == request.DestinationChainId {
		return fmt.Errorf("origin and destination chains must be different")
	}
	
	return nil
}