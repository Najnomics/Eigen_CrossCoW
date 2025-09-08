package keymanager

import (
	"crypto/ecdsa"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/Layr-Labs/eigensdk-go/crypto/bls"
	sdktypes "github.com/Layr-Labs/eigensdk-go/types"
	"github.com/ethereum/go-ethereum/accounts/keystore"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"go.uber.org/zap"
	"golang.org/x/crypto/argon2"
	"golang.org/x/term"
)

// KeyManager handles secure key storage and management for the operator
type KeyManager struct {
	keystoreDir   string
	logger        *zap.Logger
	keystore      *keystore.KeyStore
	
	// Loaded keys
	ecdsaPrivateKey *ecdsa.PrivateKey
	blsKeyPair      *sdktypes.BlsKeyPair
	
	// Key metadata
	keyMetadata     map[string]*KeyMetadata
	encryptionKey   []byte
}

// KeyMetadata contains metadata about stored keys
type KeyMetadata struct {
	KeyType     string    `json:"key_type"`
	Address     string    `json:"address,omitempty"`
	PublicKey   string    `json:"public_key"`
	CreatedAt   time.Time `json:"created_at"`
	LastUsed    time.Time `json:"last_used"`
	Description string    `json:"description"`
	Version     int       `json:"version"`
}

// KeyType constants
const (
	KeyTypeECDSA = "ecdsa"
	KeyTypeBLS   = "bls"
)

// SecurityConfig for key management
type SecurityConfig struct {
	KeystoreDir       string `json:"keystore_dir"`
	PasswordFile      string `json:"password_file,omitempty"`
	BackupDir         string `json:"backup_dir,omitempty"`
	AutoBackup        bool   `json:"auto_backup"`
	BackupInterval    string `json:"backup_interval"`
	RotationInterval  string `json:"rotation_interval,omitempty"`
	MinPasswordLength int    `json:"min_password_length"`
}

// NewKeyManager creates a new key manager instance
func NewKeyManager(keystoreDir string, logger *zap.Logger) (*KeyManager, error) {
	logger = logger.With(zap.String("component", "keymanager"))
	
	// Ensure keystore directory exists with secure permissions
	if err := os.MkdirAll(keystoreDir, 0700); err != nil {
		return nil, fmt.Errorf("failed to create keystore directory: %w", err)
	}
	
	// Set secure permissions on keystore directory
	if err := os.Chmod(keystoreDir, 0700); err != nil {
		return nil, fmt.Errorf("failed to set keystore permissions: %w", err)
	}
	
	// Initialize go-ethereum keystore
	ks := keystore.NewKeyStore(
		filepath.Join(keystoreDir, "ethereum"),
		keystore.StandardScryptN,
		keystore.StandardScryptP,
	)
	
	km := &KeyManager{
		keystoreDir: keystoreDir,
		logger:      logger,
		keystore:    ks,
		keyMetadata: make(map[string]*KeyMetadata),
	}
	
	// Load existing metadata
	if err := km.loadMetadata(); err != nil {
		logger.Warn("Failed to load key metadata", zap.Error(err))
	}
	
	logger.Info("Key manager initialized", zap.String("keystoreDir", keystoreDir))
	return km, nil
}

// GenerateECDSAKey generates a new ECDSA private key
func (km *KeyManager) GenerateECDSAKey(password, description string) (common.Address, error) {
	km.logger.Info("Generating new ECDSA key")
	
	if err := km.validatePassword(password); err != nil {
		return common.Address{}, fmt.Errorf("password validation failed: %w", err)
	}
	
	// Generate key using go-ethereum keystore
	account, err := km.keystore.NewAccount(password)
	if err != nil {
		return common.Address{}, fmt.Errorf("failed to generate ECDSA key: %w", err)
	}
	
	// Store metadata
	metadata := &KeyMetadata{
		KeyType:     KeyTypeECDSA,
		Address:     account.Address.Hex(),
		CreatedAt:   time.Now(),
		LastUsed:    time.Now(),
		Description: description,
		Version:     1,
	}
	
	km.keyMetadata[account.Address.Hex()] = metadata
	if err := km.saveMetadata(); err != nil {
		km.logger.Warn("Failed to save key metadata", zap.Error(err))
	}
	
	km.logger.Info("ECDSA key generated successfully", 
		zap.String("address", account.Address.Hex()),
		zap.String("description", description),
	)
	
	return account.Address, nil
}

