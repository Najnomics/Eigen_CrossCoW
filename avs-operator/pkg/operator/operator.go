package operator

import (
	"context"
	"crypto/ecdsa"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math/big"
	"sync"
	"time"

	"github.com/Layr-Labs/eigensdk-go/chainio/clients/eth"
	"github.com/Layr-Labs/eigensdk-go/logging"
	"github.com/Layr-Labs/eigensdk-go/metrics"
	"github.com/Layr-Labs/eigensdk-go/nodeapi"
	"github.com/Layr-Labs/eigensdk-go/signerv2"
	"github.com/Layr-Labs/eigensdk-go/types"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/prometheus/client_golang/prometheus"
)

const (
	SemVer = "0.1.0"
)

type Operator struct {
	config    Config
	logger    logging.Logger
	ethClient eth.Client
	metricsReg *prometheus.Registry
	metrics   metrics.Metrics
	nodeApi   *nodeapi.NodeApi

	blsKeypair              *types.BlsKeyPair
	operatorId              types.OperatorId
	operatorAddr            common.Address
	operatorEcdsaPrivateKey *ecdsa.PrivateKey

	// CrossCoW specific fields
	matchingEngine    *MatchingEngine
	acrossIntegration *AcrossIntegration
	taskProcessor     *TaskProcessor
	
	// Task management
	activeTasks       map[uint32]*MatchingTask
	activeTasksMutex  sync.RWMutex
	taskResponseChan  chan TaskResponseInfo
	
	// Performance metrics
	metricsCollector *MetricsCollector
}

type Config struct {
	EcdsaPrivateKeyStorePath       string `json:"ecdsa_private_key_store_path"`
	BlsPrivateKeyStorePath         string `json:"bls_private_key_store_path"`
	EthRpcUrl                      string `json:"eth_rpc_url"`
	EthWsUrl                       string `json:"eth_ws_url"`
	ServiceManagerAddress          string `json:"service_manager_address"`
	AcrossHubPoolAddress           string `json:"across_hub_pool_address"`
	RegisterOperatorOnStartup      bool   `json:"register_operator_on_startup"`
	EigenMetricsIpPortAddress      string `json:"eigen_metrics_ip_port_address"`
	EnableMetrics                  bool   `json:"enable_metrics"`
	NodeApiIpPortAddress           string `json:"node_api_ip_port_address"`
	EnableNodeApi                  bool   `json:"enable_node_api"`
	MatchingAlgorithm              string `json:"matching_algorithm"`
	MaxConcurrentTasks             int    `json:"max_concurrent_tasks"`
	TaskTimeout                    int    `json:"task_timeout_seconds"`
	EnableAIMatching               bool   `json:"enable_ai_matching"`
	DatabaseURL                    string `json:"database_url"`
}

type MatchingTask struct {
	TaskIndex       uint32              `json:"taskIndex"`
	TradeId         common.Hash         `json:"tradeId"`
	Trade           MatchedTrade        `json:"trade"`
	TaskCreatedBlock uint32             `json:"taskCreatedBlock"`
	Deadline        uint64              `json:"deadline"`
	IsComplete      bool                `json:"isComplete"`
	AssignedAt      time.Time           `json:"assignedAt"`
}

type MatchedTrade struct {
	TradeId         common.Hash    `json:"tradeId"`
	IntentA         common.Hash    `json:"intentA"`
	IntentB         common.Hash    `json:"intentB"`
	AmountA         *big.Int       `json:"amountA"`
	AmountB         *big.Int       `json:"amountB"`
	ChainA          uint32         `json:"chainA"`
	ChainB          uint32         `json:"chainB"`
	UserA           common.Address `json:"userA"`
	UserB           common.Address `json:"userB"`
	TokenA          common.Address `json:"tokenA"`
	TokenB          common.Address `json:"tokenB"`
	IsExecuted      bool           `json:"isExecuted"`
	ExecutionTime   uint64         `json:"executionTime"`
	AcrossDepositId common.Hash    `json:"acrossDepositId"`
}

type TaskResponseInfo struct {
	TaskIndex       uint32      `json:"taskIndex"`
	TradeId         common.Hash `json:"tradeId"`
	Success         bool        `json:"success"`
	AcrossDepositId common.Hash `json:"acrossDepositId"`
	GasUsed         uint64      `json:"gasUsed"`
	ExecutionTime   uint64      `json:"executionTime"`
	BlsSignature    types.Signature `json:"blsSignature"`
	OperatorId      types.OperatorId `json:"operatorId"`
}

type MetricsCollector struct {
	TasksProcessed    prometheus.Counter
	TasksSuccessful   prometheus.Counter
	TasksFailed       prometheus.Counter
	MatchingTime      prometheus.Histogram
	ExecutionTime     prometheus.Histogram
	GasCosts          prometheus.Histogram
	RewardsEarned     prometheus.Counter
}

