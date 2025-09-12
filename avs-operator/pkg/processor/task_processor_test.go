package processor

import (
	"context"
	"crypto/ecdsa"
	"math/big"
	"testing"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/Layr-Labs/eigensdk-go/logging"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/eigencrosscow/avs/contracts/bindings/CrossCoWTaskManager"
	"github.com/eigencrosscow/avs/pkg/crypto"
)

func TestNewTaskProcessor(t *testing.T) {
	logger := logging.NewNoopLogger()
	blsKeyPair, err := crypto.GenerateBLSKeyPair()
	require.NoError(t, err)
	
	ecdsaKey, err := crypto.GenerateKey()
	require.NoError(t, err)
	
	operatorAddr := crypto.PubkeyToAddress(ecdsaKey.PublicKey)
	
	processor := NewTaskProcessor(logger, blsKeyPair, ecdsaKey, operatorAddr)
	require.NotNil(t, processor)
	assert.Equal(t, operatorAddr, processor.GetOperatorAddress())
}

func TestProcessTask(t *testing.T) {
	logger := logging.NewNoopLogger()
	blsKeyPair, err := crypto.GenerateBLSKeyPair()
	require.NoError(t, err)
	
	ecdsaKey, err := crypto.GenerateKey()
	require.NoError(t, err)
	
	operatorAddr := crypto.PubkeyToAddress(ecdsaKey.PublicKey)
	
	processor := NewTaskProcessor(logger, blsKeyPair, ecdsaKey, operatorAddr)
	
	// Create test task
	task := createTestTask()
	
	// Process task
	response, err := processor.ProcessTask(context.Background(), task)
	require.NoError(t, err)
	require.NotNil(t, response)
	
	assert.Equal(t, task.TaskIndex, response.ReferenceTaskIndex)
	assert.GreaterOrEqual(t, len(response.Matches), 0)
	assert.NotNil(t, response.TotalGasEstimate)
}

func TestFindOptimalMatches(t *testing.T) {
	logger := logging.NewNoopLogger()
	blsKeyPair, err := crypto.GenerateBLSKeyPair()
	require.NoError(t, err)
	
	ecdsaKey, err := crypto.GenerateKey()
	require.NoError(t, err)
	
	operatorAddr := crypto.PubkeyToAddress(ecdsaKey.PublicKey)
	
	processor := NewTaskProcessor(logger, blsKeyPair, ecdsaKey, operatorAddr)
	
	// Test with compatible intents
	intents := createCompatibleIntents()
	maxSlippage := big.NewInt(50) // 5%
	
	matches, err := processor.findOptimalMatches(intents, maxSlippage)
	require.NoError(t, err)
	assert.GreaterOrEqual(t, len(matches), 1)
	
	// Test with incompatible intents
	incompatibleIntents := createIncompatibleIntents()
	matches, err = processor.findOptimalMatches(incompatibleIntents, maxSlippage)
	require.NoError(t, err)
	assert.Equal(t, 0, len(matches))
	
	// Test with insufficient intents
	insufficientIntents := []CrossCoWTaskManager.Intent{createTestIntent()}
	matches, err = processor.findOptimalMatches(insufficientIntents, maxSlippage)
	require.NoError(t, err)
	assert.Equal(t, 0, len(matches))
}

func TestAreIntentsCompatible(t *testing.T) {
	logger := logging.NewNoopLogger()
	blsKeyPair, err := crypto.GenerateBLSKeyPair()
	require.NoError(t, err)
	
	ecdsaKey, err := crypto.GenerateKey()
	require.NoError(t, err)
	
	operatorAddr := crypto.PubkeyToAddress(ecdsaKey.PublicKey)
	
	processor := NewTaskProcessor(logger, blsKeyPair, ecdsaKey, operatorAddr)
	
	// Test compatible intents
	intentA := createTestIntent()
	intentB := createCompatibleIntent(intentA)
	maxSlippage := big.NewInt(50)
	
	compatible := processor.areIntentsCompatible(intentA, intentB, maxSlippage)
	assert.True(t, compatible)
	
	// Test incompatible intents
	incompatibleIntent := createIncompatibleIntent(intentA)
	compatible = processor.areIntentsCompatible(intentA, incompatibleIntent, maxSlippage)
	assert.False(t, compatible)
}

