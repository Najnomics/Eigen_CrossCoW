package config

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/spf13/viper"
)

// Config represents the complete configuration for the AVS operator
type Config struct {
	// Operator configuration
	Operator OperatorConfig `json:"operator" mapstructure:"operator"`
	
	// Ethereum configuration
	Ethereum EthereumConfig `json:"ethereum" mapstructure:"ethereum"`
	
	// AVS configuration
	AVS AVSConfig `json:"avs" mapstructure:"avs"`
	
	// Monitoring configuration
	Monitoring MonitoringConfig `json:"monitoring" mapstructure:"monitoring"`
	
	// Logging configuration
	Logging LoggingConfig `json:"logging" mapstructure:"logging"`
	
	// Security configuration
	Security SecurityConfig `json:"security" mapstructure:"security"`
	
	// Performance configuration
	Performance PerformanceConfig `json:"performance" mapstructure:"performance"`
}

// OperatorConfig contains operator-specific configuration
type OperatorConfig struct {
	// Operator address
	Address common.Address `json:"address" mapstructure:"address"`
	
	// ECDSA private key path
	EcdsaPrivateKeyPath string `json:"ecdsaPrivateKeyPath" mapstructure:"ecdsaPrivateKeyPath"`
	
	// BLS private key path
	BlsPrivateKeyPath string `json:"blsPrivateKeyPath" mapstructure:"blsPrivateKeyPath"`
	
	// Operator name
	Name string `json:"name" mapstructure:"name"`
	
	// Operator description
	Description string `json:"description" mapstructure:"description"`
	
	// Minimum stake required
	MinStake string `json:"minStake" mapstructure:"minStake"`
	
	// Maximum stake allowed
	MaxStake string `json:"maxStake" mapstructure:"maxStake"`
}

// EthereumConfig contains Ethereum-related configuration
type EthereumConfig struct {
	// RPC URL
	RpcURL string `json:"rpcUrl" mapstructure:"rpcUrl"`
	
	// WebSocket URL
	WsURL string `json:"wsUrl" mapstructure:"wsUrl"`
	
	// Chain ID
	ChainID int64 `json:"chainId" mapstructure:"chainId"`
	
	// Gas price (in wei)
	GasPrice string `json:"gasPrice" mapstructure:"gasPrice"`
	
	// Gas limit
	GasLimit uint64 `json:"gasLimit" mapstructure:"gasLimit"`
	
	// Transaction timeout
	TxTimeout time.Duration `json:"txTimeout" mapstructure:"txTimeout"`
	
	// Block confirmation count
	Confirmations int64 `json:"confirmations" mapstructure:"confirmations"`
}

// AVSConfig contains AVS-specific configuration
type AVSConfig struct {
	// Service manager address
	ServiceManagerAddress common.Address `json:"serviceManagerAddress" mapstructure:"serviceManagerAddress"`
	
	// Registry coordinator address
	RegistryCoordinatorAddress common.Address `json:"registryCoordinatorAddress" mapstructure:"registryCoordinatorAddress"`
	
	// Stake registry address
	StakeRegistryAddress common.Address `json:"stakeRegistryAddress" mapstructure:"stakeRegistryAddress"`
	
	// BLS APK registry address
	BlsApkRegistryAddress common.Address `json:"blsApkRegistryAddress" mapstructure:"blsApkRegistryAddress"`
	
	// Task manager address
	TaskManagerAddress common.Address `json:"taskManagerAddress" mapstructure:"taskManagerAddress"`
	
	// Aggregator address
	AggregatorAddress common.Address `json:"aggregatorAddress" mapstructure:"aggregatorAddress"`
	
	// Quorum numbers
	QuorumNumbers []byte `json:"quorumNumbers" mapstructure:"quorumNumbers"`
	
	// Socket address
	Socket string `json:"socket" mapstructure:"socket"`
}

