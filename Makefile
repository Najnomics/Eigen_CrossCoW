# Makefile for Eigen CrossCoW
.PHONY: all build clean test test-unit test-integration test-fuzz test-invariant coverage deploy-local deploy-testnet deploy-mainnet verify format lint gas-report slither install-deps

# Default target
all: clean build test

# Build
build:
	forge build

clean:
	forge clean

# Dependencies
install-deps:
	forge install foundry-rs/forge-std --no-commit
	forge install OpenZeppelin/openzeppelin-contracts --no-commit
	forge install Layr-Labs/eigenlayer-contracts --no-commit
	forge install Uniswap/v4-core --no-commit
	forge install Uniswap/v4-periphery --no-commit
	forge install across-protocol/contracts --no-commit

# Testing
test:
	forge test

test-unit:
	forge test --match-path "test/unit/*" --no-match-path "test/integration/*" --no-match-path "test/fuzz/*" --no-match-path "test/invariant/*"

test-integration:
	forge test --match-path "test/integration/*"

test-fuzz:
	forge test --match-path "test/fuzz/*"

test-invariant:
	forge test --match-path "test/invariant/*"

coverage:
	forge coverage

# Deployment
deploy-local:
	forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast

deploy-testnet:
	forge script script/Deploy.s.sol --rpc-url $(TESTNET_RPC_URL) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY)

deploy-mainnet:
	forge script script/Deploy.s.sol --rpc-url $(MAINNET_RPC_URL) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY)

# Verification
verify-testnet:
	forge verify-contract --chain-id $(TESTNET_CHAIN_ID) --etherscan-api-key $(ETHERSCAN_API_KEY) $(CONTRACT_ADDRESS) src/hooks/EigenCrossCoWHook.sol:EigenCrossCoWHook

verify-mainnet:
	forge verify-contract --chain-id 1 --etherscan-api-key $(ETHERSCAN_API_KEY) $(CONTRACT_ADDRESS) src/hooks/EigenCrossCoWHook.sol:EigenCrossCoWHook

# Code quality
format:
	forge fmt

lint:
	forge fmt --check

gas-report:
	forge test --gas-report

slither:
	slither src/

# Local development
anvil:
	anvil --fork-url $(MAINNET_RPC_URL)

# Go operator commands
go-build:
	cd avs-operator && go build -o bin/operator cmd/operator/main.go

go-test:
	cd avs-operator && go test ./...

go-run:
	cd avs-operator && go run cmd/operator/main.go

# Docker commands
docker-build:
	docker build -t eigen-crosscow-operator avs-operator/

docker-run:
	docker run -p 8080:8080 eigen-crosscow-operator

# Full setup
setup: install-deps build test

# CI pipeline
ci: format lint test coverage gas-report slither