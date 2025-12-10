.PHONY: build release clean test dry-run install install-local

# Binary name
BINARY_NAME=homestruct

# Build directories
DIST_DIR=dist
CMD_DIR=cmd/homestruct

# Go build flags
LDFLAGS=-s -w

# Version (from git tag or "dev")
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")

# Default target
all: build

# Build for current platform
build:
	go build -ldflags="$(LDFLAGS) -X main.Version=$(VERSION)" -o $(BINARY_NAME) ./$(CMD_DIR)

# Build release binaries for all supported platforms
release: clean
	mkdir -p $(DIST_DIR)
	GOOS=darwin GOARCH=arm64 go build -ldflags="$(LDFLAGS)" -o $(DIST_DIR)/$(BINARY_NAME)-darwin-arm64 ./$(CMD_DIR)
	GOOS=darwin GOARCH=amd64 go build -ldflags="$(LDFLAGS)" -o $(DIST_DIR)/$(BINARY_NAME)-darwin-amd64 ./$(CMD_DIR)
	GOOS=linux GOARCH=amd64 go build -ldflags="$(LDFLAGS)" -o $(DIST_DIR)/$(BINARY_NAME)-linux-amd64 ./$(CMD_DIR)
	GOOS=linux GOARCH=arm64 go build -ldflags="$(LDFLAGS)" -o $(DIST_DIR)/$(BINARY_NAME)-linux-arm64 ./$(CMD_DIR)
	@echo "Release binaries built in $(DIST_DIR)/"
	@ls -la $(DIST_DIR)/

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

# Install to /usr/local/bin (requires sudo on most systems)
install: build
	install -m 755 $(BINARY_NAME) /usr/local/bin/$(BINARY_NAME)

# Install to ~/.local/bin (no sudo required)
install-local: build
	mkdir -p $(HOME)/.local/bin
	install -m 755 $(BINARY_NAME) $(HOME)/.local/bin/$(BINARY_NAME)
	@echo "Installed to $(HOME)/.local/bin/$(BINARY_NAME)"
	@echo "Make sure $(HOME)/.local/bin is in your PATH"

# Uninstall from /usr/local/bin
uninstall:
	rm -f /usr/local/bin/$(BINARY_NAME)

# Uninstall from ~/.local/bin
uninstall-local:
	rm -f $(HOME)/.local/bin/$(BINARY_NAME)

# Help
help:
	@echo "Available targets:"
	@echo "  build         - Build for current platform"
	@echo "  release       - Build release binaries for all platforms"
	@echo "  clean         - Remove build artifacts"
	@echo "  test          - Run tests"
	@echo "  dry-run       - Build and run with --dry-run --verbose"
	@echo "  generate      - Build and run generate command"
	@echo "  fmt           - Format Go code"
	@echo "  lint          - Run linter"
	@echo "  install       - Install binary to /usr/local/bin"
	@echo "  install-local - Install binary to ~/.local/bin"
	@echo "  uninstall     - Remove from /usr/local/bin"
	@echo "  uninstall-local - Remove from ~/.local/bin"