func NewOperator(config Config, logger logging.Logger) (*Operator, error) {
	logger = logger.With("component", "crosscow-operator")

	// Initialize Ethereum client
	ethClient, err := eth.NewClient(config.EthRpcUrl)
	if err != nil {
		return nil, fmt.Errorf("failed to create eth client: %w", err)
	}

	// Load operator keys
	operatorEcdsaPrivateKey, err := crypto.LoadECDSA(config.EcdsaPrivateKeyStorePath)
	if err != nil {
		return nil, fmt.Errorf("failed to load operator ecdsa private key: %w", err)
	}

	operatorAddr := crypto.PubkeyToAddress(operatorEcdsaPrivateKey.PublicKey)
	logger.Info("Operator address", "address", operatorAddr.Hex())

	blsKeyPair, err := types.ReadBlsPrivateKeyFromFile(config.BlsPrivateKeyStorePath, "")
	if err != nil {
		return nil, fmt.Errorf("failed to read bls private key: %w", err)
	}

	operatorId := types.OperatorIdFromG1Pubkey(blsKeyPair.PubkeyG1)
	logger.Info("Operator ID", "operatorId", hex.EncodeToString(operatorId[:]))

	// Initialize metrics
	var metricsReg *prometheus.Registry
	var eigenMetrics metrics.Metrics
	var metricsCollector *MetricsCollector

	if config.EnableMetrics {
		metricsReg = prometheus.NewRegistry()
		eigenMetrics = metrics.NewPrometheusMetrics(metricsReg, "eigencrosscow", logger)
		metricsCollector = NewMetricsCollector(metricsReg)
		eigenMetrics.Start(context.Background(), config.EigenMetricsIpPortAddress)
	} else {
		metricsReg = prometheus.NewRegistry()
		eigenMetrics = metrics.NewNoopMetrics()
		metricsCollector = &MetricsCollector{}
	}

	// Initialize node API
	var nodeApi *nodeapi.NodeApi
	if config.EnableNodeApi {
		nodeApi = nodeapi.NewNodeApi("eigencrosscow-operator", SemVer, config.NodeApiIpPortAddress, logger)
		go nodeApi.Start()
	}

	// Initialize matching engine
	matchingEngine, err := NewMatchingEngine(config, logger)
	if err != nil {
		return nil, fmt.Errorf("failed to create matching engine: %w", err)
	}

	// Initialize Across integration
	acrossIntegration, err := NewAcrossIntegration(config, ethClient, logger)
	if err != nil {
		return nil, fmt.Errorf("failed to create Across integration: %w", err)
	}

	// Initialize task processor
	taskProcessor := NewTaskProcessor(config, logger)

	operator := &Operator{
		config:                  config,
		logger:                  logger,
		ethClient:              ethClient,
		metricsReg:             metricsReg,
		metrics:                eigenMetrics,
		nodeApi:                nodeApi,
		blsKeypair:             blsKeyPair,
		operatorId:             operatorId,
		operatorAddr:           operatorAddr,
		operatorEcdsaPrivateKey: operatorEcdsaPrivateKey,
		matchingEngine:         matchingEngine,
		acrossIntegration:      acrossIntegration,
		taskProcessor:          taskProcessor,
		activeTasks:            make(map[uint32]*MatchingTask),
		taskResponseChan:       make(chan TaskResponseInfo, 100),
		metricsCollector:       metricsCollector,
	}

	if config.RegisterOperatorOnStartup {
		if err := operator.registerOperator(); err != nil {
			logger.Error("Failed to register operator on startup", "error", err)
		}
	}

	return operator, nil
}

func (o *Operator) Start(ctx context.Context) error {
	o.logger.Info("Starting CrossCoW AVS Operator")

	// Start task processing goroutines
	go o.listenForNewTasks(ctx)
	go o.processTaskResponses(ctx)
	go o.processActiveTasks(ctx)
	go o.monitorTaskTimeouts(ctx)

	// Start matching engine
	go o.matchingEngine.Start(ctx)

	// Start metrics collection
	go o.collectMetrics(ctx)

	o.logger.Info("CrossCoW AVS Operator started successfully")

	// Wait for context cancellation
	<-ctx.Done()
	o.logger.Info("Shutting down CrossCoW AVS Operator")
	
	return nil
}

func (o *Operator) registerOperator() error {
	o.logger.Info("Registering operator with CrossCoW AVS")

	// In a full implementation, this would:
	// 1. Generate proper operator signature
	// 2. Call the service manager's registerOperator function
	// 3. Handle registration confirmation

	o.logger.Info("Operator registration completed", 
		"operatorId", hex.EncodeToString(o.operatorId[:]),
		"address", o.operatorAddr.Hex(),
	)

	return nil
}

