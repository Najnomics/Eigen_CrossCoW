package config

import (
	"fmt"
	"math/big"
	"os"
	"path/filepath"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/fsnotify/fsnotify"
	"github.com/spf13/viper"
	"go.uber.org/zap"
	"gopkg.in/yaml.v3"
)

// Config represents the complete operator configuration
type Config struct {
	// Core operator settings
	Operator OperatorConfig `mapstructure:"operator" yaml:"operator"`
	
	// Ethereum and blockchain settings
	Ethereum EthereumConfig `mapstructure:"ethereum" yaml:"ethereum"`
	
	// EigenLayer specific settings
	EigenLayer EigenLayerConfig `mapstructure:"eigenlayer" yaml:"eigenlayer"`
	
	// Across Protocol settings
	Across AcrossConfig `mapstructure:"across" yaml:"across"`
	
	// Matching engine settings
	Matching MatchingConfig `mapstructure:"matching" yaml:"matching"`
	
	// Monitoring and metrics
	Monitoring MonitoringConfig `mapstructure:"monitoring" yaml:"monitoring"`
	
	// Logging configuration
	Logging LoggingConfig `mapstructure:"logging" yaml:"logging"`
	
	// Security settings
	Security SecurityConfig `mapstructure:"security" yaml:"security"`
}

// OperatorConfig contains core operator settings
type OperatorConfig struct {
	Name                     string        `mapstructure:"name" yaml:"name"`
	Version                  string        `mapstructure:"version" yaml:"version"`
	Description              string        `mapstructure:"description" yaml:"description"`
	RegisterOnStartup        bool          `mapstructure:"register_on_startup" yaml:"register_on_startup"`
	MaxConcurrentTasks       int           `mapstructure:"max_concurrent_tasks" yaml:"max_concurrent_tasks"`
	TaskTimeout              time.Duration `mapstructure:"task_timeout" yaml:"task_timeout"`
	GracefulShutdownTimeout  time.Duration `mapstructure:"graceful_shutdown_timeout" yaml:"graceful_shutdown_timeout"`
	HealthCheckInterval      time.Duration `mapstructure:"health_check_interval" yaml:"health_check_interval"`
}

// EthereumConfig contains Ethereum network settings
type EthereumConfig struct {
	MainnetRPC    string            `mapstructure:"mainnet_rpc" yaml:"mainnet_rpc"`
	MainnetWS     string            `mapstructure:"mainnet_ws" yaml:"mainnet_ws"`
	ChainRPCs     map[uint32]string `mapstructure:"chain_rpcs" yaml:"chain_rpcs"`
	ChainWSs      map[uint32]string `mapstructure:"chain_ws" yaml:"chain_ws"`
	MaxGasPrice   *big.Int          `mapstructure:"max_gas_price" yaml:"max_gas_price"`
	GasMultiplier float64           `mapstructure:"gas_multiplier" yaml:"gas_multiplier"`
	RetryAttempts int               `mapstructure:"retry_attempts" yaml:"retry_attempts"`
	RetryDelay    time.Duration     `mapstructure:"retry_delay" yaml:"retry_delay"`
}

// EigenLayerConfig contains EigenLayer AVS settings
type EigenLayerConfig struct {
	ServiceManagerAddress    common.Address `mapstructure:"service_manager_address" yaml:"service_manager_address"`
	RegistryCoordinatorAddr  common.Address `mapstructure:"registry_coordinator_address" yaml:"registry_coordinator_address"`
	StakeRegistryAddress     common.Address `mapstructure:"stake_registry_address" yaml:"stake_registry_address"`
	BLSApkRegistryAddress    common.Address `mapstructure:"bls_apk_registry_address" yaml:"bls_apk_registry_address"`
	IndexRegistryAddress     common.Address `mapstructure:"index_registry_address" yaml:"index_registry_address"`
	MinStakeAmount           *big.Int       `mapstructure:"min_stake_amount" yaml:"min_stake_amount"`
	SlashingParams           SlashingConfig `mapstructure:"slashing" yaml:"slashing"`
	RewardsParams            RewardsConfig  `mapstructure:"rewards" yaml:"rewards"`
}

