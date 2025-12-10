.PHONY: build release release-checksums clean test dry-run

# Binary name
BINARY_NAME=homestruct

# Build directories
DIST_DIR=dist
CMD_DIR=cmd/homestruct

# Go build flags
LDFLAGS=-s -w

# Version (can be overridden: make release VERSION=v1.0.0)
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")

# Default target
all: build

# Build for current platform
build:
	go build -ldflags="$(LDFLAGS)" -o $(BINARY_NAME) ./$(CMD_DIR)

# Build release binaries for all supported platforms
release: clean
	mkdir -p $(DIST_DIR)
	@echo "Building release binaries for version $(VERSION)..."
	GOOS=darwin GOARCH=arm64 go build -ldflags="$(LDFLAGS)" -o $(DIST_DIR)/$(BINARY_NAME)-darwin-arm64 ./$(CMD_DIR)
	GOOS=linux GOARCH=amd64 go build -ldflags="$(LDFLAGS)" -o $(DIST_DIR)/$(BINARY_NAME)-linux-amd64 ./$(CMD_DIR)
	@echo "Release binaries built in $(DIST_DIR)/"
	@ls -la $(DIST_DIR)/

# Generate checksums for release binaries
release-checksums: release
	@echo "Generating checksums..."
	cd $(DIST_DIR) && sha256sum * > checksums.txt
	@cat $(DIST_DIR)/checksums.txt

# Clean build artifacts
clean:
	rm -f $(BINARY_NAME)
	rm -rf $(DIST_DIR)

# Run tests
test:
	go test -v ./...

# Run with dry-run (for development)
dry-run: build
	./$(BINARY_NAME) generate --dry-run --verbose

# Run generate (applies changes)
generate: build
	./$(BINARY_NAME) generate

# Format code
fmt:
	go fmt ./...

# Run linter
lint:
	golangci-lint run

# Install locally
install: build
	mv $(BINARY_NAME) /usr/local/bin/

# Help
help:
	@echo "Available targets:"
	@echo "  build             - Build for current platform"
	@echo "  release           - Build release binaries for darwin/arm64 and linux/amd64"
	@echo "  release-checksums - Build release binaries and generate checksums"
	@echo "  clean             - Remove build artifacts"
	@echo "  test              - Run tests"
	@echo "  dry-run           - Build and run with --dry-run --verbose"
	@echo "  generate          - Build and run generate command"
	@echo "  fmt               - Format Go code"
	@echo "  lint              - Run linter"
	@echo "  install           - Install binary to /usr/local/bin"
