package across

import (
	"context"
	"fmt"
	"math/big"
	"time"

	"github.com/Layr-Labs/eigensdk-go/chainio/clients/eth"
	"github.com/Layr-Labs/eigensdk-go/logging"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
)

type AcrossIntegration struct {
	config       Config
	logger       logging.Logger
	ethClient    eth.Client
	hubPool      *AcrossHubPoolContract
	spokePool    map[uint32]*AcrossSpokePoolContract // chainId -> spokePool
	quoteService *QuoteService
	monitor      *BridgeMonitor
}

type Config struct {
	HubPoolAddress      common.Address
	SpokePoolAddresses  map[uint32]common.Address // chainId -> address
	PrivateKey          string
	MaxGasPrice         *big.Int
	SlippageTolerance   *big.Int // in basis points
	QuoteApiUrl         string
	MonitoringInterval  time.Duration
}

type DepositResult struct {
	DepositId     uint32
	TransactionHash common.Hash
	Success       bool
	GasUsed       uint64
	BridgeFee     *big.Int
	EstimatedTime time.Duration
}

type BridgeQuote struct {
	InputAmount     *big.Int
	OutputAmount    *big.Int
	BridgeFee       *big.Int
	RelayerGasFee   *big.Int
	LpFee          *big.Int
	TotalFee       *big.Int
	EstimatedTime  time.Duration
	Confidence     float64
}

type CrossChainTrade struct {
	TradeId         common.Hash
	SourceChain     uint32
	DestChain       uint32
	SourceToken     common.Address
	DestToken       common.Address
	SourceAmount    *big.Int
	MinDestAmount   *big.Int
	SourceUser      common.Address
	DestUser        common.Address
	Deadline        uint64
}

func NewAcrossIntegration(config Config, ethClient eth.Client, logger logging.Logger) (*AcrossIntegration, error) {
	logger = logger.With("component", "across-integration")
	
	// Initialize hub pool contract
	hubPool, err := NewAcrossHubPoolContract(config.HubPoolAddress, ethClient)
	if err != nil {
		return nil, fmt.Errorf("failed to create hub pool contract: %w", err)
	}
	
	// Initialize spoke pools for each supported chain
	spokePool := make(map[uint32]*AcrossSpokePoolContract)
	for chainId, address := range config.SpokePoolAddresses {
		// In a real implementation, you'd need separate clients for each chain
		spokeContract, err := NewAcrossSpokePoolContract(address, ethClient)
		if err != nil {
			return nil, fmt.Errorf("failed to create spoke pool contract for chain %d: %w", chainId, err)
		}
		spokePool[chainId] = spokeContract
	}
	
	// Initialize quote service
	quoteService := NewQuoteService(config.QuoteApiUrl, logger)
	
	// Initialize bridge monitor
	monitor := NewBridgeMonitor(config.MonitoringInterval, logger)
	
	return &AcrossIntegration{
		config:       config,
		logger:       logger,
		ethClient:    ethClient,
		hubPool:      hubPool,
		spokePool:    spokePool,
		quoteService: quoteService,
		monitor:      monitor,
	}, nil
}

func (ai *AcrossIntegration) ExecuteCrossChainTrade(trade CrossChainTrade) (success bool, depositId common.Hash, gasUsed uint64, err error) {
	ai.logger.Info("Executing cross-chain trade via Across",
		"tradeId", trade.TradeId.Hex(),
		"sourceChain", trade.SourceChain,
		"destChain", trade.DestChain,
		"amount", trade.SourceAmount.String(),
	)
	
	startTime := time.Now()
	
	// Step 1: Get optimal quote
	quote, err := ai.getOptimalQuote(trade)
	if err != nil {
		return false, common.Hash{}, 0, fmt.Errorf("failed to get quote: %w", err)
	}
	
	ai.logger.Info("Received bridge quote",
		"bridgeFee", quote.BridgeFee.String(),
		"outputAmount", quote.OutputAmount.String(),
		"estimatedTime", quote.EstimatedTime,
	)
	
	// Step 2: Validate quote and trade parameters
	if err := ai.validateTrade(trade, quote); err != nil {
		return false, common.Hash{}, 0, fmt.Errorf("trade validation failed: %w", err)
	}
	
	// Step 3: Execute deposit on source chain
	depositResult, err := ai.executeDeposit(trade, quote)
	if err != nil {
		return false, common.Hash{}, 0, fmt.Errorf("deposit execution failed: %w", err)
	}
	
	if !depositResult.Success {
		return false, common.Hash{}, depositResult.GasUsed, fmt.Errorf("deposit transaction failed")
	}
	
	// Step 4: Monitor bridge completion
	go ai.monitorBridgeCompletion(depositResult.DepositId, trade.DestChain)
	
	executionTime := time.Since(startTime)
	ai.logger.Info("Cross-chain trade initiated successfully",
		"tradeId", trade.TradeId.Hex(),
		"depositId", depositResult.DepositId,
		"executionTime", executionTime,
		"gasUsed", depositResult.GasUsed,
	)
	
	return true, common.BytesToHash(big.NewInt(int64(depositResult.DepositId)).Bytes()), depositResult.GasUsed, nil
}

