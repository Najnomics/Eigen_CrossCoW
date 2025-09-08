package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"

	"github.com/Layr-Labs/eigensdk-go/logging"
	"github.com/urfave/cli"
	"gopkg.in/yaml.v2"

	"../../pkg/operator"
)

var (
	// Version information
	Version   = "dev"
	GitCommit = "unknown"
	BuildTime = "unknown"
)

func main() {
	app := cli.NewApp()
	app.Flags = []cli.Flag{
		cli.StringFlag{
			Name:     "config",
			Usage:    "Load configuration from `FILE`",
			Required: true,
		},
		cli.StringFlag{
			Name:  "log-level",
			Usage: "Logging level (debug, info, warn, error)",
			Value: "info",
		},
	}
	app.Name = "crosscow-simple-operator"
	app.Usage = "CrossCoW AVS Simple Operator"
	app.Description = "Simple EigenLayer AVS Operator for cross-chain CoW trading"
	app.Version = fmt.Sprintf("%s (commit: %s, built: %s)", Version, GitCommit, BuildTime)
	
	app.Action = operatorMain
	
	err := app.Run(os.Args)
	if err != nil {
		log.Fatalln("Application failed:", err)
	}
}

func operatorMain(ctx *cli.Context) error {
	log.Println("Starting CrossCoW AVS Simple Operator")

	configPath := ctx.GlobalString("config")

	// Load configuration
	config, err := loadConfig(configPath)
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	// Initialize logger
	logger, err := logging.NewZapLogger(logging.Development)
	if err != nil {
		return fmt.Errorf("failed to create logger: %w", err)
	}
	logger.Info("CrossCoW AVS Simple Operator starting", "version", Version, "config", configPath)

	// Create operator
	op, err := operator.NewOperator(*config, logger)
	if err != nil {
		return fmt.Errorf("failed to create operator: %w", err)
	}

	// Create context for graceful shutdown
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Handle shutdown signals
	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-c
		logger.Info("Received shutdown signal, shutting down gracefully")
		cancel()
	}()

	// Start operator
	logger.Info("Starting CrossCoW AVS Simple Operator")
	err = op.Start(ctx)
	if err != nil {
		return fmt.Errorf("operator failed: %w", err)
	}

	logger.Info("CrossCoW AVS Simple Operator stopped")
	return nil
}

func loadConfig(configPath string) (*operator.Config, error) {
	if configPath == "" {
		return nil, fmt.Errorf("config path is required")
	}

	// Make path absolute
	absPath, err := filepath.Abs(configPath)
	if err != nil {
		return nil, fmt.Errorf("failed to get absolute path: %w", err)
	}

	// Read config file
	configFile, err := os.ReadFile(absPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}

	// Determine file type and unmarshal
	var config operator.Config
	ext := filepath.Ext(absPath)
	
	switch ext {
	case ".yaml", ".yml":
		err = yaml.Unmarshal(configFile, &config)
	case ".json":
		err = json.Unmarshal(configFile, &config)
	default:
		return nil, fmt.Errorf("unsupported config file format: %s (supported: .yaml, .yml, .json)", ext)
	}
	
	if err != nil {
		return nil, fmt.Errorf("failed to unmarshal config: %w", err)
	}

	// Validate required fields
	if config.EcdsaPrivateKeyStorePath == "" {
		return nil, fmt.Errorf("ecdsa_private_key_store_path is required")
	}
	if config.BlsPrivateKeyStorePath == "" {
		return nil, fmt.Errorf("bls_private_key_store_path is required")
	}
	if config.EthRpcUrl == "" {
		return nil, fmt.Errorf("eth_rpc_url is required")
	}
	if config.TaskManagerAddress == "" {
		return nil, fmt.Errorf("task_manager_address is required")
	}

	return &config, nil
}