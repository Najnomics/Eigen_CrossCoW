package operator

import (
	"context"
	"crypto/ecdsa"
	"encoding/hex"
	"fmt"
	"math/big"
	"os"
	"time"

	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/prometheus/client_golang/prometheus"

	sdkcommon "github.com/eigencrosscow/avs/common"
	"github.com/eigencrosscow/avs/contracts/bindings/CrossCoWTaskManager"
	"github.com/eigencrosscow/avs/core"
	"github.com/eigencrosscow/avs/core/chainio"
	"github.com/eigencrosscow/avs/metrics"
	"github.com/eigencrosscow/avs/types"

	"github.com/Layr-Labs/eigensdk-go/chainio/clients"
	sdkelcontracts "github.com/Layr-Labs/eigensdk-go/chainio/clients/elcontracts"
	"github.com/Layr-Labs/eigensdk-go/chainio/clients/eth"
	"github.com/Layr-Labs/eigensdk-go/chainio/clients/wallet"
	"github.com/Layr-Labs/eigensdk-go/chainio/txmgr"
	"github.com/Layr-Labs/eigensdk-go/crypto/bls"
	sdkecdsa "github.com/Layr-Labs/eigensdk-go/crypto/ecdsa"
	sdklogging "github.com/Layr-Labs/eigensdk-go/logging"
	sdkmetrics "github.com/Layr-Labs/eigensdk-go/metrics"
	"github.com/Layr-Labs/eigensdk-go/metrics/collectors/economic"
	rpccalls "github.com/Layr-Labs/eigensdk-go/metrics/collectors/rpc_calls"
	"github.com/Layr-Labs/eigensdk-go/nodeapi"
	"github.com/Layr-Labs/eigensdk-go/signerv2"
	sdktypes "github.com/Layr-Labs/eigensdk-go/types"
)

const AVS_NAME = "crosscow-avs"
const SEM_VER = "0.1.0"

// CrossCoWOperator represents an EigenLayer AVS operator for cross-chain CoW trading
type CrossCoWOperator struct {
	config    types.NodeConfig
	logger    sdklogging.Logger
	ethClient sdkcommon.EthClientInterface

	// EigenLayer components
	metricsReg       *prometheus.Registry
	metrics          metrics.Metrics
	nodeApi          *nodeapi.NodeApi
	avsWriter        *chainio.AvsWriter
	avsReader        chainio.AvsReaderer
	avsSubscriber    chainio.AvsSubscriberer
	eigenlayerReader sdkelcontracts.ChainReader
	eigenlayerWriter sdkelcontracts.ChainWriter

	// Operator identity
	blsKeypair   *bls.KeyPair
	operatorId   sdktypes.OperatorId
	operatorAddr common.Address

	// CrossCoW specific
	newTaskCreatedChan        chan *CrossCoWTaskManager.ContractCrossCoWTaskManagerNewTradeMatchingTaskCreated
	aggregatorServerIpPortAddr string
	aggregatorRpcClient        AggregatorRpcClienter
	taskManagerAddr           common.Address
	matchingEngine            *MatchingEngine
}

// TradeMatchingTask represents a task from the TaskManager
type TradeMatchingTask struct {
	Intents         []Intent  `json:"intents"`
	MaxSlippage     *big.Int  `json:"maxSlippage"`
	Deadline        uint32    `json:"deadline"`
	TaskCreatedBlock uint32   `json:"taskCreatedBlock"`
	IntentPoolHash  [32]byte  `json:"intentPoolHash"`
}

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

