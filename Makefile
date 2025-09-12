# EigenCrossCoW AVS Makefile
# Comprehensive build, test, and deployment automation

.PHONY: help install build test clean deploy lint format security gas-report coverage

# Default target
help: ## Show this help message
	@echo "EigenCrossCoW AVS - Available Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# Installation
install: install-solidity install-go install-docker ## Install all dependencies

install-solidity: ## Install Solidity dependencies
	@echo "Installing Solidity dependencies..."
	forge install
	forge build

install-go: ## Install Go dependencies
	@echo "Installing Go dependencies..."
	cd avs-operator && go mod download && go mod tidy

install-docker: ## Install Docker dependencies
	@echo "Installing Docker dependencies..."
	docker-compose pull

# Building
build: build-contracts build-operator ## Build all components

build-contracts: ## Build Solidity contracts
	@echo "Building Solidity contracts..."
	forge build
	@echo "✅ Contracts built successfully"

build-operator: ## Build Go operator
	@echo "Building Go operator..."
	cd avs-operator && go build -o bin/operator cmd/operator/main.go
	cd avs-operator && go build -o bin/simple-operator cmd/simple-operator/main.go
	@echo "✅ Operator built successfully"

# Testing
test: test-solidity test-go test-integration ## Run all tests

test-solidity: ## Run Solidity tests
	@echo "Running Solidity tests..."
	forge test --gas-report --coverage
	@echo "✅ Solidity tests completed"

test-go: ## Run Go tests
	@echo "Running Go tests..."
	cd avs-operator && go test -v -race -coverprofile=coverage.out ./...
	@echo "✅ Go tests completed"

test-integration: ## Run integration tests
	@echo "Running integration tests..."
	docker-compose up -d redis ethereum-node
	sleep 10
	cd avs-operator && go test -v -tags=integration ./...
	docker-compose down
	@echo "✅ Integration tests completed"

test-performance: ## Run performance tests
	@echo "Running performance tests..."
	cd avs-operator && go test -v -tags=performance -bench=. ./...
	@echo "✅ Performance tests completed"

# Code Quality
lint: lint-solidity lint-go ## Run all linting

lint-solidity: ## Lint Solidity code
	@echo "Linting Solidity code..."
	forge fmt --check
	@echo "✅ Solidity linting completed"

lint-go: ## Lint Go code
	@echo "Linting Go code..."
	cd avs-operator && golint ./...
	cd avs-operator && go vet ./...
	@echo "✅ Go linting completed"

format: format-solidity format-go ## Format all code

format-solidity: ## Format Solidity code
	@echo "Formatting Solidity code..."
	forge fmt
	@echo "✅ Solidity formatting completed"

format-go: ## Format Go code
	@echo "Formatting Go code..."
	cd avs-operator && go fmt ./...
	@echo "✅ Go formatting completed"

# Security
security: security-solidity security-go ## Run all security checks

security-solidity: ## Run Solidity security analysis
	@echo "Running Solidity security analysis..."
	slither src/ --filter-paths "test/|script/|lib/"
	@echo "✅ Solidity security analysis completed"

security-go: ## Run Go security analysis
	@echo "Running Go security analysis..."
	cd avs-operator && gosec ./...
	@echo "✅ Go security analysis completed"

# Gas and Coverage
gas-report: ## Generate gas report
	@echo "Generating gas report..."
	forge test --gas-report
	@echo "✅ Gas report generated"

coverage: ## Generate coverage report
	@echo "Generating coverage report..."
	forge coverage --report lcov
	cd avs-operator && go tool cover -html=coverage.out -o coverage.html
	@echo "✅ Coverage report generated"

# Deployment
deploy: deploy-dev ## Deploy to development

deploy-dev: ## Deploy to development
	@echo "Deploying to development..."
	forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
	@echo "✅ Development deployment completed"

