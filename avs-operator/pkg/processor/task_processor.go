package processor

import (
	"context"
	"crypto/ecdsa"
	"encoding/json"
	"fmt"
	"math/big"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/Layr-Labs/eigensdk-go/logging"

	"github.com/eigencrosscow/avs/pkg/crypto"
	"github.com/eigencrosscow/avs/contracts/bindings/CrossCoWTaskManager"
)

// TaskProcessor handles task processing and response generation
type TaskProcessor struct {
	logger        logging.Logger
	blsKeyPair    *crypto.BLSKeyPair
	ecdsaKey      *ecdsa.PrivateKey
	operatorAddr  common.Address
}

// NewTaskProcessor creates a new task processor
func NewTaskProcessor(
	logger logging.Logger,
	blsKeyPair *crypto.BLSKeyPair,
	ecdsaKey *ecdsa.PrivateKey,
	operatorAddr common.Address,
) *TaskProcessor {
	return &TaskProcessor{
		logger:       logger,
		blsKeyPair:   blsKeyPair,
		ecdsaKey:     ecdsaKey,
		operatorAddr: operatorAddr,
	}
}

// ProcessTask processes a trade matching task
func (tp *TaskProcessor) ProcessTask(ctx context.Context, task CrossCoWTaskManager.TradeMatchingTask) (*CrossCoWTaskManager.TradeMatchingResponse, error) {
	tp.logger.Info("Processing task", "taskIndex", task.TaskIndex)

	// Find optimal matches
	matches, err := tp.findOptimalMatches(task.Intents, task.MaxSlippage)
	if err != nil {
		tp.logger.Error("Failed to find matches", "error", err)
		return nil, fmt.Errorf("failed to find matches: %w", err)
	}

	// Calculate total gas estimate
	totalGasEstimate := tp.calculateGasEstimate(matches)

	// Create response
	response := &CrossCoWTaskManager.TradeMatchingResponse{
		ReferenceTaskIndex: task.TaskIndex,
		Matches:           matches,
		TotalGasEstimate:  totalGasEstimate,
		ExecutionPriority: 1, // Default priority
	}

	tp.logger.Info("Task processed successfully", 
		"taskIndex", task.TaskIndex,
		"matches", len(matches),
		"gasEstimate", totalGasEstimate.String(),
	)

	return response, nil
}

// findOptimalMatches finds optimal matches for the given intents
func (tp *TaskProcessor) findOptimalMatches(intents []CrossCoWTaskManager.Intent, maxSlippage *big.Int) ([]CrossCoWTaskManager.MatchedTrade, error) {
	tp.logger.Debug("Finding optimal matches", "intentCount", len(intents))

	if len(intents) < 2 {
		return []CrossCoWTaskManager.MatchedTrade{}, nil
	}

	var matches []CrossCoWTaskManager.MatchedTrade
	usedIntents := make(map[int]bool)

	// Simple matching algorithm - find pairs with compatible tokens
	for i := 0; i < len(intents); i++ {
		if usedIntents[i] {
			continue
		}

		intentA := intents[i]
		
		for j := i + 1; j < len(intents); j++ {
			if usedIntents[j] {
				continue
			}

			intentB := intents[j]

			// Check if intents are compatible
			if tp.areIntentsCompatible(intentA, intentB, maxSlippage) {
				match := tp.createMatch(intentA, intentB, i, j)
				matches = append(matches, match)
				usedIntents[i] = true
				usedIntents[j] = true
				break
			}
		}
	}

	tp.logger.Info("Found matches", "count", len(matches))
	return matches, nil
}

// areIntentsCompatible checks if two intents are compatible for matching
func (tp *TaskProcessor) areIntentsCompatible(intentA, intentB CrossCoWTaskManager.Intent, maxSlippage *big.Int) bool {
	// Check if tokens are compatible (A's output = B's input, A's input = B's output)
	tokenCompatible := (intentA.OutputToken == intentB.InputToken) && (intentA.InputToken == intentB.OutputToken)
	
	// Check if chains are compatible (A's destination = B's source, A's source = B's destination)
	chainCompatible := (intentA.DestinationChain == intentB.SourceChain) && (intentA.SourceChain == intentB.DestinationChain)
	
	// Check if amounts are compatible
	amountCompatible := intentA.InputAmount.Cmp(intentB.InputAmount) == 0
	
	// Check if deadlines are compatible
	deadlineCompatible := intentA.Deadline >= uint32(time.Now().Unix()) && intentB.Deadline >= uint32(time.Now().Unix())
	
	// Check slippage tolerance
	slippageCompatible := intentA.MinOutputAmount.Cmp(intentB.InputAmount) <= 0 && intentB.MinOutputAmount.Cmp(intentA.InputAmount) <= 0

	return tokenCompatible && chainCompatible && amountCompatible && deadlineCompatible && slippageCompatible
}

// createMatch creates a matched trade from two intents
func (tp *TaskProcessor) createMatch(intentA, intentB CrossCoWTaskManager.Intent, indexA, indexB int) CrossCoWTaskManager.MatchedTrade {
	// Calculate execution amount (minimum of both amounts)
	executionAmount := intentA.InputAmount
	if intentB.InputAmount.Cmp(executionAmount) < 0 {
		executionAmount = intentB.InputAmount
	}

	// Calculate bridge fee (simplified - 0.1% of amount)
	bridgeFee := new(big.Int).Div(executionAmount, big.NewInt(1000))

	// Generate execution proof (simplified)
	proof := tp.generateExecutionProof(intentA, intentB, executionAmount)

	return CrossCoWTaskManager.MatchedTrade{
		IntentAIndex:    uint32(indexA),
		IntentBIndex:    uint32(indexB),
		ExecutionAmount: executionAmount,
		BridgeFee:       bridgeFee,
		ExecutionProof:  proof,
	}
}