// TradeMatchingResponse represents the operator's response
type TradeMatchingResponse struct {
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

// NewCrossCoWOperatorFromConfig creates a new CrossCoW operator
func NewCrossCoWOperatorFromConfig(c types.NodeConfig) (*CrossCoWOperator, error) {
	var logLevel sdklogging.LogLevel
	if c.Production {
		logLevel = sdklogging.Production
	} else {
		logLevel = sdklogging.Development
	}
	
	logger, err := sdklogging.NewZapLogger(logLevel)
	if err != nil {
		return nil, err
	}

	reg := prometheus.NewRegistry()
	eigenMetrics := sdkmetrics.NewEigenMetrics(AVS_NAME, c.EigenMetricsIpPortAddress, reg, logger)
	avsAndEigenMetrics := metrics.NewAvsAndEigenMetrics(AVS_NAME, eigenMetrics, reg)

	// Setup Node API
	nodeApi := nodeapi.NewNodeApi(AVS_NAME, SEM_VER, c.NodeApiIpPortAddress, logger)

	// Setup Ethereum clients
	var ethRpcClient, ethWsClient sdkcommon.EthClientInterface
	if c.EnableMetrics {
		rpcCallsCollector := rpccalls.NewCollector(AVS_NAME, reg)
		ethRpcClient, err = eth.NewInstrumentedClient(c.EthRpcUrl, rpcCallsCollector)
		if err != nil {
			logger.Errorf("Cannot create http ethclient", "err", err)
			return nil, err
		}
		ethWsClient, err = eth.NewInstrumentedClient(c.EthWsUrl, rpcCallsCollector)
		if err != nil {
			logger.Errorf("Cannot create ws ethclient", "err", err)
			return nil, err
		}
	} else {
		ethRpcClient, err = ethclient.Dial(c.EthRpcUrl)
		if err != nil {
			logger.Errorf("Cannot create http ethclient", "err", err)
			return nil, err
		}
		ethWsClient, err = ethclient.Dial(c.EthWsUrl)
		if err != nil {
			logger.Errorf("Cannot create ws ethclient", "err", err)
			return nil, err
		}
	}

	// Load BLS keypair
	blsKeyPassword, ok := os.LookupEnv("OPERATOR_BLS_KEY_PASSWORD")
	if !ok {
		logger.Warnf("OPERATOR_BLS_KEY_PASSWORD env var not set. using empty string")
	}
	blsKeyPair, err := bls.ReadPrivateKeyFromFile(c.BlsPrivateKeyStorePath, blsKeyPassword)
	if err != nil {
		logger.Errorf("Cannot parse bls private key", "err", err)
		return nil, err
	}

	// Get chain ID
	chainId, err := ethRpcClient.ChainID(context.Background())
	if err != nil {
		logger.Error("Cannot get chainId", "err", err)
		return nil, err
	}

	// Load ECDSA keypair
	ecdsaKeyPassword, ok := os.LookupEnv("OPERATOR_ECDSA_KEY_PASSWORD")
	if !ok {
		logger.Warnf("OPERATOR_ECDSA_KEY_PASSWORD env var not set. using empty string")
	}

	signerV2, _, err := signerv2.SignerFromConfig(signerv2.Config{
		KeystorePath: c.EcdsaPrivateKeyStorePath,
		Password:     ecdsaKeyPassword,
	}, chainId)
	if err != nil {
		panic(err)
	}
	chainWriter := sdkelcontracts.NewChainWriter(signerV2, ethRpcClient, logger)
	chainReader := sdkelcontracts.NewChainReader(ethRpcClient, logger)

	// Create AVS clients
	avsReader, err := chainio.NewAvsReaderFromConfig(c, ethRpcClient, logger)
	if err != nil {
		logger.Error("Cannot create avs reader", "err", err)
		return nil, err
	}
	
	avsWriter, err := chainio.NewAvsWriterFromConfig(c, ethRpcClient, logger)
	if err != nil {
		logger.Error("Cannot create avs writer", "err", err)
		return nil, err
	}

	avsSubscriber, err := chainio.NewAvsSubscriberFromConfig(c, ethWsClient, logger)
	if err != nil {
		logger.Error("Cannot create avs subscriber", "err", err)
		return nil, err
	}

	// Initialize matching engine
	matchingEngine, err := NewMatchingEngine(MatchingConfig{
		Algorithm:        c.MatchingAlgorithm,
		EnableAI:         c.EnableAIMatching,
		MaxIntentPoolSize: 10000,
		MinProfitThreshold: big.NewInt(1000),
	}, logger)
	if err != nil {
		logger.Error("Cannot create matching engine", "err", err)
		return nil, err
	}

	operator := &CrossCoWOperator{
		config:                     c,
		logger:                     logger,
		ethClient:                  ethRpcClient,
		metricsReg:                 reg,
		metrics:                    avsAndEigenMetrics,
		nodeApi:                    nodeApi,
		avsReader:                  avsReader,
		avsWriter:                  avsWriter,
		avsSubscriber:              avsSubscriber,
		eigenlayerReader:           chainReader,
		eigenlayerWriter:           chainWriter,
		blsKeypair:                 blsKeyPair,
		operatorAddr:               signerV2.Address,
		newTaskCreatedChan:         make(chan *CrossCoWTaskManager.ContractCrossCoWTaskManagerNewTradeMatchingTaskCreated, 100),
		aggregatorServerIpPortAddr: c.AggregatorServerIpPortAddress,
		taskManagerAddr:            common.HexToAddress(c.CrossCoWTaskManagerAddress),
		matchingEngine:             matchingEngine,
	}

	// Calculate operator ID
	operator.operatorId = sdktypes.OperatorIdFromG1Pubkey(blsKeyPair.PubkeyG1)

	logger.Info("Operator info",
		"operatorId", hex.EncodeToString(operator.operatorId[:]),
		"operatorAddr", operator.operatorAddr,
		"operatorG1Pubkey", operator.blsKeypair.PubkeyG1.String(),
		"operatorG2Pubkey", operator.blsKeypair.PubkeyG2.String(),
	)

	return operator, nil
}

// Start starts the operator's main event loop
func (o *CrossCoWOperator) Start(ctx context.Context) error {
	operatorIsRegistered, err := o.avsReader.IsOperatorRegistered(ctx, o.operatorAddr)
	if err != nil {
		o.logger.Error("Error checking if operator is registered", "err", err)
		return err
	}

	if !operatorIsRegistered {
		o.logger.Info("Operator not registered. Registering operator...")
		err = o.registerOperator()
		if err != nil {
			o.logger.Error("Error registering operator", "err", err)
			return err
		}
	}

	o.logger.Infof("Starting operator.")
	if o.config.EnableMetrics {
		o.metrics.Start(ctx, o.metricsReg)
	}
	o.nodeApi.Start()

	var metricsErrChan <-chan error
	if o.config.EnableMetrics {
		metricsErrChan = o.metrics.GetErrChan()
	} else {
		metricsErrChan = make(chan error, 1)
	}

	// Subscribe to new tasks
	sub := o.subscribeToNewTasks()
	o.logger.Info("Subscribed to new TaskManager tasks")

	for {
		select {
		case <-ctx.Done():
			return nil

		case err := <-metricsErrChan:
			// TODO(samlaf); we should also register the service manager as a prometheus metric
			// this will require creating a registry for each service (chain)
			o.logger.Fatal("Error in metrics server", "err", err)

		case err := <-sub.Err():
			o.logger.Error("Error in websocket subscription", "err", err)
			// TODO(samlaf): write retries logic

		case newTaskCreatedLog := <-o.newTaskCreatedChan:
			o.metrics.IncNumTasksReceived()
			taskResponse := o.ProcessNewTaskCreatedLog(newTaskCreatedLog)
			signedTaskResponse, err := o.SignTaskResponse(taskResponse)
			if err != nil {
				continue
			}
			go o.aggregatorRpcClient.SendSignedTaskResponseToAggregator(signedTaskResponse)
		}
	}
}

// ProcessNewTaskCreatedLog processes a new task from the TaskManager
func (o *CrossCoWOperator) ProcessNewTaskCreatedLog(newTaskCreatedLog *CrossCoWTaskManager.ContractCrossCoWTaskManagerNewTradeMatchingTaskCreated) *CrossCoWTaskManager.TradeMatchingResponse {
	o.logger.Debug("Received new task", "taskIndex", newTaskCreatedLog.TaskIndex)

	// Convert task from contract format
	task := &TradeMatchingTask{
		Intents:          convertContractIntents(newTaskCreatedLog.Task.Intents),
		MaxSlippage:      newTaskCreatedLog.Task.MaxSlippage,
		Deadline:         newTaskCreatedLog.Task.Deadline,
		TaskCreatedBlock: newTaskCreatedLog.Task.TaskCreatedBlock,
		IntentPoolHash:   newTaskCreatedLog.Task.IntentPoolHash,
	}

	// Process the matching logic
	matches, err := o.matchingEngine.FindOptimalMatches(task.Intents, task.MaxSlippage)
	if err != nil {
		o.logger.Error("Error finding matches", "err", err)
		// Return empty response on error
		return &CrossCoWTaskManager.TradeMatchingResponse{
			ReferenceTaskIndex: newTaskCreatedLog.TaskIndex,
			Matches:           []CrossCoWTaskManager.MatchedTrade{},
			TotalGasEstimate:  big.NewInt(0),
			ExecutionPriority: 0,
		}
	}

	// Convert matches to contract format
	contractMatches := make([]CrossCoWTaskManager.MatchedTrade, len(matches))
	totalGasEstimate := big.NewInt(0)
	
	for i, match := range matches {
		contractMatches[i] = CrossCoWTaskManager.MatchedTrade{
			IntentAIndex:    match.IntentAIndex,
			IntentBIndex:    match.IntentBIndex,
			ExecutionAmount: match.ExecutionAmount,
			BridgeFee:       match.BridgeFee,
			ExecutionProof:  match.ExecutionProof,
		}
		
		// Estimate gas for this match (simplified)
		gasEstimate := o.estimateGasForMatch(match)
		totalGasEstimate.Add(totalGasEstimate, gasEstimate)
	}

	taskResponse := &CrossCoWTaskManager.TradeMatchingResponse{
		ReferenceTaskIndex: newTaskCreatedLog.TaskIndex,
		Matches:           contractMatches,
		TotalGasEstimate:  totalGasEstimate,
		ExecutionPriority: o.calculateExecutionPriority(matches),
	}

	o.logger.Info("Processed task", 
		"taskIndex", newTaskCreatedLog.TaskIndex, 
		"matchesFound", len(matches),
		"gasEstimate", totalGasEstimate.String(),
	)

	return taskResponse
}

// SignTaskResponse signs the task response with BLS signature
func (o *CrossCoWOperator) SignTaskResponse(taskResponse *CrossCoWTaskManager.TradeMatchingResponse) (*SignedTaskResponse, error) {
	taskResponseHash, err := core.GetTaskResponseDigest(taskResponse)
	if err != nil {
		o.logger.Error("Error getting task response hash", "err", err)
		return nil, err
	}

	blsSignature := o.blsKeypair.SignMessage(taskResponseHash)
	signedTaskResponse := &SignedTaskResponse{
		TaskResponse: *taskResponse,
		BlsSignature: *blsSignature,
		OperatorId:   o.operatorId,
	}

	o.logger.Debug("Signed task response", "taskIndex", taskResponse.ReferenceTaskIndex)
	return signedTaskResponse, nil
}

// registerOperator registers the operator with EigenLayer and the AVS
func (o *CrossCoWOperator) registerOperator() error {
	// Register with EigenLayer
	err := o.eigenlayerWriter.RegisterAsOperator(context.Background(), o.operatorEcdsaPrivateKey)
	if err != nil {
		o.logger.Errorf("Error registering operator with eigenlayer", "err", err)
		return err
	}

	// Register with AVS
	operatorToAvsRegistrationSigSalt, operatorToAvsRegistrationSigExpiry, err := o.avsReader.GetOperatorToAvsRegistrationSalt(context.Background(), o.operatorAddr)
	if err != nil {
		o.logger.Errorf("Cannot get operator to AVS registration salt", "err", err)
		return err
	}

	operatorToAvsRegistrationSig, err := o.avsWriter.BuildAvsRegistrationMessage(o.operatorAddr, operatorToAvsRegistrationSigSalt, operatorToAvsRegistrationSigExpiry)
	if err != nil {
		o.logger.Errorf("Error building AVS registration message", "err", err)
		return err
	}

	_, err = o.avsWriter.RegisterOperatorInQuorumWithAVSRegistryCoordinator(
		context.Background(),
		o.operatorEcdsaPrivateKey,
		operatorToAvsRegistrationSig,
		o.blsKeypair,
		[]byte("0"), // quorum number 0
	)
	if err != nil {
		o.logger.Errorf("Error registering operator with avs registry coordinator", "err", err)
		return err
	}

	o.logger.Infof("Registered operator with AVS registry coordinator.")
	return nil
}

// subscribeToNewTasks subscribes to new task events from TaskManager
func (o *CrossCoWOperator) subscribeToNewTasks() Subscription {
	// Subscribe to NewTradeMatchingTaskCreated events
	return o.avsSubscriber.SubscribeToNewTasks(o.newTaskCreatedChan)
}

// estimateGasForMatch estimates gas cost for executing a matched trade
func (o *CrossCoWOperator) estimateGasForMatch(match *MatchedTrade) *big.Int {
	// Simplified gas estimation - in production would be more sophisticated
	baseGas := big.NewInt(21000)        // Base transaction cost
	bridgeGas := big.NewInt(150000)     // Estimated cross-chain bridge cost
	matchingGas := big.NewInt(50000)    // Matching validation cost
	
	totalGas := big.NewInt(0)
	totalGas.Add(totalGas, baseGas)
	totalGas.Add(totalGas, bridgeGas)
	totalGas.Add(totalGas, matchingGas)
	
	return totalGas
}

// calculateExecutionPriority calculates priority for task execution
func (o *CrossCoWOperator) calculateExecutionPriority(matches []*MatchedTrade) uint32 {
	if len(matches) == 0 {
		return 0
	}
	
	// Higher priority for more matches and larger amounts
	priority := uint32(len(matches) * 10)
	
	// Bonus for large trades
	totalValue := big.NewInt(0)
	for _, match := range matches {
		totalValue.Add(totalValue, match.ExecutionAmount)
	}
	
	// Add priority based on trade size (simplified)
	valueBonus := totalValue.Uint64() / 1000000 // 1 point per million wei
	if valueBonus > 1000 {
		valueBonus = 1000 // Cap bonus
	}
	
	return priority + uint32(valueBonus)
}

// Helper types and functions

type SignedTaskResponse struct {
	TaskResponse CrossCoWTaskManager.TradeMatchingResponse
	BlsSignature bls.Signature
	OperatorId   sdktypes.OperatorId
}

type AggregatorRpcClienter interface {
	SendSignedTaskResponseToAggregator(*SignedTaskResponse) error
}

type Subscription interface {
	Err() <-chan error
}

// convertContractIntents converts contract intents to internal format
func convertContractIntents(contractIntents []CrossCoWTaskManager.Intent) []Intent {
	intents := make([]Intent, len(contractIntents))
	for i, contractIntent := range contractIntents {
		intents[i] = Intent{
			User:              contractIntent.User,
			InputToken:        contractIntent.InputToken,
			OutputToken:       contractIntent.OutputToken,
			InputAmount:       contractIntent.InputAmount,
			MinOutputAmount:   contractIntent.MinOutputAmount,
			SourceChain:       contractIntent.SourceChain,
			DestinationChain:  contractIntent.DestinationChain,
			Deadline:          contractIntent.Deadline,
			Signature:         contractIntent.Signature,
		}
	}
	return intents
}