// SlashingConfig contains slashing parameters
type SlashingConfig struct {
	EnableSlashing     bool          `mapstructure:"enable_slashing" yaml:"enable_slashing"`
	SlashableAmount    *big.Int      `mapstructure:"slashable_amount" yaml:"slashable_amount"`
	SlashingDelay      time.Duration `mapstructure:"slashing_delay" yaml:"slashing_delay"`
	WithdrawalDelay    time.Duration `mapstructure:"withdrawal_delay" yaml:"withdrawal_delay"`
}

// RewardsConfig contains reward distribution parameters
type RewardsConfig struct {
	EnableRewards        bool     `mapstructure:"enable_rewards" yaml:"enable_rewards"`
	RewardPerTask        *big.Int `mapstructure:"reward_per_task" yaml:"reward_per_task"`
	BonusPerformanceRate float64  `mapstructure:"bonus_performance_rate" yaml:"bonus_performance_rate"`
	MinTasksForBonus     int64    `mapstructure:"min_tasks_for_bonus" yaml:"min_tasks_for_bonus"`
}

// AcrossConfig contains Across Protocol settings
type AcrossConfig struct {
	HubPoolAddress         common.Address            `mapstructure:"hub_pool_address" yaml:"hub_pool_address"`
	SpokePoolAddresses     map[uint32]common.Address `mapstructure:"spoke_pool_addresses" yaml:"spoke_pool_addresses"`
	QuoteAPIURL            string                    `mapstructure:"quote_api_url" yaml:"quote_api_url"`
	MaxSlippageTolerance   *big.Int                  `mapstructure:"max_slippage_tolerance" yaml:"max_slippage_tolerance"`
	MinBridgeAmount        *big.Int                  `mapstructure:"min_bridge_amount" yaml:"min_bridge_amount"`
	MaxBridgeAmount        *big.Int                  `mapstructure:"max_bridge_amount" yaml:"max_bridge_amount"`
	BridgeTimeout          time.Duration             `mapstructure:"bridge_timeout" yaml:"bridge_timeout"`
	MonitoringInterval     time.Duration             `mapstructure:"monitoring_interval" yaml:"monitoring_interval"`
	SupportedTokens        []TokenConfig             `mapstructure:"supported_tokens" yaml:"supported_tokens"`
}

// TokenConfig defines supported token configuration
type TokenConfig struct {
	Symbol    string                     `mapstructure:"symbol" yaml:"symbol"`
	Decimals  uint8                      `mapstructure:"decimals" yaml:"decimals"`
	Addresses map[uint32]common.Address  `mapstructure:"addresses" yaml:"addresses"`
}

// MatchingConfig contains matching engine settings
type MatchingConfig struct {
	Algorithm              string        `mapstructure:"algorithm" yaml:"algorithm"`
	EnableAIMatching       bool          `mapstructure:"enable_ai_matching" yaml:"enable_ai_matching"`
	AIModelEndpoint        string        `mapstructure:"ai_model_endpoint" yaml:"ai_model_endpoint"`
	AIModelAPIKey          string        `mapstructure:"ai_model_api_key" yaml:"ai_model_api_key"`
	MaxIntentPoolSize      int           `mapstructure:"max_intent_pool_size" yaml:"max_intent_pool_size"`
	IntentExpiryTime       time.Duration `mapstructure:"intent_expiry_time" yaml:"intent_expiry_time"`
	MatchingInterval       time.Duration `mapstructure:"matching_interval" yaml:"matching_interval"`
	MinProfitThreshold     *big.Int      `mapstructure:"min_profit_threshold" yaml:"min_profit_threshold"`
	EnableBatchMatching    bool          `mapstructure:"enable_batch_matching" yaml:"enable_batch_matching"`
	BatchSize              int           `mapstructure:"batch_size" yaml:"batch_size"`
	BatchTimeout           time.Duration `mapstructure:"batch_timeout" yaml:"batch_timeout"`
	EnableCircularTrades   bool          `mapstructure:"enable_circular_trades" yaml:"enable_circular_trades"`
	MaxCircularTradeDepth  int           `mapstructure:"max_circular_trade_depth" yaml:"max_circular_trade_depth"`
}