func (ai *AcrossIntegration) getOptimalQuote(trade CrossChainTrade) (*BridgeQuote, error) {
	// Get quote from Across API
	quote, err := ai.quoteService.GetQuote(QuoteRequest{
		OriginChainId:      trade.SourceChain,
		DestinationChainId: trade.DestChain,
		InputToken:         trade.SourceToken,
		OutputToken:        trade.DestToken,
		Amount:            trade.SourceAmount,
		Recipient:         trade.DestUser,
		Message:           []byte{}, // No message for simple transfer
	})
	
	if err != nil {
		return nil, fmt.Errorf("failed to get quote from service: %w", err)
	}
	
	// Validate quote parameters
	if quote.OutputAmount.Cmp(trade.MinDestAmount) < 0 {
		return nil, fmt.Errorf("quote output amount %s below minimum %s", 
			quote.OutputAmount.String(), trade.MinDestAmount.String())
	}
	
	return quote, nil
}

func (ai *AcrossIntegration) validateTrade(trade CrossChainTrade, quote *BridgeQuote) error {
	// Check deadline
	if uint64(time.Now().Unix()) > trade.Deadline {
		return fmt.Errorf("trade deadline expired")
	}
	
	// Check supported chains
	if _, exists := ai.spokePool[trade.SourceChain]; !exists {
		return fmt.Errorf("source chain %d not supported", trade.SourceChain)
	}
	
	if _, exists := ai.spokePool[trade.DestChain]; !exists {
		return fmt.Errorf("destination chain %d not supported", trade.DestChain)
	}
	
	// Check token compatibility
	if err := ai.validateTokenPair(trade.SourceToken, trade.DestToken, trade.SourceChain, trade.DestChain); err != nil {
		return fmt.Errorf("token validation failed: %w", err)
	}
	
	// Check slippage tolerance
	expectedOutput := new(big.Int).Sub(trade.SourceAmount, quote.TotalFee)
	slippage := new(big.Int).Sub(expectedOutput, quote.OutputAmount)
	slippage.Mul(slippage, big.NewInt(10000)) // Convert to basis points
	slippage.Div(slippage, expectedOutput)
	
	if slippage.Cmp(ai.config.SlippageTolerance) > 0 {
		return fmt.Errorf("slippage %s exceeds tolerance %s", 
			slippage.String(), ai.config.SlippageTolerance.String())
	}
	
	return nil
}

func (ai *AcrossIntegration) executeDeposit(trade CrossChainTrade, quote *BridgeQuote) (*DepositResult, error) {
	// Get the spoke pool for source chain
	spokePool, exists := ai.spokePool[trade.SourceChain]
	if !exists {
		return nil, fmt.Errorf("no spoke pool for chain %d", trade.SourceChain)
	}
	
	// Prepare transaction options
	opts, err := ai.getTransactOpts()
	if err != nil {
		return nil, fmt.Errorf("failed to prepare transaction options: %w", err)
	}
	
	// Calculate fill deadline (trade deadline - buffer)
	fillDeadline := uint32(trade.Deadline - 60) // 60 second buffer
	
	// Execute deposit
	tx, err := spokePool.DepositV3(
		opts,
		trade.SourceUser,
		trade.DestUser,
		trade.SourceToken,
		trade.DestToken,
		trade.SourceAmount,
		quote.OutputAmount,
		big.NewInt(int64(trade.DestChain)),
		common.Address{}, // No exclusive relayer
		uint32(time.Now().Unix()), // Quote timestamp
		fillDeadline,
		0, // No exclusivity deadline
		[]byte{}, // No message
	)
	
	if err != nil {
		return nil, fmt.Errorf("deposit transaction failed: %w", err)
	}
	
	ai.logger.Info("Deposit transaction sent",
		"txHash", tx.Hash().Hex(),
		"sourceChain", trade.SourceChain,
		"destChain", trade.DestChain,
	)
	
	// Wait for transaction confirmation
	receipt, err := bind.WaitMined(context.Background(), ai.ethClient, tx)
	if err != nil {
		return nil, fmt.Errorf("failed to wait for transaction confirmation: %w", err)
	}
	
	// Parse deposit ID from logs
	depositId, err := ai.parseDepositIdFromReceipt(receipt)
	if err != nil {
		return nil, fmt.Errorf("failed to parse deposit ID: %w", err)
	}
	
	return &DepositResult{
		DepositId:       depositId,
		TransactionHash: tx.Hash(),
		Success:         receipt.Status == 1,
		GasUsed:         receipt.GasUsed,
		BridgeFee:       quote.BridgeFee,
		EstimatedTime:   quote.EstimatedTime,
	}, nil
}

