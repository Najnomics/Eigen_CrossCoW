package crypto

import (
	"testing"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestGenerateBLSKeyPair(t *testing.T) {
	keyPair, err := GenerateBLSKeyPair()
	require.NoError(t, err)
	require.NotNil(t, keyPair)
	
	// Test private key length
	assert.Equal(t, 32, len(keyPair.PrivateKey))
	
	// Test public key lengths
	assert.Equal(t, 48, len(keyPair.PublicKey.G1Pubkey))
	assert.Equal(t, 96, len(keyPair.PublicKey.G2Pubkey))
	
	// Test validation
	err = ValidateBLSKeyPair(keyPair)
	assert.NoError(t, err)
}

func TestBLSSignature(t *testing.T) {
	keyPair, err := GenerateBLSKeyPair()
	require.NoError(t, err)
	
	message := []byte("test message")
	
	// Test signing
	signature, err := keyPair.SignBLS(message)
	require.NoError(t, err)
	require.NotNil(t, signature)
	assert.Equal(t, 96, len(signature))
	
	// Test verification
	valid, err := VerifyBLS(keyPair.PublicKey, message, signature)
	require.NoError(t, err)
	assert.True(t, valid)
}

func TestBLSVerification(t *testing.T) {
	keyPair, err := GenerateBLSKeyPair()
	require.NoError(t, err)
	
	message := []byte("test message")
	signature, err := keyPair.SignBLS(message)
	require.NoError(t, err)
	
	// Test with correct message
	valid, err := VerifyBLS(keyPair.PublicKey, message, signature)
	require.NoError(t, err)
	assert.True(t, valid)
	
	// Test with wrong message
	wrongMessage := []byte("wrong message")
	valid, err = VerifyBLS(keyPair.PublicKey, wrongMessage, signature)
	require.NoError(t, err)
	assert.False(t, valid)
	
	// Test with wrong signature
	wrongSignature := make([]byte, 96)
	valid, err = VerifyBLS(keyPair.PublicKey, message, wrongSignature)
	require.NoError(t, err)
	assert.False(t, valid)
}

func TestAggregateBLS(t *testing.T) {
	// Generate multiple key pairs
	keyPairs := make([]*BLSKeyPair, 3)
	for i := 0; i < 3; i++ {
		keyPair, err := GenerateBLSKeyPair()
		require.NoError(t, err)
		keyPairs[i] = keyPair
	}
	
	// Sign the same message with all keys
	message := []byte("test message")
	signatures := make([][]byte, 3)
	for i, keyPair := range keyPairs {
		signature, err := keyPair.SignBLS(message)
		require.NoError(t, err)
		signatures[i] = signature
	}
	
	// Aggregate signatures
	aggregated, err := AggregateBLS(signatures)
	require.NoError(t, err)
	require.NotNil(t, aggregated)
	assert.Equal(t, 3*96, len(aggregated))
}

func TestVerifyAggregatedBLS(t *testing.T) {
	// Generate multiple key pairs
	keyPairs := make([]*BLSKeyPair, 3)
	for i := 0; i < 3; i++ {
		keyPair, err := GenerateBLSKeyPair()
		require.NoError(t, err)
		keyPairs[i] = keyPair
	}
	
	// Sign the same message with all keys
	message := []byte("test message")
	signatures := make([][]byte, 3)
	for i, keyPair := range keyPairs {
		signature, err := keyPair.SignBLS(message)
		require.NoError(t, err)
		signatures[i] = signature
	}
	
	// Aggregate signatures
	aggregated, err := AggregateBLS(signatures)
	require.NoError(t, err)
	
	// Extract public keys
	publicKeys := make([]BLSPublicKey, 3)
	for i, keyPair := range keyPairs {
		publicKeys[i] = keyPair.PublicKey
	}
	
	// Verify aggregated signature
	valid, err := VerifyAggregatedBLS(publicKeys, message, aggregated)
	require.NoError(t, err)
	assert.True(t, valid)
}

func TestGetBLSAddress(t *testing.T) {
	keyPair, err := GenerateBLSKeyPair()
	require.NoError(t, err)
	
	address, err := GetBLSAddress(keyPair.PublicKey)
	require.NoError(t, err)
	assert.NotEqual(t, common.Address{}, address)
}

func TestValidateBLSKeyPair(t *testing.T) {
	// Test valid key pair
	keyPair, err := GenerateBLSKeyPair()
	require.NoError(t, err)
	
	err = ValidateBLSKeyPair(keyPair)
	assert.NoError(t, err)
	
	// Test nil key pair
	err = ValidateBLSKeyPair(nil)
	assert.Error(t, err)
	
	// Test invalid private key length
	invalidKeyPair := &BLSKeyPair{
		PrivateKey: make([]byte, 16), // Wrong length
		PublicKey: BLSPublicKey{
			G1Pubkey: make([]byte, 48),
			G2Pubkey: make([]byte, 96),
		},
	}
	err = ValidateBLSKeyPair(invalidKeyPair)
	assert.Error(t, err)
	
	// Test invalid public key lengths
	invalidKeyPair = &BLSKeyPair{
		PrivateKey: make([]byte, 32),
		PublicKey: BLSPublicKey{
			G1Pubkey: make([]byte, 32), // Wrong length
			G2Pubkey: make([]byte, 96),
		},
	}
	err = ValidateBLSKeyPair(invalidKeyPair)
	assert.Error(t, err)
}

func TestBLSKeyPairConcurrency(t *testing.T) {
	// Test concurrent key pair generation
	keyPairs := make([]*BLSKeyPair, 10)
	errors := make([]error, 10)
	
	for i := 0; i < 10; i++ {
		go func(index int) {
			keyPair, err := GenerateBLSKeyPair()
			keyPairs[index] = keyPair
			errors[index] = err
		}(i)
	}
	
	// Wait for all goroutines to complete
	time.Sleep(100 * time.Millisecond)
	
	// Check results
	for i := 0; i < 10; i++ {
		assert.NoError(t, errors[i])
		assert.NotNil(t, keyPairs[i])
	}
}

func TestBLSKeyPairUniqueness(t *testing.T) {
	// Generate multiple key pairs and ensure they're unique
	keyPairs := make([]*BLSKeyPair, 100)
	for i := 0; i < 100; i++ {
		keyPair, err := GenerateBLSKeyPair()
		require.NoError(t, err)
		keyPairs[i] = keyPair
	}
	
	// Check uniqueness of private keys
	privateKeys := make(map[string]bool)
	for _, keyPair := range keyPairs {
		keyStr := string(keyPair.PrivateKey)
		assert.False(t, privateKeys[keyStr], "Duplicate private key found")
		privateKeys[keyStr] = true
	}
	
	// Check uniqueness of public keys
	publicKeys := make(map[string]bool)
	for _, keyPair := range keyPairs {
		keyStr := string(keyPair.PublicKey.G1Pubkey) + string(keyPair.PublicKey.G2Pubkey)
		assert.False(t, publicKeys[keyStr], "Duplicate public key found")
		publicKeys[keyStr] = true
	}
}

func BenchmarkGenerateBLSKeyPair(b *testing.B) {
	for i := 0; i < b.N; i++ {
		_, err := GenerateBLSKeyPair()
		if err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkBLSSignature(b *testing.B) {
	keyPair, err := GenerateBLSKeyPair()
	if err != nil {
		b.Fatal(err)
	}
	
	message := []byte("test message")
	
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, err := keyPair.SignBLS(message)
		if err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkBLSVerification(b *testing.B) {
	keyPair, err := GenerateBLSKeyPair()
	if err != nil {
		b.Fatal(err)
	}
	
	message := []byte("test message")
	signature, err := keyPair.SignBLS(message)
	if err != nil {
		b.Fatal(err)
	}
	
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, err := VerifyBLS(keyPair.PublicKey, message, signature)
		if err != nil {
			b.Fatal(err)
		}
	}
}