// MonitoringConfig contains monitoring and metrics settings
type MonitoringConfig struct {
	EnableMetrics         bool          `mapstructure:"enable_metrics" yaml:"enable_metrics"`
	MetricsAddress        string        `mapstructure:"metrics_address" yaml:"metrics_address"`
	EnableNodeAPI         bool          `mapstructure:"enable_node_api" yaml:"enable_node_api"`
	NodeAPIAddress        string        `mapstructure:"node_api_address" yaml:"node_api_address"`
	EnableHealthCheck     bool          `mapstructure:"enable_health_check" yaml:"enable_health_check"`
	HealthCheckAddress    string        `mapstructure:"health_check_address" yaml:"health_check_address"`
	MetricsUpdateInterval time.Duration `mapstructure:"metrics_update_interval" yaml:"metrics_update_interval"`
	EnableProfiling       bool          `mapstructure:"enable_profiling" yaml:"enable_profiling"`
	ProfilingAddress      string        `mapstructure:"profiling_address" yaml:"profiling_address"`
}

// LoggingConfig contains logging settings
type LoggingConfig struct {
	Level       string `mapstructure:"level" yaml:"level"`
	Format      string `mapstructure:"format" yaml:"format"`
	OutputPath  string `mapstructure:"output_path" yaml:"output_path"`
	ErrorPath   string `mapstructure:"error_path" yaml:"error_path"`
	MaxSize     int    `mapstructure:"max_size" yaml:"max_size"`
	MaxBackups  int    `mapstructure:"max_backups" yaml:"max_backups"`
	MaxAge      int    `mapstructure:"max_age" yaml:"max_age"`
	Compress    bool   `mapstructure:"compress" yaml:"compress"`
	EnableColor bool   `mapstructure:"enable_color" yaml:"enable_color"`
}

// SecurityConfig contains security settings
type SecurityConfig struct {
	EnableTLS            bool          `mapstructure:"enable_tls" yaml:"enable_tls"`
	TLSCertPath          string        `mapstructure:"tls_cert_path" yaml:"tls_cert_path"`
	TLSKeyPath           string        `mapstructure:"tls_key_path" yaml:"tls_key_path"`
	EnableRateLimiting   bool          `mapstructure:"enable_rate_limiting" yaml:"enable_rate_limiting"`
	RateLimit            int           `mapstructure:"rate_limit" yaml:"rate_limit"`
	RateBurst            int           `mapstructure:"rate_burst" yaml:"rate_burst"`
	EnableAuth           bool          `mapstructure:"enable_auth" yaml:"enable_auth"`
	AuthSecret           string        `mapstructure:"auth_secret" yaml:"auth_secret"`
	SessionTimeout       time.Duration `mapstructure:"session_timeout" yaml:"session_timeout"`
	MaxFailedAttempts    int           `mapstructure:"max_failed_attempts" yaml:"max_failed_attempts"`
	LockoutDuration      time.Duration `mapstructure:"lockout_duration" yaml:"lockout_duration"`
}

// ConfigManager handles configuration loading, validation, and updates
type ConfigManager struct {
	config     *Config
	configPath string
	logger     *zap.Logger
	viper      *viper.Viper
}

// NewConfigManager creates a new configuration manager
func NewConfigManager(configPath string, logger *zap.Logger) *ConfigManager {
	return &ConfigManager{
		configPath: configPath,
		logger:     logger,
		viper:      viper.New(),
	}
}

