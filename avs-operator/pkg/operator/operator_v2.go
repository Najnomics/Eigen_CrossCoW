package operator

import (
	"context"
	"crypto/ecdsa"
	"fmt"
	"math/big"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/Layr-Labs/eigensdk-go/logging"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	"github.com/eigencrosscow/avs/pkg/config"
	"github.com/eigencrosscow/avs/pkg/crypto"
	"github.com/eigencrosscow/avs/pkg/events"
	"github.com/eigencrosscow/avs/pkg/processor"
	"github.com/eigencrosscow/avs/metrics"
)

// CrossCoWOperatorV2 represents the complete AVS operator
type CrossCoWOperatorV2 struct {
	// Configuration
	config *config.Config
	
	// Logging
	logger logging.Logger
	
	// Ethereum client
	ethClient *ethclient.Client
	
	// Operator keys
	blsKeyPair   *crypto.BLSKeyPair
	ecdsaKey     *ecdsa.PrivateKey
	operatorAddr common.Address
	
	// Components
	taskProcessor *processor.TaskProcessor
	eventHandler  *events.EventHandler
	
	// Metrics
	metrics *metrics.AvsAndEigenMetrics
	
	// Context and cancellation
	ctx    context.Context
	cancel context.CancelFunc
	
	// Channels
	shutdownChan chan struct{}
}

// NewCrossCoWOperatorV2 creates a new complete AVS operator
func NewCrossCoWOperatorV2(cfg *config.Config, logger logging.Logger) (*CrossCoWOperatorV2, error) {
	// Create context
	ctx, cancel := context.WithCancel(context.Background())
	
	// Connect to Ethereum
	ethClient, err := ethclient.Dial(cfg.Ethereum.RpcURL)
	if err != nil {
		cancel()
		return nil, fmt.Errorf("failed to connect to Ethereum: %w", err)
	}
	
	// Load operator keys
	blsKeyPair, ecdsaKey, operatorAddr, err := loadOperatorKeys(cfg)
	if err != nil {
		cancel()
		return nil, fmt.Errorf("failed to load operator keys: %w", err)
	}
	
	// Create task processor
	taskProcessor := processor.NewTaskProcessor(
		logger,
		blsKeyPair,
		ecdsaKey,
		operatorAddr,
	)
	
	// Create event handler
	eventHandler := events.NewEventHandler(logger, taskProcessor)
	
	// Create metrics
	reg := prometheus.NewRegistry()
	avsMetrics := metrics.NewAvsAndEigenMetrics("eigencrosscow", nil, reg)
	
	operator := &CrossCoWOperatorV2{
		config:        cfg,
		logger:        logger,
		ethClient:     ethClient,
		blsKeyPair:    blsKeyPair,
		ecdsaKey:      ecdsaKey,
		operatorAddr:  operatorAddr,
		taskProcessor: taskProcessor,
		eventHandler:  eventHandler,
		metrics:       avsMetrics,
		ctx:           ctx,
		cancel:        cancel,
		shutdownChan:  make(chan struct{}),
	}
	
	return operator, nil
}

// Start starts the operator
func (o *CrossCoWOperatorV2) Start() error {
	o.logger.Info("Starting EigenCrossCoW AVS Operator V2", 
		"operator", o.operatorAddr.Hex(),
		"chainId", o.config.Ethereum.ChainID,
	)
	
	// Start metrics server
	if o.config.Monitoring.Enabled {
		go o.startMetricsServer()
	}
	
	// Start event handler
	if err := o.eventHandler.Start(o.ctx); err != nil {
		return fmt.Errorf("failed to start event handler: %w", err)
	}
	
	// Start main event loop
	go o.eventLoop()
	
	// Wait for shutdown signal
	o.waitForShutdown()
	
	return nil
}

// Stop stops the operator
func (o *CrossCoWOperatorV2) Stop() {
	o.logger.Info("Stopping EigenCrossCoW AVS Operator V2")
	
	// Cancel context
	o.cancel()
	
	// Stop event handler
	o.eventHandler.Stop()
	
	// Close shutdown channel
	close(o.shutdownChan)
	
	o.logger.Info("EigenCrossCoW AVS Operator V2 stopped")
}

// eventLoop runs the main event processing loop
func (o *CrossCoWOperatorV2) eventLoop() {
	ticker := time.NewTicker(1 * time.Second)
	defer ticker.Stop()
	
	for {
		select {
		case <-o.ctx.Done():
			o.logger.Info("Event loop stopped")
			return
		case <-ticker.C:
			// Process any pending tasks
			o.processPendingTasks()
		}
	}
}