func (o *Operator) listenForNewTasks(ctx context.Context) {
	o.logger.Info("Starting to listen for new matching tasks")

	// In a real implementation, this would:
	// 1. Subscribe to TaskCreated events from the service manager
	// 2. Process incoming tasks
	// 3. Add them to the active tasks queue

	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			// Simulate receiving tasks for demonstration
			o.simulateTask()
		}
	}
}

func (o *Operator) simulateTask() {
	// Create a simulated matching task
	task := &MatchingTask{
		TaskIndex:       uint32(time.Now().Unix() % 1000000),
		TradeId:         common.BytesToHash(crypto.Keccak256([]byte(fmt.Sprintf("trade_%d", time.Now().Unix())))),
		TaskCreatedBlock: uint32(time.Now().Unix()),
		Deadline:        uint64(time.Now().Add(time.Duration(o.config.TaskTimeout) * time.Second).Unix()),
		IsComplete:      false,
		AssignedAt:      time.Now(),
		Trade: MatchedTrade{
			TradeId: common.BytesToHash(crypto.Keccak256([]byte(fmt.Sprintf("trade_%d", time.Now().Unix())))),
			IntentA: common.BytesToHash(crypto.Keccak256([]byte("intentA"))),
			IntentB: common.BytesToHash(crypto.Keccak256([]byte("intentB"))),
			AmountA: big.NewInt(1000000000000000000), // 1 ETH
			AmountB: big.NewInt(1000000000000000000), // 1 ETH
			ChainA:  1,  // Ethereum
			ChainB:  10, // Optimism
			UserA:   common.HexToAddress("0x742d35Cc6608C8B29a1b8d9c0f6f8aD5b7c8b0A1"),
			UserB:   common.HexToAddress("0x742d35Cc6608C8B29a1b8d9c0f6f8aD5b7c8b0A2"),
			TokenA:  common.HexToAddress("0xA0b86a33e6441C4c27D3F50c9d6D14bDf12F4e6e"), // USDC
			TokenB:  common.HexToAddress("0xA0b86a33e6441C4c27D3F50c9d6D14bDf12F4e6e"), // USDC
		},
	}

	o.activeTasksMutex.Lock()
	o.activeTasks[task.TaskIndex] = task
	o.activeTasksMutex.Unlock()

	o.logger.Info("Received new matching task",
		"taskIndex", task.TaskIndex,
		"tradeId", task.TradeId.Hex(),
		"chainA", task.Trade.ChainA,
		"chainB", task.Trade.ChainB,
	)
}

func (o *Operator) processActiveTasks(ctx context.Context) {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			o.processNextTask()
		}
	}
}

func (o *Operator) processNextTask() {
	o.activeTasksMutex.RLock()
	var nextTask *MatchingTask
	for _, task := range o.activeTasks {
		if !task.IsComplete {
			nextTask = task
			break
		}
	}
	o.activeTasksMutex.RUnlock()

	if nextTask == nil {
		return
	}

	startTime := time.Now()
	o.logger.Info("Processing matching task", "taskIndex", nextTask.TaskIndex)

	// Process the cross-chain trade execution
	success, acrossDepositId, gasUsed := o.executeTask(nextTask)

	executionTime := time.Since(startTime)
	
	// Create task response
	response := TaskResponseInfo{
		TaskIndex:       nextTask.TaskIndex,
		TradeId:         nextTask.TradeId,
		Success:         success,
		AcrossDepositId: acrossDepositId,
		GasUsed:         gasUsed,
		ExecutionTime:   uint64(executionTime.Seconds()),
		OperatorId:      o.operatorId,
	}

	// Sign the response
	responseHash := o.hashTaskResponse(response)
	blsSignature := o.blsKeypair.SignMessage(responseHash)
	response.BlsSignature = *blsSignature

	// Send response
	select {
	case o.taskResponseChan <- response:
		o.logger.Info("Task response queued", "taskIndex", nextTask.TaskIndex, "success", success)
	default:
		o.logger.Warn("Task response channel full", "taskIndex", nextTask.TaskIndex)
	}

	// Mark task as complete
	o.activeTasksMutex.Lock()
	if task, exists := o.activeTasks[nextTask.TaskIndex]; exists {
		task.IsComplete = true
	}
	o.activeTasksMutex.Unlock()

	// Update metrics
	o.metricsCollector.TasksProcessed.Inc()
	if success {
		o.metricsCollector.TasksSuccessful.Inc()
	} else {
		o.metricsCollector.TasksFailed.Inc()
	}
	
	o.metricsCollector.ExecutionTime.Observe(executionTime.Seconds())
	o.metricsCollector.GasCosts.Observe(float64(gasUsed))
}