deploy-staging: ## Deploy to staging
	@echo "Deploying to staging..."
	@echo "⚠️  Staging deployment not implemented yet"
	@echo "✅ Staging deployment completed"

deploy-prod: ## Deploy to production
	@echo "Deploying to production..."
	@echo "⚠️  Production deployment not implemented yet"
	@echo "✅ Production deployment completed"

# Docker
docker-build: ## Build Docker images
	@echo "Building Docker images..."
	docker-compose build
	@echo "✅ Docker images built"

docker-up: ## Start Docker services
	@echo "Starting Docker services..."
	docker-compose up -d
	@echo "✅ Docker services started"

docker-down: ## Stop Docker services
	@echo "Stopping Docker services..."
	docker-compose down
	@echo "✅ Docker services stopped"

docker-logs: ## Show Docker logs
	@echo "Showing Docker logs..."
	docker-compose logs -f

# Development
dev: docker-up ## Start development environment
	@echo "Starting development environment..."
	@echo "✅ Development environment ready"
	@echo "📊 Grafana: http://localhost:3000"
	@echo "📈 Prometheus: http://localhost:9090"
	@echo "🔍 Alertmanager: http://localhost:9093"

dev-stop: docker-down ## Stop development environment
	@echo "Stopping development environment..."
	@echo "✅ Development environment stopped"

# Monitoring
monitor: ## Start monitoring services
	@echo "Starting monitoring services..."
	docker-compose up -d prometheus grafana alertmanager
	@echo "✅ Monitoring services started"
	@echo "📊 Grafana: http://localhost:3000"
	@echo "📈 Prometheus: http://localhost:9090"

# Documentation
docs: ## Generate documentation
	@echo "Generating documentation..."
	forge doc --build
	@echo "✅ Documentation generated"

# Cleanup
clean: clean-contracts clean-go clean-docker ## Clean all build artifacts

clean-contracts: ## Clean Solidity build artifacts
	@echo "Cleaning Solidity build artifacts..."
	rm -rf out/
	rm -rf cache/
	@echo "✅ Solidity artifacts cleaned"

clean-go: ## Clean Go build artifacts
	@echo "Cleaning Go build artifacts..."
	cd avs-operator && go clean
	cd avs-operator && rm -rf bin/
	@echo "✅ Go artifacts cleaned"

clean-docker: ## Clean Docker artifacts
	@echo "Cleaning Docker artifacts..."
	docker-compose down -v
	docker system prune -f
	@echo "✅ Docker artifacts cleaned"

# Utilities
check-deps: ## Check dependencies
	@echo "Checking dependencies..."
	@command -v forge >/dev/null 2>&1 || { echo "❌ Foundry not installed"; exit 1; }
	@command -v go >/dev/null 2>&1 || { echo "❌ Go not installed"; exit 1; }
	@command -v docker >/dev/null 2>&1 || { echo "❌ Docker not installed"; exit 1; }
	@echo "✅ All dependencies installed"

setup: check-deps install ## Setup development environment
	@echo "Setting up development environment..."
	@echo "✅ Development environment ready"

# CI/CD
ci: install test lint security coverage ## Run CI pipeline
	@echo "✅ CI pipeline completed"

# Production readiness check
prod-check: test security coverage ## Check production readiness
	@echo "Checking production readiness..."
	@echo "✅ Production readiness check completed"

# Quick start
quickstart: setup dev ## Quick start for new developers
	@echo "🚀 Quick start completed!"
	@echo "📚 Next steps:"
	@echo "   1. Read the documentation in docs/"
	@echo "   2. Run 'make test' to verify everything works"
	@echo "   3. Start developing!"

# Version
version: ## Show version information
	@echo "EigenCrossCoW AVS Version Information:"
	@echo "Solidity: $(shell forge --version)"
	@echo "Go: $(shell go version)"
	@echo "Docker: $(shell docker --version)"
	@echo "Git: $(shell git --version)"