// LoadConfig loads configuration from file with environment variable overrides
func (cm *ConfigManager) LoadConfig() (*Config, error) {
	cm.logger.Info("Loading configuration", zap.String("path", cm.configPath))
	
	// Set up viper
	cm.viper.SetConfigFile(cm.configPath)
	cm.viper.AutomaticEnv()
	cm.viper.SetEnvPrefix("CROSSCOW")
	
	// Set default values
	cm.setDefaults()
	
	// Read config file
	if err := cm.viper.ReadInConfig(); err != nil {
		if _, ok := err.(viper.ConfigFileNotFoundError); ok {
			cm.logger.Warn("Config file not found, using defaults and environment variables")
		} else {
			return nil, fmt.Errorf("error reading config file: %w", err)
		}
	}
	
	// Unmarshal config
	config := &Config{}
	if err := cm.viper.Unmarshal(config); err != nil {
		return nil, fmt.Errorf("error unmarshaling config: %w", err)
	}
	
	// Validate configuration
	if err := cm.validateConfig(config); err != nil {
		return nil, fmt.Errorf("config validation failed: %w", err)
	}
	
	cm.config = config
	cm.logger.Info("Configuration loaded successfully")
	
	return config, nil
}

// SaveConfig saves the current configuration to file
func (cm *ConfigManager) SaveConfig(config *Config) error {
	cm.logger.Info("Saving configuration", zap.String("path", cm.configPath))
	
	// Ensure directory exists
	dir := filepath.Dir(cm.configPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create config directory: %w", err)
	}
	
	// Marshal config to YAML
	data, err := yaml.Marshal(config)
	if err != nil {
		return fmt.Errorf("failed to marshal config: %w", err)
	}
	
	// Write to file
	if err := os.WriteFile(cm.configPath, data, 0644); err != nil {
		return fmt.Errorf("failed to write config file: %w", err)
	}
	
	cm.config = config
	cm.logger.Info("Configuration saved successfully")
	
	return nil
}

// GetConfig returns the current configuration
func (cm *ConfigManager) GetConfig() *Config {
	return cm.config
}

// UpdateConfig updates specific configuration values
func (cm *ConfigManager) UpdateConfig(updates map[string]interface{}) error {
	cm.logger.Info("Updating configuration", zap.Int("updates", len(updates)))
	
	for key, value := range updates {
		cm.viper.Set(key, value)
	}
	
	// Re-unmarshal the updated config
	config := &Config{}
	if err := cm.viper.Unmarshal(config); err != nil {
		return fmt.Errorf("error unmarshaling updated config: %w", err)
	}
	
	// Validate updated configuration
	if err := cm.validateConfig(config); err != nil {
		return fmt.Errorf("updated config validation failed: %w", err)
	}
	
	cm.config = config
	return nil
}

