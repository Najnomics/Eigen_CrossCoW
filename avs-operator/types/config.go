package types

import (
	"time"
)

// NodeConfig defines the configuration for the operator node
type NodeConfig struct {
	// Ethereum configuration
	EthRpcUrl string `yaml:"eth_rpc_url"`
	EthWsUrl  string `yaml:"eth_ws_url"`
	
	// Operator configuration
	BlsPrivateKeyStorePath    string `yaml:"bls_private_key_store_path"`
	EcdsaPrivateKeyStorePath  string `yaml:"ecdsa_private_key_store_path"`
	OperatorAddress           string `yaml:"operator_address"`
	
	// AVS configuration
	CrossCoWTaskManagerAddress string `yaml:"crosscow_task_manager_address"`
	AggregatorServerIpPortAddress string `yaml:"aggregator_server_ip_port_address"`
	
	// Metrics configuration
	EnableMetrics           bool   `yaml:"enable_metrics"`
	EigenMetricsIpPortAddress string `yaml:"eigen_metrics_ip_port_address"`
	NodeApiIpPortAddress    string `yaml:"node_api_ip_port_address"`
	
	// Matching configuration
	MatchingAlgorithm       string `yaml:"matching_algorithm"`
	EnableAIMatching        bool   `yaml:"enable_ai_matching"`
	
	// Production settings
	Production              bool          `yaml:"production"`
	TaskTimeout             time.Duration `yaml:"task_timeout"`
	MaxConcurrentTasks      int           `yaml:"max_concurrent_tasks"`
	
	// Logging configuration
	LogLevel                string `yaml:"log_level"`
	LogFormat               string `yaml:"log_format"`
}

// DefaultNodeConfig returns a default configuration
func DefaultNodeConfig() *NodeConfig {
	return &NodeConfig{
		EthRpcUrl:                  "http://localhost:8545",
		EthWsUrl:                   "ws://localhost:8546",
		BlsPrivateKeyStorePath:     "./keys/bls_private_key.json",
		EcdsaPrivateKeyStorePath:   "./keys/ecdsa_private_key.json",
		CrossCoWTaskManagerAddress: "0x0000000000000000000000000000000000000000",
		AggregatorServerIpPortAddress: "localhost:8080",
		EnableMetrics:              true,
		EigenMetricsIpPortAddress:  "localhost:9090",
		NodeApiIpPortAddress:       "localhost:8081",
		MatchingAlgorithm:          "greedy",
		EnableAIMatching:           false,
		Production:                 false,
		TaskTimeout:                30 * time.Second,
		MaxConcurrentTasks:         10,
		LogLevel:                   "info",
		LogFormat:                  "json",
	}
}
