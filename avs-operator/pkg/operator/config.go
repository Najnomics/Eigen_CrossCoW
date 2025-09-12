package operator

import (
	"time"
)

// Config defines the configuration for the operator
type Config struct {
	// Ethereum configuration
	EthRpcUrl string `yaml:"eth_rpc_url" json:"eth_rpc_url"`
	EthWsUrl  string `yaml:"eth_ws_url" json:"eth_ws_url"`
	
	// Operator configuration
	BlsPrivateKeyStorePath    string `yaml:"bls_private_key_store_path" json:"bls_private_key_store_path"`
	EcdsaPrivateKeyStorePath  string `yaml:"ecdsa_private_key_store_path" json:"ecdsa_private_key_store_path"`
	OperatorAddress           string `yaml:"operator_address" json:"operator_address"`
	
	// AVS configuration
	TaskManagerAddress        string `yaml:"task_manager_address" json:"task_manager_address"`
	AggregatorServerIpPortAddress string `yaml:"aggregator_server_ip_port_address" json:"aggregator_server_ip_port_address"`
	
	// Metrics configuration
	EnableMetrics           bool   `yaml:"enable_metrics" json:"enable_metrics"`
	EigenMetricsIpPortAddress string `yaml:"eigen_metrics_ip_port_address" json:"eigen_metrics_ip_port_address"`
	NodeApiIpPortAddress    string `yaml:"node_api_ip_port_address" json:"node_api_ip_port_address"`
	
	// Matching configuration
	MatchingAlgorithm       string `yaml:"matching_algorithm" json:"matching_algorithm"`
	EnableAIMatching        bool   `yaml:"enable_ai_matching" json:"enable_ai_matching"`
	
	// Production settings
	Production              bool          `yaml:"production" json:"production"`
	TaskTimeout             time.Duration `yaml:"task_timeout" json:"task_timeout"`
	MaxConcurrentTasks      int           `yaml:"max_concurrent_tasks" json:"max_concurrent_tasks"`
	
	// Logging configuration
	LogLevel                string `yaml:"log_level" json:"log_level"`
	LogFormat               string `yaml:"log_format" json:"log_format"`
}

// DefaultConfig returns a default configuration
func DefaultConfig() *Config {
	return &Config{
		EthRpcUrl:                  "http://localhost:8545",
		EthWsUrl:                   "ws://localhost:8546",
		BlsPrivateKeyStorePath:     "./keys/bls_private_key.json",
		EcdsaPrivateKeyStorePath:   "./keys/ecdsa_private_key.json",
		TaskManagerAddress:         "0x0000000000000000000000000000000000000000",
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