// generateExecutionProof generates an execution proof for the match
func (tp *TaskProcessor) generateExecutionProof(intentA, intentB CrossCoWTaskManager.Intent, amount *big.Int) []byte {
	// Create proof data
	proofData := map[string]interface{}{
		"intentA": map[string]interface{}{
			"user":     intentA.User.Hex(),
			"tokenIn":  intentA.InputToken.Hex(),
			"tokenOut": intentA.OutputToken.Hex(),
			"amount":   intentA.InputAmount.String(),
		},
		"intentB": map[string]interface{}{
			"user":     intentB.User.Hex(),
			"tokenIn":  intentB.InputToken.Hex(),
			"tokenOut": intentB.OutputToken.Hex(),
			"amount":   intentB.InputAmount.String(),
		},
		"executionAmount": amount.String(),
		"timestamp":       time.Now().Unix(),
		"operator":        tp.operatorAddr.Hex(),
	}

	// Serialize to JSON
	proofBytes, err := json.Marshal(proofData)
	if err != nil {
		tp.logger.Error("Failed to marshal proof data", "error", err)
		return []byte{}
	}

	// Sign the proof
	signature, err := tp.blsKeyPair.SignBLS(proofBytes)
	if err != nil {
		tp.logger.Error("Failed to sign proof", "error", err)
		return []byte{}
	}

	// Combine proof data and signature
	fullProof := append(proofBytes, signature...)
	return fullProof
}

// calculateGasEstimate calculates the total gas estimate for the matches
func (tp *TaskProcessor) calculateGasEstimate(matches []CrossCoWTaskManager.MatchedTrade) *big.Int {
	// Base gas cost
	baseGas := big.NewInt(21000)
	
	// Gas per match
	gasPerMatch := big.NewInt(100000)
	
	// Calculate total gas
	totalGas := new(big.Int).Set(baseGas)
	for range matches {
		totalGas.Add(totalGas, gasPerMatch)
	}
	
	return totalGas
}

// SignResponse signs a task response
func (tp *TaskProcessor) SignResponse(response *CrossCoWTaskManager.TradeMatchingResponse) ([]byte, error) {
	// Serialize response
	responseData, err := json.Marshal(response)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal response: %w", err)
	}

	// Sign with BLS
	signature, err := tp.blsKeyPair.SignBLS(responseData)
	if err != nil {
		return nil, fmt.Errorf("failed to sign response: %w", err)
	}

	return signature, nil
}

// VerifyResponse verifies a task response signature
func (tp *TaskProcessor) VerifyResponse(response *CrossCoWTaskManager.TradeMatchingResponse, signature []byte) (bool, error) {
	// Serialize response
	responseData, err := json.Marshal(response)
	if err != nil {
		return false, fmt.Errorf("failed to marshal response: %w", err)
	}

	// Verify BLS signature
	valid, err := crypto.VerifyBLS(tp.blsKeyPair.PublicKey, responseData, signature)
	if err != nil {
		return false, fmt.Errorf("failed to verify signature: %w", err)
	}

	return valid, nil
}

// GetOperatorAddress returns the operator address
func (tp *TaskProcessor) GetOperatorAddress() common.Address {
	return tp.operatorAddr
}

// GetBLSPublicKey returns the BLS public key
func (tp *TaskProcessor) GetBLSPublicKey() crypto.BLSPublicKey {
	return tp.blsKeyPair.PublicKey
}

// ValidateTask validates a task before processing
func (tp *TaskProcessor) ValidateTask(task CrossCoWTaskManager.TradeMatchingTask) error {
	if len(task.Intents) < 2 {
		return fmt.Errorf("task must have at least 2 intents, got %d", len(task.Intents))
	}

	if task.MaxSlippage.Cmp(big.NewInt(1000)) > 0 {
		return fmt.Errorf("max slippage too high: %s", task.MaxSlippage.String())
	}

	if task.Deadline <= uint32(time.Now().Unix()) {
		return fmt.Errorf("task deadline has passed: %d", task.Deadline)
	}

	// Validate each intent
	for i, intent := range task.Intents {
		if err := tp.validateIntent(intent, i); err != nil {
			return fmt.Errorf("invalid intent %d: %w", i, err)
		}
	}

	return nil
}

// validateIntent validates a single intent
func (tp *TaskProcessor) validateIntent(intent CrossCoWTaskManager.Intent, index int) error {
	if intent.User == (common.Address{}) {
		return fmt.Errorf("intent %d: user address is zero", index)
	}

	if intent.InputToken == (common.Address{}) {
		return fmt.Errorf("intent %d: input token address is zero", index)
	}

	if intent.OutputToken == (common.Address{}) {
		return fmt.Errorf("intent %d: output token address is zero", index)
	}

	if intent.InputAmount.Cmp(big.NewInt(0)) <= 0 {
		return fmt.Errorf("intent %d: input amount must be positive", index)
	}

	if intent.MinOutputAmount.Cmp(big.NewInt(0)) <= 0 {
		return fmt.Errorf("intent %d: min output amount must be positive", index)
	}

	if intent.SourceChain == intent.DestinationChain {
		return fmt.Errorf("intent %d: source and destination chains must be different", index)
	}

	if intent.Deadline <= uint32(time.Now().Unix()) {
		return fmt.Errorf("intent %d: deadline has passed", index)
	}

	return nil
}