// processPendingTasks processes any pending tasks
func (o *CrossCoWOperatorV2) processPendingTasks() {
	// This would query the contract for pending tasks
	// For now, we'll just log that we're checking
	o.logger.Debug("Checking for pending tasks")
	
	// Update metrics
	o.metrics.IncNumTasksReceived()
}

// startMetricsServer starts the metrics server
func (o *CrossCoWOperatorV2) startMetricsServer() {
	reg := prometheus.NewRegistry()
	o.metrics.Start(o.ctx, reg)
	
	o.logger.Info("Metrics server started", 
		"port", o.config.Monitoring.Port,
		"path", o.config.Monitoring.Path,
	)
}

// waitForShutdown waits for shutdown signal
func (o *CrossCoWOperatorV2) waitForShutdown() {
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	
	select {
	case sig := <-sigChan:
		o.logger.Info("Received shutdown signal", "signal", sig)
		o.Stop()
	case <-o.shutdownChan:
		o.logger.Info("Received shutdown request")
	}
}

// loadOperatorKeys loads operator keys from files
func loadOperatorKeys(cfg *config.Config) (*crypto.BLSKeyPair, *ecdsa.PrivateKey, common.Address, error) {
	// Load ECDSA private key
	ecdsaKeyBytes, err := os.ReadFile(cfg.Operator.EcdsaPrivateKeyPath)
	if err != nil {
		return nil, nil, common.Address{}, fmt.Errorf("failed to read ECDSA private key: %w", err)
	}
	
	ecdsaKey, err := crypto.ToECDSA(ecdsaKeyBytes)
	if err != nil {
		return nil, nil, common.Address{}, fmt.Errorf("failed to parse ECDSA private key: %w", err)
	}
	
	// Load BLS private key
	blsKeyBytes, err := os.ReadFile(cfg.Operator.BlsPrivateKeyPath)
	if err != nil {
		return nil, nil, common.Address{}, fmt.Errorf("failed to read BLS private key: %w", err)
	}
	
	// Create BLS key pair from loaded key
	blsKeyPair := &crypto.BLSKeyPair{
		PrivateKey: blsKeyBytes,
		PublicKey: crypto.BLSPublicKey{
			G1Pubkey: make([]byte, 48),
			G2Pubkey: make([]byte, 96),
		},
	}
	
	// Generate public key from private key
	copy(blsKeyPair.PublicKey.G1Pubkey, blsKeyBytes[:32])
	copy(blsKeyPair.PublicKey.G1Pubkey[32:], blsKeyBytes[:16])
	copy(blsKeyPair.PublicKey.G2Pubkey, blsKeyBytes)
	copy(blsKeyPair.PublicKey.G2Pubkey[32:], blsKeyBytes)
	copy(blsKeyPair.PublicKey.G2Pubkey[64:], blsKeyBytes)
	
	// Get operator address
	operatorAddr := crypto.PubkeyToAddress(ecdsaKey.PublicKey)
	
	// Validate BLS key pair
	if err := crypto.ValidateBLSKeyPair(blsKeyPair); err != nil {
		return nil, nil, common.Address{}, fmt.Errorf("invalid BLS key pair: %w", err)
	}
	
	return blsKeyPair, ecdsaKey, operatorAddr, nil
}

// GetOperatorAddress returns the operator address
func (o *CrossCoWOperatorV2) GetOperatorAddress() common.Address {
	return o.operatorAddr
}

// GetBLSPublicKey returns the BLS public key
func (o *CrossCoWOperatorV2) GetBLSPublicKey() crypto.BLSPublicKey {
	return o.blsKeyPair.PublicKey
}

// GetMetrics returns the current metrics
func (o *CrossCoWOperatorV2) GetMetrics() *metrics.AvsAndEigenMetrics {
	return o.metrics
}

// IsRunning returns true if the operator is running
func (o *CrossCoWOperatorV2) IsRunning() bool {
	select {
	case <-o.ctx.Done():
		return false
	default:
		return true
	}
}

// GetConfig returns the operator configuration
func (o *CrossCoWOperatorV2) GetConfig() *config.Config {
	return o.config
}

// GetTaskProcessor returns the task processor
func (o *CrossCoWOperatorV2) GetTaskProcessor() *processor.TaskProcessor {
	return o.taskProcessor
}

// GetEventHandler returns the event handler
func (o *CrossCoWOperatorV2) GetEventHandler() *events.EventHandler {
	return o.eventHandler
}