// MonitoringConfig contains monitoring configuration
type MonitoringConfig struct {
	// Enable metrics
	Enabled bool `json:"enabled" mapstructure:"enabled"`
	
	// Metrics port
	Port int `json:"port" mapstructure:"port"`
	
	// Metrics path
	Path string `json:"path" mapstructure:"path"`
	
	// Prometheus configuration
	Prometheus PrometheusConfig `json:"prometheus" mapstructure:"prometheus"`
	
	// Health check configuration
	HealthCheck HealthCheckConfig `json:"healthCheck" mapstructure:"healthCheck"`
}

// PrometheusConfig contains Prometheus-specific configuration
type PrometheusConfig struct {
	// Enable Prometheus metrics
	Enabled bool `json:"enabled" mapstructure:"enabled"`
	
	// Metrics namespace
	Namespace string `json:"namespace" mapstructure:"namespace"`
	
	// Metrics subsystem
	Subsystem string `json:"subsystem" mapstructure:"subsystem"`
}

// HealthCheckConfig contains health check configuration
type HealthCheckConfig struct {
	// Enable health checks
	Enabled bool `json:"enabled" mapstructure:"enabled"`
	
	// Health check port
	Port int `json:"port" mapstructure:"port"`
	
	// Health check interval
	Interval time.Duration `json:"interval" mapstructure:"interval"`
	
	// Health check timeout
	Timeout time.Duration `json:"timeout" mapstructure:"timeout"`
}

// LoggingConfig contains logging configuration
type LoggingConfig struct {
	// Log level
	Level string `json:"level" mapstructure:"level"`
	
	// Log format
	Format string `json:"format" mapstructure:"format"`
	
	// Log file path
	FilePath string `json:"filePath" mapstructure:"filePath"`
	
	// Enable console logging
	Console bool `json:"console" mapstructure:"console"`
	
	// Enable file logging
	File bool `json:"file" mapstructure:"file"`
	
	// Log rotation
	Rotation LogRotationConfig `json:"rotation" mapstructure:"rotation"`
}

// LogRotationConfig contains log rotation configuration
type LogRotationConfig struct {
	// Enable log rotation
	Enabled bool `json:"enabled" mapstructure:"enabled"`
	
	// Maximum file size (in MB)
	MaxSize int `json:"maxSize" mapstructure:"maxSize"`
	
	// Maximum number of files
	MaxFiles int `json:"maxFiles" mapstructure:"maxFiles"`
	
	// Maximum age (in days)
	MaxAge int `json:"maxAge" mapstructure:"maxAge"`
}

// SecurityConfig contains security configuration
type SecurityConfig struct {
	// Enable BLS signature verification
	EnableBLS bool `json:"enableBLS" mapstructure:"enableBLS"`
	
	// Enable ECDSA signature verification
	EnableECDSA bool `json:"enableECDSA" mapstructure:"enableECDSA"`
	
	// Signature verification timeout
	SignatureTimeout time.Duration `json:"signatureTimeout" mapstructure:"signatureTimeout"`
	
	// Maximum signature age
	MaxSignatureAge time.Duration `json:"maxSignatureAge" mapstructure:"maxSignatureAge"`
	
	// Rate limiting
	RateLimit RateLimitConfig `json:"rateLimit" mapstructure:"rateLimit"`
}

// RateLimitConfig contains rate limiting configuration
type RateLimitConfig struct {
	// Enable rate limiting
	Enabled bool `json:"enabled" mapstructure:"enabled"`
	
	// Requests per second
	RPS int `json:"rps" mapstructure:"rps"`
	
	// Burst size
	Burst int `json:"burst" mapstructure:"burst"`
}

// PerformanceConfig contains performance configuration
type PerformanceConfig struct {
	// Maximum concurrent tasks
	MaxConcurrentTasks int `json:"maxConcurrentTasks" mapstructure:"maxConcurrentTasks"`
	
	// Task processing timeout
	TaskTimeout time.Duration `json:"taskTimeout" mapstructure:"taskTimeout"`
	
	// Event processing timeout
	EventTimeout time.Duration `json:"eventTimeout" mapstructure:"eventTimeout"`
	
	// Cache configuration
	Cache CacheConfig `json:"cache" mapstructure:"cache"`
	
	// Database configuration
	Database DatabaseConfig `json:"database" mapstructure:"database"`
}