// setDefaults sets default configuration values
func (cm *ConfigManager) setDefaults() {
	// Operator defaults
	cm.viper.SetDefault("operator.name", "crosscow-operator")
	cm.viper.SetDefault("operator.version", "0.1.0")
	cm.viper.SetDefault("operator.description", "CrossCoW AVS Operator")
	cm.viper.SetDefault("operator.register_on_startup", true)
	cm.viper.SetDefault("operator.max_concurrent_tasks", 10)
	cm.viper.SetDefault("operator.task_timeout", "5m")
	cm.viper.SetDefault("operator.graceful_shutdown_timeout", "30s")
	cm.viper.SetDefault("operator.health_check_interval", "30s")
	
	// Ethereum defaults
	cm.viper.SetDefault("ethereum.mainnet_rpc", "https://eth-mainnet.alchemyapi.io/v2/your-api-key")
	cm.viper.SetDefault("ethereum.gas_multiplier", 1.2)
	cm.viper.SetDefault("ethereum.retry_attempts", 3)
	cm.viper.SetDefault("ethereum.retry_delay", "5s")
	
	// EigenLayer defaults
	cm.viper.SetDefault("eigenlayer.min_stake_amount", "32000000000000000000") // 32 ETH in wei
	cm.viper.SetDefault("eigenlayer.slashing.enable_slashing", true)
	cm.viper.SetDefault("eigenlayer.slashing.slashing_delay", "7d")
	cm.viper.SetDefault("eigenlayer.slashing.withdrawal_delay", "7d")
	cm.viper.SetDefault("eigenlayer.rewards.enable_rewards", true)
	cm.viper.SetDefault("eigenlayer.rewards.bonus_performance_rate", 1.1)
	cm.viper.SetDefault("eigenlayer.rewards.min_tasks_for_bonus", 100)
	
	// Across defaults
	cm.viper.SetDefault("across.quote_api_url", "https://across.to/api/")
	cm.viper.SetDefault("across.max_slippage_tolerance", "100") // 1% in basis points
	cm.viper.SetDefault("across.min_bridge_amount", "1000000") // 1 USDC
	cm.viper.SetDefault("across.bridge_timeout", "30m")
	cm.viper.SetDefault("across.monitoring_interval", "30s")
	
	// Matching defaults
	cm.viper.SetDefault("matching.algorithm", "greedy")
	cm.viper.SetDefault("matching.enable_ai_matching", false)
	cm.viper.SetDefault("matching.max_intent_pool_size", 10000)
	cm.viper.SetDefault("matching.intent_expiry_time", "1h")
	cm.viper.SetDefault("matching.matching_interval", "10s")
	cm.viper.SetDefault("matching.min_profit_threshold", "1000") // 0.001 ETH in wei
	cm.viper.SetDefault("matching.enable_batch_matching", true)
	cm.viper.SetDefault("matching.batch_size", 10)
	cm.viper.SetDefault("matching.batch_timeout", "30s")
	cm.viper.SetDefault("matching.enable_circular_trades", true)
	cm.viper.SetDefault("matching.max_circular_trade_depth", 5)
	
	// Monitoring defaults
	cm.viper.SetDefault("monitoring.enable_metrics", true)
	cm.viper.SetDefault("monitoring.metrics_address", ":9090")
	cm.viper.SetDefault("monitoring.enable_node_api", true)
	cm.viper.SetDefault("monitoring.node_api_address", ":9091")
	cm.viper.SetDefault("monitoring.enable_health_check", true)
	cm.viper.SetDefault("monitoring.health_check_address", ":8080")
	cm.viper.SetDefault("monitoring.metrics_update_interval", "30s")
	cm.viper.SetDefault("monitoring.enable_profiling", false)
	cm.viper.SetDefault("monitoring.profiling_address", ":6060")
	
	// Logging defaults
	cm.viper.SetDefault("logging.level", "info")
	cm.viper.SetDefault("logging.format", "json")
	cm.viper.SetDefault("logging.output_path", "stdout")
	cm.viper.SetDefault("logging.error_path", "stderr")
	cm.viper.SetDefault("logging.max_size", 100)
	cm.viper.SetDefault("logging.max_backups", 3)
	cm.viper.SetDefault("logging.max_age", 7)
	cm.viper.SetDefault("logging.compress", true)
	cm.viper.SetDefault("logging.enable_color", false)
	
	// Security defaults
	cm.viper.SetDefault("security.enable_tls", false)
	cm.viper.SetDefault("security.enable_rate_limiting", true)
	cm.viper.SetDefault("security.rate_limit", 100)
	cm.viper.SetDefault("security.rate_burst", 10)
	cm.viper.SetDefault("security.enable_auth", false)
	cm.viper.SetDefault("security.session_timeout", "24h")
	cm.viper.SetDefault("security.max_failed_attempts", 5)
	cm.viper.SetDefault("security.lockout_duration", "15m")
}

