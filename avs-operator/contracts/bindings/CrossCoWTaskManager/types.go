package CrossCoWTaskManager

import (
	"math/big"
	"github.com/ethereum/go-ethereum/common"
)

// Intent represents a user's trading intent
type Intent struct {
	User              common.Address `json:"user"`
	InputToken        common.Address `json:"inputToken"`
	OutputToken       common.Address `json:"outputToken"`
	InputAmount       *big.Int       `json:"inputAmount"`
	MinOutputAmount   *big.Int       `json:"minOutputAmount"`
	SourceChain       uint32         `json:"sourceChain"`
	DestinationChain  uint32         `json:"destinationChain"`
	Deadline          uint32         `json:"deadline"`
	Signature         []byte         `json:"signature"`
}

// TradeMatchingTask represents a task from the TaskManager
type TradeMatchingTask struct {
	Intents          []Intent `json:"intents"`
	MaxSlippage      *big.Int `json:"maxSlippage"`
	Deadline         uint32   `json:"deadline"`
	TaskCreatedBlock uint32   `json:"taskCreatedBlock"`
	IntentPoolHash   [32]byte `json:"intentPoolHash"`
}

// MatchedTrade represents a matched pair of intents
type MatchedTrade struct {
	IntentAIndex     uint32   `json:"intentAIndex"`
	IntentBIndex     uint32   `json:"intentBIndex"`
	ExecutionAmount  *big.Int `json:"executionAmount"`
	BridgeFee        *big.Int `json:"bridgeFee"`
	ExecutionProof   []byte   `json:"executionProof"`
}

// TradeMatchingResponse represents the operator's response
type TradeMatchingResponse struct {
	ReferenceTaskIndex uint32         `json:"referenceTaskIndex"`
	Matches           []MatchedTrade  `json:"matches"`
	TotalGasEstimate  *big.Int        `json:"totalGasEstimate"`
	ExecutionPriority uint32          `json:"executionPriority"`
}

// ContractCrossCoWTaskManagerNewTradeMatchingTaskCreated represents the event
type ContractCrossCoWTaskManagerNewTradeMatchingTaskCreated struct {
	TaskIndex uint32
	Task      TradeMatchingTask
}
