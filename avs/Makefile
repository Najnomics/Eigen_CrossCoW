# -----------------------------------------------------------------------------
# This Makefile is used for building the CrossCoW AVS application.
#
# It contains basic targets for building the application, installing dependencies,
# and building a Docker container.
#
# Modify each target as needed to suit your application's requirements.
# -----------------------------------------------------------------------------

GO = $(shell which go)
OUT = ./bin

build: deps
	@mkdir -p $(OUT) || true
	@echo "Building CrossCoW Performer binary..."
	go build -o $(OUT)/performer ./cmd/main.go

build-contracts:
	@echo "Building CrossCoW contracts..."
	cd .devkit/contracts && forge build

deps:
	GOPRIVATE=github.com/Layr-Labs/* go mod tidy

build/container:
	./.hourglass/scripts/buildContainer.sh

test: test-go test-forge

test-go::
	go test ./... -v -p 1

test-forge:
	cd .devkit/contracts && forge test

clean:
	rm -rf $(OUT)
	cd .devkit/contracts && forge clean

.PHONY: build build-contracts deps test test-go test-forge clean