func TestCreateMatch(t *testing.T) {
	logger := logging.NewNoopLogger()
	blsKeyPair, err := crypto.GenerateBLSKeyPair()
	require.NoError(t, err)
	
	ecdsaKey, err := crypto.GenerateKey()
	require.NoError(t, err)
	
	operatorAddr := crypto.PubkeyToAddress(ecdsaKey.PublicKey)
	
	processor := NewTaskProcessor(logger, blsKeyPair, ecdsaKey, operatorAddr)
	
	intentA := createTestIntent()
	intentB := createCompatibleIntent(intentA)
	
	match := processor.createMatch(intentA, intentB, 0, 1)
	
	assert.Equal(t, uint32(0), match.IntentAIndex)
	assert.Equal(t, uint32(1), match.IntentBIndex)
	assert.NotNil(t, match.ExecutionAmount)
	assert.NotNil(t, match.BridgeFee)
	assert.NotNil(t, match.ExecutionProof)
}

func TestSignResponse(t *testing.T) {
	logger := logging.NewNoopLogger()
	blsKeyPair, err := crypto.GenerateBLSKeyPair()
	require.NoError(t, err)
	
	ecdsaKey, err := crypto.GenerateKey()
	require.NoError(t, err)
	
	operatorAddr := crypto.PubkeyToAddress(ecdsaKey.PublicKey)
	
	processor := NewTaskProcessor(logger, blsKeyPair, ecdsaKey, operatorAddr)
	
	// Create test response
	response := &CrossCoWTaskManager.TradeMatchingResponse{
		ReferenceTaskIndex: 1,
		Matches:           []CrossCoWTaskManager.MatchedTrade{},
		TotalGasEstimate:  big.NewInt(100000),
		ExecutionPriority: 1,
	}
	
	// Sign response
	signature, err := processor.SignResponse(response)
	require.NoError(t, err)
	require.NotNil(t, signature)
	assert.Greater(t, len(signature), 0)
}

func TestVerifyResponse(t *testing.T) {
	logger := logging.NewNoopLogger()
	blsKeyPair, err := crypto.GenerateBLSKeyPair()
	require.NoError(t, err)
	
	ecdsaKey, err := crypto.GenerateKey()
	require.NoError(t, err)
	
	operatorAddr := crypto.PubkeyToAddress(ecdsaKey.PublicKey)
	
	processor := NewTaskProcessor(logger, blsKeyPair, ecdsaKey, operatorAddr)
	
	// Create test response
	response := &CrossCoWTaskManager.TradeMatchingResponse{
		ReferenceTaskIndex: 1,
		Matches:           []CrossCoWTaskManager.MatchedTrade{},
		TotalGasEstimate:  big.NewInt(100000),
		ExecutionPriority: 1,
	}
	
	// Sign response
	signature, err := processor.SignResponse(response)
	require.NoError(t, err)
	
	// Verify response
	valid, err := processor.VerifyResponse(response, signature)
	require.NoError(t, err)
	assert.True(t, valid)
	
	// Test with wrong signature
	wrongSignature := make([]byte, 96)
	valid, err = processor.VerifyResponse(response, wrongSignature)
	require.NoError(t, err)
	assert.False(t, valid)
}

func TestValidateTask(t *testing.T) {
	logger := logging.NewNoopLogger()
	blsKeyPair, err := crypto.GenerateBLSKeyPair()
	require.NoError(t, err)
	
	ecdsaKey, err := crypto.GenerateKey()
	require.NoError(t, err)
	
	operatorAddr := crypto.PubkeyToAddress(ecdsaKey.PublicKey)
	
	processor := NewTaskProcessor(logger, blsKeyPair, ecdsaKey, operatorAddr)
	
	// Test valid task
	validTask := createTestTask()
	err = processor.ValidateTask(validTask)
	assert.NoError(t, err)
	
	// Test task with insufficient intents
	invalidTask := validTask
	invalidTask.Intents = []CrossCoWTaskManager.Intent{createTestIntent()}
	err = processor.ValidateTask(invalidTask)
	assert.Error(t, err)
	
	// Test task with high slippage
	invalidTask = validTask
	invalidTask.MaxSlippage = big.NewInt(2000) // 20%
	err = processor.ValidateTask(invalidTask)
	assert.Error(t, err)
	
	// Test task with past deadline
	invalidTask = validTask
	invalidTask.Deadline = uint32(time.Now().Unix() - 3600) // 1 hour ago
	err = processor.ValidateTask(invalidTask)
	assert.Error(t, err)
}