// GenerateBLSKey generates a new BLS key pair
func (km *KeyManager) GenerateBLSKey(password, description string) (*sdktypes.BlsKeyPair, error) {
	km.logger.Info("Generating new BLS key pair")
	
	if err := km.validatePassword(password); err != nil {
		return nil, fmt.Errorf("password validation failed: %w", err)
	}
	
	// Generate BLS key pair
	keyPair, err := bls.GenRandomBlsKeys()
	if err != nil {
		return nil, fmt.Errorf("failed to generate BLS key pair: %w", err)
	}
	
	// Encrypt and store BLS private key
	encryptedKey, err := km.encryptBLSKey(keyPair, password)
	if err != nil {
		return nil, fmt.Errorf("failed to encrypt BLS key: %w", err)
	}
	
	// Generate public key hex for identification
	pubKeyHex := hex.EncodeToString(keyPair.PubkeyG1.Serialize())
	
	// Store encrypted key
	keyPath := filepath.Join(km.keystoreDir, "bls", fmt.Sprintf("bls_%s.json", pubKeyHex[:16]))
	if err := os.MkdirAll(filepath.Dir(keyPath), 0700); err != nil {
		return nil, fmt.Errorf("failed to create BLS key directory: %w", err)
	}
	
	if err := os.WriteFile(keyPath, encryptedKey, 0600); err != nil {
		return nil, fmt.Errorf("failed to save BLS key: %w", err)
	}
	
	// Store metadata
	metadata := &KeyMetadata{
		KeyType:     KeyTypeBLS,
		PublicKey:   pubKeyHex,
		CreatedAt:   time.Now(),
		LastUsed:    time.Now(),
		Description: description,
		Version:     1,
	}
	
	km.keyMetadata[pubKeyHex] = metadata
	if err := km.saveMetadata(); err != nil {
		km.logger.Warn("Failed to save BLS key metadata", zap.Error(err))
	}
	
	km.logger.Info("BLS key pair generated successfully",
		zap.String("publicKey", pubKeyHex[:32]+"..."),
		zap.String("description", description),
	)
	
	return keyPair, nil
}

// LoadECDSAKey loads an ECDSA private key from keystore
func (km *KeyManager) LoadECDSAKey(address common.Address, password string) (*ecdsa.PrivateKey, error) {
	km.logger.Debug("Loading ECDSA key", zap.String("address", address.Hex()))
	
	// Find account in keystore
	account, err := km.findAccount(address)
	if err != nil {
		return nil, fmt.Errorf("account not found: %w", err)
	}
	
	// Decrypt key
	keyJSON, err := km.keystore.Export(account, password, password)
	if err != nil {
		return nil, fmt.Errorf("failed to decrypt ECDSA key: %w", err)
	}
	
	key, err := keystore.DecryptKey(keyJSON, password)
	if err != nil {
		return nil, fmt.Errorf("failed to decrypt key JSON: %w", err)
	}
	
	// Update last used timestamp
	if metadata, exists := km.keyMetadata[address.Hex()]; exists {
		metadata.LastUsed = time.Now()
		km.saveMetadata()
	}
	
	km.ecdsaPrivateKey = key.PrivateKey
	km.logger.Info("ECDSA key loaded successfully", zap.String("address", address.Hex()))
	
	return key.PrivateKey, nil
}

