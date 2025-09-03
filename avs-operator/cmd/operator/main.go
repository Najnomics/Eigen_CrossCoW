package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/eigencrosscow/avs/pkg/operator"
	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
)

func main() {
	var configPath = flag.String("config", "configs/operator.json", "Path to operator configuration file")
	flag.Parse()

	// Initialize logger
	logger := initLogger()
	defer logger.Sync()

	logger.Info("Starting EigenCrossCoW AVS Operator", 
		"version", operator.SemVer,
		"configPath", *configPath,
	)

	// Load configuration
	config, err := loadConfig(*configPath)
	if err != nil {
		logger.Fatal("Failed to load configuration", zap.Error(err))
	}

	// Validate configuration
	if err := validateConfig(config); err != nil {
		logger.Fatal("Invalid configuration", zap.Error(err))
	}

	// Create operator instance
	op, err := operator.NewOperator(config, logger)
	if err != nil {
		logger.Fatal("Failed to create operator", zap.Error(err))
	}

	// Setup graceful shutdown
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Handle shutdown signals
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		sig := <-sigChan
		logger.Info("Received shutdown signal", zap.String("signal", sig.String()))
		cancel()
	}()

	// Start operator
	logger.Info("Starting operator services")
	if err := op.Start(ctx); err != nil {
		logger.Fatal("Operator failed", zap.Error(err))
	}

	logger.Info("EigenCrossCoW AVS Operator shut down successfully")
}

func initLogger() *zap.Logger {
	config := zap.NewProductionConfig()
	config.Level = zap.NewAtomicLevelAt(zap.InfoLevel)
	config.OutputPaths = []string{"stdout"}
	config.ErrorOutputPaths = []string{"stderr"}
	config.EncoderConfig.TimeKey = "timestamp"
	config.EncoderConfig.EncodeTime = zapcore.ISO8601TimeEncoder
	config.EncoderConfig.LevelKey = "level"
	config.EncoderConfig.EncodeLevel = zapcore.CapitalLevelEncoder
	config.EncoderConfig.CallerKey = "caller"
	config.EncoderConfig.EncodeCaller = zapcore.ShortCallerEncoder
	config.EncoderConfig.MessageKey = "message"
	config.EncoderConfig.StacktraceKey = "stacktrace"

	logger, err := config.Build()
	if err != nil {
		panic(fmt.Sprintf("Failed to initialize logger: %v", err))
	}

	return logger
}

func loadConfig(path string) (operator.Config, error) {
	var config operator.Config

	file, err := os.Open(path)
	if err != nil {
		return config, fmt.Errorf("failed to open config file: %w", err)
	}
	defer file.Close()

	decoder := json.NewDecoder(file)
	if err := decoder.Decode(&config); err != nil {
		return config, fmt.Errorf("failed to parse config file: %w", err)
	}

	return config, nil
}

func validateConfig(config operator.Config) error {
	if config.EcdsaPrivateKeyStorePath == "" {
		return fmt.Errorf("ECDSA private key store path is required")
	}

	if config.BlsPrivateKeyStorePath == "" {
		return fmt.Errorf("BLS private key store path is required")
	}

	if config.EthRpcUrl == "" {
		return fmt.Errorf("Ethereum RPC URL is required")
	}

	if config.ServiceManagerAddress == "" {
		return fmt.Errorf("Service manager address is required")
	}

	if config.AcrossHubPoolAddress == "" {
		return fmt.Errorf("Across hub pool address is required")
	}

	if config.MaxConcurrentTasks <= 0 {
		config.MaxConcurrentTasks = 10 // Default value
	}

	if config.TaskTimeout <= 0 {
		config.TaskTimeout = 300 // Default 5 minutes
	}

	return nil
}