// validateConfig validates the loaded configuration
func (cm *ConfigManager) validateConfig(config *Config) error {
	// Validate operator config
	if config.Operator.Name == "" {
		return fmt.Errorf("operator name cannot be empty")
	}
	
	if config.Operator.MaxConcurrentTasks <= 0 {
		return fmt.Errorf("max_concurrent_tasks must be greater than 0")
	}
	
	// Validate Ethereum config
	if config.Ethereum.MainnetRPC == "" {
		return fmt.Errorf("mainnet_rpc cannot be empty")
	}
	
	if config.Ethereum.GasMultiplier <= 0 {
		return fmt.Errorf("gas_multiplier must be greater than 0")
	}
	
	// Validate EigenLayer addresses if provided
	if config.EigenLayer.ServiceManagerAddress == (common.Address{}) {
		cm.logger.Warn("ServiceManagerAddress not configured")
	}
	
	// Validate Across config
	if config.Across.QuoteAPIURL == "" {
		return fmt.Errorf("across quote_api_url cannot be empty")
	}
	
	// Validate matching config
	validAlgorithms := []string{"greedy", "optimal", "ai_enhanced"}
	algorithmValid := false
	for _, alg := range validAlgorithms {
		if config.Matching.Algorithm == alg {
			algorithmValid = true
			break
		}
	}
	if !algorithmValid {
		return fmt.Errorf("invalid matching algorithm: %s", config.Matching.Algorithm)
	}
	
	// Validate logging config
	validLevels := []string{"debug", "info", "warn", "error", "fatal"}
	levelValid := false
	for _, level := range validLevels {
		if config.Logging.Level == level {
			levelValid = true
			break
		}
	}
	if !levelValid {
		return fmt.Errorf("invalid log level: %s", config.Logging.Level)
	}
	
	return nil
}

// WatchConfig watches for configuration file changes
func (cm *ConfigManager) WatchConfig(callback func(*Config)) error {
	cm.viper.WatchConfig()
	cm.viper.OnConfigChange(func(e fsnotify.Event) {
		cm.logger.Info("Config file changed", zap.String("file", e.Name))
		
		// Reload configuration
		config := &Config{}
		if err := cm.viper.Unmarshal(config); err != nil {
			cm.logger.Error("Error reloading config", zap.Error(err))
			return
		}
		
		// Validate reloaded configuration
		if err := cm.validateConfig(config); err != nil {
			cm.logger.Error("Reloaded config validation failed", zap.Error(err))
			return
		}
		
		cm.config = config
		if callback != nil {
			callback(config)
		}
	})
	
	return nil
}

// GenerateDefaultConfig generates a default configuration file
func GenerateDefaultConfig(path string) error {
	config := &Config{
		Operator: OperatorConfig{
			Name:                     "crosscow-operator",
			Version:                  "0.1.0",
			Description:              "CrossCoW AVS Operator",
			RegisterOnStartup:        true,
			MaxConcurrentTasks:       10,
			TaskTimeout:              5 * time.Minute,
			GracefulShutdownTimeout:  30 * time.Second,
			HealthCheckInterval:      30 * time.Second,
		},
		Ethereum: EthereumConfig{
			MainnetRPC:    "https://eth-mainnet.alchemyapi.io/v2/your-api-key",
			GasMultiplier: 1.2,
			RetryAttempts: 3,
			RetryDelay:    5 * time.Second,
			ChainRPCs: map[uint32]string{
				1:     "https://eth-mainnet.alchemyapi.io/v2/your-api-key",
				10:    "https://opt-mainnet.g.alchemy.com/v2/your-api-key",
				137:   "https://polygon-mainnet.alchemyapi.io/v2/your-api-key",
				42161: "https://arb-mainnet.g.alchemy.com/v2/your-api-key",
				8453:  "https://base-mainnet.g.alchemy.com/v2/your-api-key",
			},
		},
		Monitoring: MonitoringConfig{
			EnableMetrics:         true,
			MetricsAddress:        ":9090",
			EnableNodeAPI:         true,
			NodeAPIAddress:        ":9091",
			EnableHealthCheck:     true,
			HealthCheckAddress:    ":8080",
			MetricsUpdateInterval: 30 * time.Second,
		},
		Logging: LoggingConfig{
			Level:       "info",
			Format:      "json",
			OutputPath:  "stdout",
			ErrorPath:   "stderr",
			MaxSize:     100,
			MaxBackups:  3,
			MaxAge:      7,
			Compress:    true,
			EnableColor: false,
		},
	}
	
	// Ensure directory exists
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create config directory: %w", err)
	}
	
	// Marshal to YAML
	data, err := yaml.Marshal(config)
	if err != nil {
		return fmt.Errorf("failed to marshal config: %w", err)
	}
	
	// Write to file
	if err := os.WriteFile(path, data, 0644); err != nil {
		return fmt.Errorf("failed to write config file: %w", err)
	}
	
	return nil
}