// CacheConfig contains cache configuration
type CacheConfig struct {
	// Enable caching
	Enabled bool `json:"enabled" mapstructure:"enabled"`
	
	// Cache size
	Size int `json:"size" mapstructure:"size"`
	
	// Cache TTL
	TTL time.Duration `json:"ttl" mapstructure:"ttl"`
}

// DatabaseConfig contains database configuration
type DatabaseConfig struct {
	// Database type
	Type string `json:"type" mapstructure:"type"`
	
	// Database URL
	URL string `json:"url" mapstructure:"url"`
	
	// Connection pool size
	PoolSize int `json:"poolSize" mapstructure:"poolSize"`
	
	// Connection timeout
	Timeout time.Duration `json:"timeout" mapstructure:"timeout"`
}

// LoadConfig loads configuration from file and environment variables
func LoadConfig(configPath string) (*Config, error) {
	// Set default values
	setDefaults()
	
	// Load from file if provided
	if configPath != "" {
		viper.SetConfigFile(configPath)
		if err := viper.ReadInConfig(); err != nil {
			return nil, fmt.Errorf("failed to read config file: %w", err)
		}
	}
	
	// Load from environment variables
	viper.AutomaticEnv()
	
	// Unmarshal into config struct
	var config Config
	if err := viper.Unmarshal(&config); err != nil {
		return nil, fmt.Errorf("failed to unmarshal config: %w", err)
	}
	
	// Validate configuration
	if err := config.Validate(); err != nil {
		return nil, fmt.Errorf("config validation failed: %w", err)
	}
	
	return &config, nil
}

// setDefaults sets default configuration values
func setDefaults() {
	// Operator defaults
	viper.SetDefault("operator.name", "eigencrosscow-operator")
	viper.SetDefault("operator.description", "EigenCrossCoW AVS Operator")
	viper.SetDefault("operator.minStake", "1000000000000000000") // 1 ETH
	viper.SetDefault("operator.maxStake", "1000000000000000000000") // 1000 ETH
	
	// Ethereum defaults
	viper.SetDefault("ethereum.chainId", 1)
	viper.SetDefault("ethereum.gasPrice", "20000000000") // 20 gwei
	viper.SetDefault("ethereum.gasLimit", 1000000)
	viper.SetDefault("ethereum.txTimeout", "30s")
	viper.SetDefault("ethereum.confirmations", 1)
	
	// AVS defaults
	viper.SetDefault("avs.quorumNumbers", []byte{0})
	viper.SetDefault("avs.socket", "")
	
	// Monitoring defaults
	viper.SetDefault("monitoring.enabled", true)
	viper.SetDefault("monitoring.port", 9000)
	viper.SetDefault("monitoring.path", "/metrics")
	viper.SetDefault("monitoring.prometheus.enabled", true)
	viper.SetDefault("monitoring.prometheus.namespace", "eigencrosscow")
	viper.SetDefault("monitoring.prometheus.subsystem", "avs")
	viper.SetDefault("monitoring.healthCheck.enabled", true)
	viper.SetDefault("monitoring.healthCheck.port", 8080)
	viper.SetDefault("monitoring.healthCheck.interval", "30s")
	viper.SetDefault("monitoring.healthCheck.timeout", "5s")
	
	// Logging defaults
	viper.SetDefault("logging.level", "info")
	viper.SetDefault("logging.format", "json")
	viper.SetDefault("logging.console", true)
	viper.SetDefault("logging.file", false)
	viper.SetDefault("logging.rotation.enabled", true)
	viper.SetDefault("logging.rotation.maxSize", 100)
	viper.SetDefault("logging.rotation.maxFiles", 10)
	viper.SetDefault("logging.rotation.maxAge", 30)
	
	// Security defaults
	viper.SetDefault("security.enableBLS", true)
	viper.SetDefault("security.enableECDSA", true)
	viper.SetDefault("security.signatureTimeout", "30s")
	viper.SetDefault("security.maxSignatureAge", "1h")
	viper.SetDefault("security.rateLimit.enabled", true)
	viper.SetDefault("security.rateLimit.rps", 100)
	viper.SetDefault("security.rateLimit.burst", 200)
	
	// Performance defaults
	viper.SetDefault("performance.maxConcurrentTasks", 10)
	viper.SetDefault("performance.taskTimeout", "5m")
	viper.SetDefault("performance.eventTimeout", "1m")
	viper.SetDefault("performance.cache.enabled", true)
	viper.SetDefault("performance.cache.size", 1000)
	viper.SetDefault("performance.cache.ttl", "1h")
	viper.SetDefault("performance.database.type", "redis")
	viper.SetDefault("performance.database.poolSize", 10)
	viper.SetDefault("performance.database.timeout", "30s")
}