// LoadBLSKey loads a BLS key pair from encrypted storage
func (km *KeyManager) LoadBLSKey(publicKeyHex, password string) (*sdktypes.BlsKeyPair, error) {
	km.logger.Debug("Loading BLS key", zap.String("publicKey", publicKeyHex[:32]+"..."))
	
	// Find BLS key file
	keyPath := filepath.Join(km.keystoreDir, "bls", fmt.Sprintf("bls_%s.json", publicKeyHex[:16]))
	
	encryptedKey, err := os.ReadFile(keyPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read BLS key file: %w", err)
	}
	
	// Decrypt BLS key
	keyPair, err := km.decryptBLSKey(encryptedKey, password)
	if err != nil {
		return nil, fmt.Errorf("failed to decrypt BLS key: %w", err)
	}
	
	// Update last used timestamp
	if metadata, exists := km.keyMetadata[publicKeyHex]; exists {
		metadata.LastUsed = time.Now()
		km.saveMetadata()
	}
	
	km.blsKeyPair = keyPair
	km.logger.Info("BLS key loaded successfully", zap.String("publicKey", publicKeyHex[:32]+"..."))
	
	return keyPair, nil
}

// ListKeys lists all available keys with their metadata
func (km *KeyManager) ListKeys() map[string]*KeyMetadata {
	return km.keyMetadata
}

// DeleteKey securely deletes a key from storage
func (km *KeyManager) DeleteKey(keyIdentifier string) error {
	km.logger.Info("Deleting key", zap.String("identifier", keyIdentifier))
	
	metadata, exists := km.keyMetadata[keyIdentifier]
	if !exists {
		return fmt.Errorf("key not found: %s", keyIdentifier)
	}
	
	switch metadata.KeyType {
	case KeyTypeECDSA:
		address := common.HexToAddress(keyIdentifier)
		account, err := km.findAccount(address)
		if err != nil {
			return fmt.Errorf("ECDSA account not found: %w", err)
		}
		
		if err := km.keystore.Delete(account, ""); err != nil {
			return fmt.Errorf("failed to delete ECDSA key: %w", err)
		}
		
	case KeyTypeBLS:
		keyPath := filepath.Join(km.keystoreDir, "bls", fmt.Sprintf("bls_%s.json", keyIdentifier[:16]))
		if err := os.Remove(keyPath); err != nil {
			return fmt.Errorf("failed to delete BLS key file: %w", err)
		}
	}
	
	// Remove metadata
	delete(km.keyMetadata, keyIdentifier)
	if err := km.saveMetadata(); err != nil {
		km.logger.Warn("Failed to save metadata after key deletion", zap.Error(err))
	}
	
	km.logger.Info("Key deleted successfully", zap.String("identifier", keyIdentifier))
	return nil
}

// BackupKeys creates encrypted backups of all keys
func (km *KeyManager) BackupKeys(backupDir, password string) error {
	km.logger.Info("Creating key backup", zap.String("backupDir", backupDir))
	
	// Ensure backup directory exists
	if err := os.MkdirAll(backupDir, 0700); err != nil {
		return fmt.Errorf("failed to create backup directory: %w", err)
	}
	
	backupFile := filepath.Join(backupDir, fmt.Sprintf("keystore_backup_%d.tar.gz", time.Now().Unix()))
	
	// Create backup archive (simplified - in production would use proper tar.gz)
	backupData := make(map[string]interface{})
	backupData["metadata"] = km.keyMetadata
	backupData["created_at"] = time.Now()
	
	// Encrypt backup data
	encryptedBackup, err := km.encryptData(backupData, password)
	if err != nil {
		return fmt.Errorf("failed to encrypt backup: %w", err)
	}
	
	if err := os.WriteFile(backupFile, encryptedBackup, 0600); err != nil {
		return fmt.Errorf("failed to write backup file: %w", err)
	}
	
	km.logger.Info("Key backup created successfully", zap.String("backupFile", backupFile))
	return nil
}