func (o *Operator) executeTask(task *MatchingTask) (success bool, acrossDepositId common.Hash, gasUsed uint64) {
	// Execute cross-chain trade using Across Protocol
	success, acrossDepositId, gasUsed, err := o.acrossIntegration.ExecuteCrossChainTrade(task.Trade)
	if err != nil {
		o.logger.Error("Failed to execute cross-chain trade", 
			"taskIndex", task.TaskIndex,
			"error", err,
		)
		return false, common.Hash{}, 0
	}

	o.logger.Info("Successfully executed cross-chain trade",
		"taskIndex", task.TaskIndex,
		"acrossDepositId", acrossDepositId.Hex(),
		"gasUsed", gasUsed,
	)

	return success, acrossDepositId, gasUsed
}

func (o *Operator) processTaskResponses(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case response := <-o.taskResponseChan:
			o.submitTaskResponse(response)
		}
	}
}

func (o *Operator) submitTaskResponse(response TaskResponseInfo) {
	o.logger.Info("Submitting task response to service manager",
		"taskIndex", response.TaskIndex,
		"success", response.Success,
		"gasUsed", response.GasUsed,
	)

	// In a real implementation, this would call the service manager's submitTaskResponse function
	// For now, we'll just log the response
	responseJson, _ := json.MarshalIndent(response, "", "  ")
	o.logger.Info("Task response submitted", "response", string(responseJson))
}

func (o *Operator) monitorTaskTimeouts(ctx context.Context) {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			o.checkTaskTimeouts()
		}
	}
}

func (o *Operator) checkTaskTimeouts() {
	currentTime := uint64(time.Now().Unix())
	
	o.activeTasksMutex.Lock()
	defer o.activeTasksMutex.Unlock()

	for taskIndex, task := range o.activeTasks {
		if !task.IsComplete && currentTime > task.Deadline {
			o.logger.Warn("Task timed out", "taskIndex", taskIndex, "deadline", task.Deadline)
			
			// Mark as failed due to timeout
			task.IsComplete = true
			o.metricsCollector.TasksFailed.Inc()
		}
	}
}

func (o *Operator) collectMetrics(ctx context.Context) {
	ticker := time.NewTicker(60 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			o.updateMetrics()
		}
	}
}

func (o *Operator) updateMetrics() {
	o.activeTasksMutex.RLock()
	activeCount := len(o.activeTasks)
	o.activeTasksMutex.RUnlock()

	o.logger.Debug("Metrics update", 
		"activeTasks", activeCount,
		"operatorAddress", o.operatorAddr.Hex(),
	)
}

func (o *Operator) hashTaskResponse(response TaskResponseInfo) [32]byte {
	responseData := struct {
		TaskIndex       uint32
		TradeId         common.Hash
		Success         bool
		AcrossDepositId common.Hash
		ExecutionTime   uint64
	}{
		TaskIndex:       response.TaskIndex,
		TradeId:         response.TradeId,
		Success:         response.Success,
		AcrossDepositId: response.AcrossDepositId,
		ExecutionTime:   response.ExecutionTime,
	}
	
	responseBytes, _ := json.Marshal(responseData)
	return crypto.Keccak256Hash(responseBytes)
}

// Getter methods
func (o *Operator) GetOperatorId() types.OperatorId {
	return o.operatorId
}

func (o *Operator) GetOperatorAddress() common.Address {
	return o.operatorAddr
}

func (o *Operator) GetBlsPublicKey() *types.G1Point {
	return o.blsKeypair.PubkeyG1
}

func NewMetricsCollector(registry *prometheus.Registry) *MetricsCollector {
	collector := &MetricsCollector{
		TasksProcessed: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "crosscow_tasks_processed_total",
			Help: "Total number of tasks processed",
		}),
		TasksSuccessful: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "crosscow_tasks_successful_total",
			Help: "Total number of successful tasks",
		}),
		TasksFailed: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "crosscow_tasks_failed_total",
			Help: "Total number of failed tasks",
		}),
		MatchingTime: prometheus.NewHistogram(prometheus.HistogramOpts{
			Name: "crosscow_matching_duration_seconds",
			Help: "Time taken to match trades",
		}),
		ExecutionTime: prometheus.NewHistogram(prometheus.HistogramOpts{
			Name: "crosscow_execution_duration_seconds",
			Help: "Time taken to execute cross-chain trades",
		}),
		GasCosts: prometheus.NewHistogram(prometheus.HistogramOpts{
			Name: "crosscow_gas_costs",
			Help: "Gas costs for trade execution",
		}),
		RewardsEarned: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "crosscow_rewards_earned_total",
			Help: "Total rewards earned by operator",
		}),
	}

	if registry != nil {
		registry.MustRegister(
			collector.TasksProcessed,
			collector.TasksSuccessful,
			collector.TasksFailed,
			collector.MatchingTime,
			collector.ExecutionTime,
			collector.GasCosts,
			collector.RewardsEarned,
		)
	}

	return collector
}