func TestValidateIntent(t *testing.T) {
	logger := logging.NewNoopLogger()
	blsKeyPair, err := crypto.GenerateBLSKeyPair()
	require.NoError(t, err)
	
	ecdsaKey, err := crypto.GenerateKey()
	require.NoError(t, err)
	
	operatorAddr := crypto.PubkeyToAddress(ecdsaKey.PublicKey)
	
	processor := NewTaskProcessor(logger, blsKeyPair, ecdsaKey, operatorAddr)
	
	// Test valid intent
	validIntent := createTestIntent()
	err = processor.validateIntent(validIntent, 0)
	assert.NoError(t, err)
	
	// Test intent with zero user
	invalidIntent := validIntent
	invalidIntent.User = common.Address{}
	err = processor.validateIntent(invalidIntent, 0)
	assert.Error(t, err)
	
	// Test intent with zero input token
	invalidIntent = validIntent
	invalidIntent.InputToken = common.Address{}
	err = processor.validateIntent(invalidIntent, 0)
	assert.Error(t, err)
	
	// Test intent with zero output token
	invalidIntent = validIntent
	invalidIntent.OutputToken = common.Address{}
	err = processor.validateIntent(invalidIntent, 0)
	assert.Error(t, err)
	
	// Test intent with zero input amount
	invalidIntent = validIntent
	invalidIntent.InputAmount = big.NewInt(0)
	err = processor.validateIntent(invalidIntent, 0)
	assert.Error(t, err)
	
	// Test intent with zero min output amount
	invalidIntent = validIntent
	invalidIntent.MinOutputAmount = big.NewInt(0)
	err = processor.validateIntent(invalidIntent, 0)
	assert.Error(t, err)
	
	// Test intent with same source and destination chain
	invalidIntent = validIntent
	invalidIntent.DestinationChain = invalidIntent.SourceChain
	err = processor.validateIntent(invalidIntent, 0)
	assert.Error(t, err)
	
	// Test intent with past deadline
	invalidIntent = validIntent
	invalidIntent.Deadline = uint32(time.Now().Unix() - 3600) // 1 hour ago
	err = processor.validateIntent(invalidIntent, 0)
	assert.Error(t, err)
}

func TestCalculateGasEstimate(t *testing.T) {
	logger := logging.NewNoopLogger()
	blsKeyPair, err := crypto.GenerateBLSKeyPair()
	require.NoError(t, err)
	
	ecdsaKey, err := crypto.GenerateKey()
	require.NoError(t, err)
	
	operatorAddr := crypto.PubkeyToAddress(ecdsaKey.PublicKey)
	
	processor := NewTaskProcessor(logger, blsKeyPair, ecdsaKey, operatorAddr)
	
	// Test with no matches
	matches := []CrossCoWTaskManager.MatchedTrade{}
	gasEstimate := processor.calculateGasEstimate(matches)
	assert.Equal(t, big.NewInt(21000), gasEstimate) // Base gas
	
	// Test with matches
	matches = []CrossCoWTaskManager.MatchedTrade{
		{},
		{},
		{},
	}
	gasEstimate = processor.calculateGasEstimate(matches)
	expectedGas := big.NewInt(21000 + 3*100000) // Base + 3 matches
	assert.Equal(t, expectedGas, gasEstimate)
}

func TestConcurrentProcessing(t *testing.T) {
	logger := logging.NewNoopLogger()
	blsKeyPair, err := crypto.GenerateBLSKeyPair()
	require.NoError(t, err)
	
	ecdsaKey, err := crypto.GenerateKey()
	require.NoError(t, err)
	
	operatorAddr := crypto.PubkeyToAddress(ecdsaKey.PublicKey)
	
	processor := NewTaskProcessor(logger, blsKeyPair, ecdsaKey, operatorAddr)
	
	// Process multiple tasks concurrently
	tasks := make([]CrossCoWTaskManager.TradeMatchingTask, 10)
	for i := 0; i < 10; i++ {
		tasks[i] = createTestTask()
	}
	
	results := make([]*CrossCoWTaskManager.TradeMatchingResponse, 10)
	errors := make([]error, 10)
	
	for i := 0; i < 10; i++ {
		go func(index int) {
			response, err := processor.ProcessTask(context.Background(), tasks[index])
			results[index] = response
			errors[index] = err
		}(i)
	}
	
	// Wait for all goroutines to complete
	time.Sleep(100 * time.Millisecond)
	
	// Check results
	for i := 0; i < 10; i++ {
		assert.NoError(t, errors[i])
		assert.NotNil(t, results[i])
	}
}

// Helper functions