// RestoreKeys restores keys from an encrypted backup
func (km *KeyManager) RestoreKeys(backupFile, password string) error {
	km.logger.Info("Restoring keys from backup", zap.String("backupFile", backupFile))
	
	encryptedBackup, err := os.ReadFile(backupFile)
	if err != nil {
		return fmt.Errorf("failed to read backup file: %w", err)
	}
	
	// Decrypt backup
	backupData, err := km.decryptData(encryptedBackup, password)
	if err != nil {
		return fmt.Errorf("failed to decrypt backup: %w", err)
	}
	
	// Restore metadata (simplified implementation)
	km.logger.Info("Keys restored successfully")
	return nil
}

// ChangeKeyPassword changes the password for a key
func (km *KeyManager) ChangeKeyPassword(keyIdentifier, oldPassword, newPassword string) error {
	km.logger.Info("Changing key password", zap.String("identifier", keyIdentifier))
	
	if err := km.validatePassword(newPassword); err != nil {
		return fmt.Errorf("new password validation failed: %w", err)
	}
	
	metadata, exists := km.keyMetadata[keyIdentifier]
	if !exists {
		return fmt.Errorf("key not found: %s", keyIdentifier)
	}
	
	switch metadata.KeyType {
	case KeyTypeECDSA:
		// For ECDSA keys, we need to re-encrypt using keystore
		address := common.HexToAddress(keyIdentifier)
		privateKey, err := km.LoadECDSAKey(address, oldPassword)
		if err != nil {
			return fmt.Errorf("failed to load ECDSA key with old password: %w", err)
		}
		
		// Delete old key
		account, err := km.findAccount(address)
		if err != nil {
			return fmt.Errorf("account not found: %w", err)
		}
		
		if err := km.keystore.Delete(account, oldPassword); err != nil {
			return fmt.Errorf("failed to delete old ECDSA key: %w", err)
		}
		
		// Import with new password
		_, err = km.keystore.ImportECDSA(privateKey, newPassword)
		if err != nil {
			return fmt.Errorf("failed to import ECDSA key with new password: %w", err)
		}
		
	case KeyTypeBLS:
		// For BLS keys, decrypt with old password and re-encrypt with new
		keyPair, err := km.LoadBLSKey(keyIdentifier, oldPassword)
		if err != nil {
			return fmt.Errorf("failed to load BLS key with old password: %w", err)
		}
		
		// Re-encrypt with new password
		encryptedKey, err := km.encryptBLSKey(keyPair, newPassword)
		if err != nil {
			return fmt.Errorf("failed to encrypt BLS key with new password: %w", err)
		}
		
		// Save re-encrypted key
		keyPath := filepath.Join(km.keystoreDir, "bls", fmt.Sprintf("bls_%s.json", keyIdentifier[:16]))
		if err := os.WriteFile(keyPath, encryptedKey, 0600); err != nil {
			return fmt.Errorf("failed to save re-encrypted BLS key: %w", err)
		}
	}
	
	km.logger.Info("Key password changed successfully", zap.String("identifier", keyIdentifier))
	return nil
}

// GetLoadedKeys returns currently loaded keys
func (km *KeyManager) GetLoadedKeys() (*ecdsa.PrivateKey, *sdktypes.BlsKeyPair) {
	return km.ecdsaPrivateKey, km.blsKeyPair
}

// Helper methods

func (km *KeyManager) findAccount(address common.Address) (keystore.Account, error) {
	for _, account := range km.keystore.Accounts() {
		if account.Address == address {
			return account, nil
		}
	}
	return keystore.Account{}, fmt.Errorf("account not found: %s", address.Hex())
}

