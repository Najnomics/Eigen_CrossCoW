package operator

import (
	"context"
	"time"

	"github.com/Layr-Labs/eigensdk-go/logging"
	"github.com/eigencrosscow/avs/types"
)

// Operator represents the main operator interface
type Operator interface {
	Start(ctx context.Context) error
	Stop() error
	GetStatus() Status
}

// Status represents the operator status
type Status struct {
	IsRunning     bool      `json:"is_running"`
	Uptime        time.Duration `json:"uptime"`
	TasksProcessed uint64   `json:"tasks_processed"`
	MatchesFound   uint64   `json:"matches_found"`
	LastError     string    `json:"last_error,omitempty"`
}

// NewOperator creates a new operator instance
func NewOperator(config Config, logger logging.Logger) (Operator, error) {
	// Convert to types.NodeConfig
	nodeConfig := types.NodeConfig{
		EthRpcUrl:                  config.EthRpcUrl,
		EthWsUrl:                   config.EthWsUrl,
		BlsPrivateKeyStorePath:     config.BlsPrivateKeyStorePath,
		EcdsaPrivateKeyStorePath:   config.EcdsaPrivateKeyStorePath,
		OperatorAddress:            config.OperatorAddress,
		CrossCoWTaskManagerAddress: config.TaskManagerAddress,
		AggregatorServerIpPortAddress: config.AggregatorServerIpPortAddress,
		EnableMetrics:              config.EnableMetrics,
		EigenMetricsIpPortAddress:  config.EigenMetricsIpPortAddress,
		NodeApiIpPortAddress:       config.NodeApiIpPortAddress,
		MatchingAlgorithm:          config.MatchingAlgorithm,
		EnableAIMatching:           config.EnableAIMatching,
		Production:                 config.Production,
		TaskTimeout:                config.TaskTimeout,
		MaxConcurrentTasks:         config.MaxConcurrentTasks,
		LogLevel:                   config.LogLevel,
		LogFormat:                  config.LogFormat,
	}

	// Create CrossCoW operator
	crosscowOp, err := NewCrossCoWOperatorFromConfig(nodeConfig)
	if err != nil {
		return nil, err
	}

	return &operatorWrapper{
		config: config,
		logger: logger,
		op:     crosscowOp,
	}, nil
}

// operatorWrapper wraps the CrossCoW operator
type operatorWrapper struct {
	config Config
	logger logging.Logger
	op     *CrossCoWOperator
	status Status
}

func (w *operatorWrapper) Start(ctx context.Context) error {
	w.status.IsRunning = true
	w.logger.Info("Starting operator")
	
	return w.op.Start(ctx)
}

func (w *operatorWrapper) Stop() error {
	w.status.IsRunning = false
	w.logger.Info("Stopping operator")
	return nil
}

func (w *operatorWrapper) GetStatus() Status {
	return w.status
}