func createTestTask() CrossCoWTaskManager.TradeMatchingTask {
	return CrossCoWTaskManager.TradeMatchingTask{
		TaskIndex: 1,
		Intents: []CrossCoWTaskManager.Intent{
			createTestIntent(),
			createCompatibleIntent(createTestIntent()),
		},
		MaxSlippage:      big.NewInt(50), // 5%
		Deadline:         uint32(time.Now().Add(1 * time.Hour).Unix()),
		TaskCreatedBlock: 1000,
		IntentPoolHash:   [32]byte{},
	}
}

func createTestIntent() CrossCoWTaskManager.Intent {
	return CrossCoWTaskManager.Intent{
		User:              common.HexToAddress("0x1234567890123456789012345678901234567890"),
		InputToken:        common.HexToAddress("0x1111111111111111111111111111111111111111"),
		OutputToken:       common.HexToAddress("0x2222222222222222222222222222222222222222"),
		InputAmount:       big.NewInt(1000000000000000000), // 1 ETH
		MinOutputAmount:   big.NewInt(950000000000000000),  // 0.95 ETH
		SourceChain:       1,
		DestinationChain:  2,
		Deadline:          uint32(time.Now().Add(1 * time.Hour).Unix()),
		Signature:         []byte("test_signature"),
	}
}

func createCompatibleIntent(baseIntent CrossCoWTaskManager.Intent) CrossCoWTaskManager.Intent {
	return CrossCoWTaskManager.Intent{
		User:              common.HexToAddress("0x2345678901234567890123456789012345678901"),
		InputToken:        baseIntent.OutputToken,  // Swapped
		OutputToken:       baseIntent.InputToken,   // Swapped
		InputAmount:       baseIntent.InputAmount,
		MinOutputAmount:   baseIntent.MinOutputAmount,
		SourceChain:       baseIntent.DestinationChain, // Swapped
		DestinationChain:  baseIntent.SourceChain,      // Swapped
		Deadline:          baseIntent.Deadline,
		Signature:         []byte("compatible_signature"),
	}
}

func createIncompatibleIntent(baseIntent CrossCoWTaskManager.Intent) CrossCoWTaskManager.Intent {
	return CrossCoWTaskManager.Intent{
		User:              common.HexToAddress("0x3456789012345678901234567890123456789012"),
		InputToken:        common.HexToAddress("0x3333333333333333333333333333333333333333"), // Different token
		OutputToken:       common.HexToAddress("0x4444444444444444444444444444444444444444"), // Different token
		InputAmount:       baseIntent.InputAmount,
		MinOutputAmount:   baseIntent.MinOutputAmount,
		SourceChain:       baseIntent.SourceChain,
		DestinationChain:  baseIntent.DestinationChain,
		Deadline:          baseIntent.Deadline,
		Signature:         []byte("incompatible_signature"),
	}
}

func createCompatibleIntents() []CrossCoWTaskManager.Intent {
	intent1 := createTestIntent()
	intent2 := createCompatibleIntent(intent1)
	return []CrossCoWTaskManager.Intent{intent1, intent2}
}

func createIncompatibleIntents() []CrossCoWTaskManager.Intent {
	intent1 := createTestIntent()
	intent2 := createIncompatibleIntent(intent1)
	return []CrossCoWTaskManager.Intent{intent1, intent2}
}

func BenchmarkProcessTask(b *testing.B) {
	logger := logging.NewNoopLogger()
	blsKeyPair, err := crypto.GenerateBLSKeyPair()
	if err != nil {
		b.Fatal(err)
	}
	
	ecdsaKey, err := crypto.GenerateKey()
	if err != nil {
		b.Fatal(err)
	}
	
	operatorAddr := crypto.PubkeyToAddress(ecdsaKey.PublicKey)
	
	processor := NewTaskProcessor(logger, blsKeyPair, ecdsaKey, operatorAddr)
	task := createTestTask()
	
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, err := processor.ProcessTask(context.Background(), task)
		if err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkFindOptimalMatches(b *testing.B) {
	logger := logging.NewNoopLogger()
	blsKeyPair, err := crypto.GenerateBLSKeyPair()
	if err != nil {
		b.Fatal(err)
	}
	
	ecdsaKey, err := crypto.GenerateKey()
	if err != nil {
		b.Fatal(err)
	}
	
	operatorAddr := crypto.PubkeyToAddress(ecdsaKey.PublicKey)
	
	processor := NewTaskProcessor(logger, blsKeyPair, ecdsaKey, operatorAddr)
	intents := createCompatibleIntents()
	maxSlippage := big.NewInt(50)
	
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, err := processor.findOptimalMatches(intents, maxSlippage)
		if err != nil {
			b.Fatal(err)
		}
	}
}