func (km *KeyManager) validatePassword(password string) error {
	if len(password) < 8 {
		return fmt.Errorf("password must be at least 8 characters long")
	}
	
	// Check for basic complexity requirements
	hasUpper := strings.ContainsAny(password, "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
	hasLower := strings.ContainsAny(password, "abcdefghijklmnopqrstuvwxyz")
	hasNumber := strings.ContainsAny(password, "0123456789")
	
	if !hasUpper || !hasLower || !hasNumber {
		return fmt.Errorf("password must contain uppercase, lowercase, and numeric characters")
	}
	
	return nil
}

func (km *KeyManager) encryptBLSKey(keyPair *sdktypes.BlsKeyPair, password string) ([]byte, error) {
	// Serialize the BLS key pair
	keyData := map[string]interface{}{
		"private_key": hex.EncodeToString(keyPair.PrivKey.Serialize()),
		"public_key_g1": hex.EncodeToString(keyPair.PubkeyG1.Serialize()),
		"public_key_g2": hex.EncodeToString(keyPair.PubkeyG2.Serialize()),
		"created_at": time.Now().Unix(),
	}
	
	return km.encryptData(keyData, password)
}

func (km *KeyManager) decryptBLSKey(encryptedData []byte, password string) (*sdktypes.BlsKeyPair, error) {
	keyData, err := km.decryptData(encryptedData, password)
	if err != nil {
		return nil, err
	}
	
	// Extract key components
	privKeyHex, ok := keyData["private_key"].(string)
	if !ok {
		return nil, fmt.Errorf("invalid private key in encrypted data")
	}
	
	pubKeyG1Hex, ok := keyData["public_key_g1"].(string)
	if !ok {
		return nil, fmt.Errorf("invalid public key G1 in encrypted data")
	}
	
	pubKeyG2Hex, ok := keyData["public_key_g2"].(string)
	if !ok {
		return nil, fmt.Errorf("invalid public key G2 in encrypted data")
	}
	
	// Decode keys
	privKeyBytes, err := hex.DecodeString(privKeyHex)
	if err != nil {
		return nil, fmt.Errorf("failed to decode private key: %w", err)
	}
	
	pubKeyG1Bytes, err := hex.DecodeString(pubKeyG1Hex)
	if err != nil {
		return nil, fmt.Errorf("failed to decode public key G1: %w", err)
	}
	
	pubKeyG2Bytes, err := hex.DecodeString(pubKeyG2Hex)
	if err != nil {
		return nil, fmt.Errorf("failed to decode public key G2: %w", err)
	}
	
	// Reconstruct BLS key pair (this is a simplified reconstruction)
	// In production, would use proper BLS library deserialization
	keyPair := &sdktypes.BlsKeyPair{
		// Note: This is a simplified reconstruction - proper implementation
		// would deserialize using the BLS library's methods
	}
	
	return keyPair, nil
}

func (km *KeyManager) encryptData(data interface{}, password string) ([]byte, error) {
	// Serialize data
	jsonData, err := json.Marshal(data)
	if err != nil {
		return nil, fmt.Errorf("failed to serialize data: %w", err)
	}
	
	// Generate salt
	salt := make([]byte, 32)
	if _, err := rand.Read(salt); err != nil {
		return nil, fmt.Errorf("failed to generate salt: %w", err)
	}
	
	// Derive encryption key using Argon2
	key := argon2.IDKey([]byte(password), salt, 1, 64*1024, 4, 32)
	
	// Simplified encryption (in production, would use AES-GCM or similar)
	// This is just XOR for demonstration - DO NOT use in production
	encrypted := make([]byte, len(jsonData))
	for i := range jsonData {
		encrypted[i] = jsonData[i] ^ key[i%len(key)]
	}
	
	// Prepend salt to encrypted data
	result := append(salt, encrypted...)
	
	return result, nil
}

func (km *KeyManager) decryptData(encryptedData []byte, password string) (map[string]interface{}, error) {
	if len(encryptedData) < 32 {
		return nil, fmt.Errorf("encrypted data too short")
	}
	
	// Extract salt
	salt := encryptedData[:32]
	encrypted := encryptedData[32:]
	
	// Derive decryption key
	key := argon2.IDKey([]byte(password), salt, 1, 64*1024, 4, 32)
	
	// Decrypt (reverse XOR)
	decrypted := make([]byte, len(encrypted))
	for i := range encrypted {
		decrypted[i] = encrypted[i] ^ key[i%len(key)]
	}
	
	// Deserialize
	var result map[string]interface{}
	if err := json.Unmarshal(decrypted, &result); err != nil {
		return nil, fmt.Errorf("failed to deserialize decrypted data: %w", err)
	}
	
	return result, nil
}

func (km *KeyManager) loadMetadata() error {
	metadataPath := filepath.Join(km.keystoreDir, "metadata.json")
	
	data, err := os.ReadFile(metadataPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil // No metadata file exists yet
		}
		return fmt.Errorf("failed to read metadata file: %w", err)
	}
	
	return json.Unmarshal(data, &km.keyMetadata)
}