func (ai *AcrossIntegration) validateTokenPair(sourceToken, destToken common.Address, sourceChain, destChain uint32) error {
	// In a real implementation, this would:
	// 1. Check if tokens are supported on both chains
	// 2. Verify token mapping is correct
	// 3. Check if there's sufficient liquidity
	
	// For now, just do basic validation
	if sourceToken == (common.Address{}) || destToken == (common.Address{}) {
		return fmt.Errorf("invalid token addresses")
	}
	
	return nil
}

func (ai *AcrossIntegration) getTransactOpts() (*bind.TransactOpts, error) {
	privateKey, err := crypto.HexToECDSA(ai.config.PrivateKey)
	if err != nil {
		return nil, fmt.Errorf("invalid private key: %w", err)
	}
	
	opts, err := bind.NewKeyedTransactorWithChainID(privateKey, big.NewInt(1)) // Mainnet for now
	if err != nil {
		return nil, fmt.Errorf("failed to create transactor: %w", err)
	}
	
	opts.GasPrice = ai.config.MaxGasPrice
	
	return opts, nil
}

func (ai *AcrossIntegration) parseDepositIdFromReceipt(receipt *types.Receipt) (uint32, error) {
	// Parse FundsDeposited event to extract deposit ID
	// This is a simplified implementation
	
	for _, log := range receipt.Logs {
		// Check if this is a FundsDeposited event
		if len(log.Topics) > 0 && log.Topics[0] == crypto.Keccak256Hash([]byte("FundsDeposited(uint256,uint256,uint256,int64,uint32,uint32,address,address,address,bytes)")) {
			// Extract deposit ID from event data
			if len(log.Data) >= 32*5 { // Event has at least 5 uint256 fields
				depositIdBytes := log.Data[32*4 : 32*5] // 5th field (0-indexed)
				return uint32(new(big.Int).SetBytes(depositIdBytes).Uint64()), nil
			}
		}
	}
	
	return 0, fmt.Errorf("deposit ID not found in transaction receipt")
}

func (ai *AcrossIntegration) monitorBridgeCompletion(depositId uint32, destChain uint32) {
	ai.logger.Info("Starting bridge monitoring", 
		"depositId", depositId, 
		"destChain", destChain,
	)
	
	// This would monitor the destination chain for fill events
	// and update the trade status accordingly
	
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	
	timeout := time.After(30 * time.Minute) // 30 minute timeout
	
	for {
		select {
		case <-ticker.C:
			completed, err := ai.checkBridgeCompletion(depositId, destChain)
			if err != nil {
				ai.logger.Warn("Error checking bridge completion", 
					"depositId", depositId, 
					"error", err,
				)
				continue
			}
			
			if completed {
				ai.logger.Info("Bridge completed successfully", 
					"depositId", depositId,
					"destChain", destChain,
				)
				return
			}
			
		case <-timeout:
			ai.logger.Warn("Bridge monitoring timeout", 
				"depositId", depositId,
				"destChain", destChain,
			)
			return
		}
	}
}

func (ai *AcrossIntegration) checkBridgeCompletion(depositId uint32, destChain uint32) (bool, error) {
	// Query the destination chain spoke pool for fill events
	// This is a simplified check - in practice you'd query event logs
	
	spokePool, exists := ai.spokePool[destChain]
	if !exists {
		return false, fmt.Errorf("no spoke pool for destination chain %d", destChain)
	}
	
	// In a real implementation, this would:
	// 1. Query FilledRelay events for the deposit ID
	// 2. Check if the fill was successful
	// 3. Return completion status
	
	_ = spokePool // Use the spoke pool to query completion status
	
	// For now, simulate completion after some time
	time.Sleep(2 * time.Second)
	return true, nil
}

// Placeholder contract interfaces (would be generated from ABI)
type AcrossHubPoolContract struct {
	// Contract binding would go here
}

type AcrossSpokePoolContract struct {
	// Contract binding would go here
}

func NewAcrossHubPoolContract(address common.Address, client eth.Client) (*AcrossHubPoolContract, error) {
	// Would create actual contract binding
	return &AcrossHubPoolContract{}, nil
}

func NewAcrossSpokePoolContract(address common.Address, client eth.Client) (*AcrossSpokePoolContract, error) {
	// Would create actual contract binding
	return &AcrossSpokePoolContract{}, nil
}

func (c *AcrossSpokePoolContract) DepositV3(
	opts *bind.TransactOpts,
	depositor common.Address,
	recipient common.Address,
	inputToken common.Address,
	outputToken common.Address,
	inputAmount *big.Int,
	outputAmount *big.Int,
	destinationChainId *big.Int,
	exclusiveRelayer common.Address,
	quoteTimestamp uint32,
	fillDeadline uint32,
	exclusivityDeadline uint32,
	message []byte,
) (*types.Transaction, error) {
	// Would call actual contract method
	return &types.Transaction{}, nil
}