// Validate validates the configuration
func (c *Config) Validate() error {
	// Validate operator configuration
	if c.Operator.Address == (common.Address{}) {
		return fmt.Errorf("operator address is required")
	}
	
	if c.Operator.EcdsaPrivateKeyPath == "" {
		return fmt.Errorf("ECDSA private key path is required")
	}
	
	if c.Operator.BlsPrivateKeyPath == "" {
		return fmt.Errorf("BLS private key path is required")
	}
	
	// Validate Ethereum configuration
	if c.Ethereum.RpcURL == "" {
		return fmt.Errorf("Ethereum RPC URL is required")
	}
	
	if c.Ethereum.ChainID <= 0 {
		return fmt.Errorf("invalid chain ID: %d", c.Ethereum.ChainID)
	}
	
	// Validate AVS configuration
	if c.AVS.ServiceManagerAddress == (common.Address{}) {
		return fmt.Errorf("service manager address is required")
	}
	
	if c.AVS.RegistryCoordinatorAddress == (common.Address{}) {
		return fmt.Errorf("registry coordinator address is required")
	}
	
	if c.AVS.StakeRegistryAddress == (common.Address{}) {
		return fmt.Errorf("stake registry address is required")
	}
	
	if c.AVS.BlsApkRegistryAddress == (common.Address{}) {
		return fmt.Errorf("BLS APK registry address is required")
	}
	
	if c.AVS.TaskManagerAddress == (common.Address{}) {
		return fmt.Errorf("task manager address is required")
	}
	
	// Validate monitoring configuration
	if c.Monitoring.Enabled && c.Monitoring.Port <= 0 {
		return fmt.Errorf("invalid monitoring port: %d", c.Monitoring.Port)
	}
	
	// Validate logging configuration
	if c.Logging.Level == "" {
		return fmt.Errorf("log level is required")
	}
	
	// Validate performance configuration
	if c.Performance.MaxConcurrentTasks <= 0 {
		return fmt.Errorf("invalid max concurrent tasks: %d", c.Performance.MaxConcurrentTasks)
	}
	
	return nil
}

// SaveConfig saves configuration to file
func (c *Config) SaveConfig(configPath string) error {
	// Create directory if it doesn't exist
	dir := filepath.Dir(configPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create config directory: %w", err)
	}
	
	// Marshal to JSON
	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal config: %w", err)
	}
	
	// Write to file
	if err := os.WriteFile(configPath, data, 0644); err != nil {
		return fmt.Errorf("failed to write config file: %w", err)
	}
	
	return nil
}

// GetDefaultConfigPath returns the default config path
func GetDefaultConfigPath() string {
	return "config/operator.yaml"
}

// GetConfigPaths returns possible config file paths
func GetConfigPaths() []string {
	return []string{
		"config/operator.yaml",
		"config/operator.json",
		"operator.yaml",
		"operator.json",
		"./config.yaml",
		"./config.json",
	}
}