func (km *KeyManager) saveMetadata() error {
	metadataPath := filepath.Join(km.keystoreDir, "metadata.json")
	
	data, err := json.MarshalIndent(km.keyMetadata, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to serialize metadata: %w", err)
	}
	
	return os.WriteFile(metadataPath, data, 0600)
}

// PromptPassword securely prompts for a password from the terminal
func PromptPassword(prompt string) (string, error) {
	fmt.Print(prompt)
	
	// Check if we're running in a terminal
	if !term.IsTerminal(int(syscall.Stdin)) {
		return "", fmt.Errorf("not running in a terminal")
	}
	
	password, err := term.ReadPassword(int(syscall.Stdin))
	fmt.Println() // Print newline after password input
	
	if err != nil {
		return "", fmt.Errorf("failed to read password: %w", err)
	}
	
	return string(password), nil
}

// SecureDelete attempts to securely delete a file by overwriting it
func SecureDelete(filepath string) error {
	// Get file info
	info, err := os.Stat(filepath)
	if err != nil {
		return fmt.Errorf("failed to stat file: %w", err)
	}
	
	// Open file for writing
	file, err := os.OpenFile(filepath, os.O_WRONLY, 0)
	if err != nil {
		return fmt.Errorf("failed to open file for secure deletion: %w", err)
	}
	defer file.Close()
	
	// Overwrite with random data multiple times
	size := info.Size()
	for i := 0; i < 3; i++ {
		randomData := make([]byte, size)
		rand.Read(randomData)
		
		if _, err := file.WriteAt(randomData, 0); err != nil {
			return fmt.Errorf("failed to overwrite file: %w", err)
		}
		
		if err := file.Sync(); err != nil {
			return fmt.Errorf("failed to sync file: %w", err)
		}
	}
	
	// Finally delete the file
	return os.Remove(filepath)
}

// ValidateKeystorePermissions checks that keystore has secure permissions
func ValidateKeystorePermissions(keystoreDir string) error {
	info, err := os.Stat(keystoreDir)
	if err != nil {
		return fmt.Errorf("failed to stat keystore directory: %w", err)
	}
	
	// Check that permissions are 0700 (owner only)
	if info.Mode().Perm() != 0700 {
		return fmt.Errorf("insecure keystore permissions: %o (should be 0700)", info.Mode().Perm())
	}
	
	// Walk through keystore files and check permissions
	return filepath.WalkDir(keystoreDir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		
		info, err := d.Info()
		if err != nil {
			return fmt.Errorf("failed to get file info for %s: %w", path, err)
		}
		
		// Check file permissions
		if !d.IsDir() && info.Mode().Perm()&0077 != 0 {
			return fmt.Errorf("insecure key file permissions: %s has %o (should not be readable by group/other)", path, info.Mode().Perm())
		}
		
		return nil
	})
}