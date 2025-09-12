package core

import (
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
)

// TaskResponse represents a task response from the operator
type TaskResponse struct {
	ReferenceTaskIndex uint32         `json:"referenceTaskIndex"`
	Matches           []MatchedTrade  `json:"matches"`
	TotalGasEstimate  *big.Int        `json:"totalGasEstimate"`
	ExecutionPriority uint32          `json:"executionPriority"`
}

// MatchedTrade represents a matched pair of intents
type MatchedTrade struct {
	IntentAIndex     uint32   `json:"intentAIndex"`
	IntentBIndex     uint32   `json:"intentBIndex"`
	ExecutionAmount  *big.Int `json:"executionAmount"`
	BridgeFee        *big.Int `json:"bridgeFee"`
	ExecutionProof   []byte   `json:"executionProof"`
}

// GetTaskResponseDigest calculates the hash of a task response
func GetTaskResponseDigest(response *TaskResponse) (common.Hash, error) {
	// Serialize the response
	data, err := json.Marshal(response)
	if err != nil {
		return common.Hash{}, err
	}
	
	// Hash the serialized data
	hash := sha256.Sum256(data)
	return common.BytesToHash(hash[:]), nil
}

// ValidateTaskResponse validates a task response
func ValidateTaskResponse(response *TaskResponse) error {
	if response.ReferenceTaskIndex == 0 {
		return errors.New("invalid task index")
	}
	
	if len(response.Matches) == 0 {
		return errors.New("no matches provided")
	}
	
	for i, match := range response.Matches {
		if match.IntentAIndex == match.IntentBIndex {
			return fmt.Errorf("match %d: intent indices cannot be the same", i)
		}
		
		if match.ExecutionAmount.Cmp(big.NewInt(0)) <= 0 {
			return fmt.Errorf("match %d: execution amount must be positive", i)
		}
	}
	
	return nil
}
