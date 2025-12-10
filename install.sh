#!/bin/sh
#
# homestruct installer script
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/nabkey/home-files/main/install.sh | sh
#
# Options (via environment variables):
#   HOMESTRUCT_VERSION  - Version to install (default: latest)
#   HOMESTRUCT_INSTALL_DIR - Installation directory (default: /usr/local/bin or ~/.local/bin)
#   HOMESTRUCT_RUN_GENERATE - Run 'homestruct generate' after install (default: false)
#   HOMESTRUCT_DRY_RUN - Run 'homestruct generate --dry-run' after install (default: false)
#
# Examples:
#   # Install latest version
#   curl -fsSL https://raw.githubusercontent.com/nabkey/home-files/main/install.sh | sh
#
#   # Install specific version
#   curl -fsSL https://raw.githubusercontent.com/nabkey/home-files/main/install.sh | HOMESTRUCT_VERSION=v1.0.0 sh
#
#   # Install and run generate
#   curl -fsSL https://raw.githubusercontent.com/nabkey/home-files/main/install.sh | HOMESTRUCT_RUN_GENERATE=true sh
#
#   # Install to custom directory
#   curl -fsSL https://raw.githubusercontent.com/nabkey/home-files/main/install.sh | HOMESTRUCT_INSTALL_DIR=~/bin sh
#

set -e

REPO="nabkey/home-files"
BINARY_NAME="homestruct"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
info() {
    printf "${BLUE}[INFO]${NC} %s\n" "$1"
}

success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"
}

warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
    exit 1
}

# Detect OS
detect_os() {
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    case "$OS" in
        darwin)
            echo "darwin"
            ;;
        linux)
            echo "linux"
            ;;
        *)
            error "Unsupported operating system: $OS"
            ;;
    esac
}

# Detect architecture
detect_arch() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64)
            echo "amd64"
            ;;
        arm64|aarch64)
            echo "arm64"
            ;;
        *)
            error "Unsupported architecture: $ARCH"
            ;;
    esac
}

# Get latest release version from GitHub API
get_latest_version() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/'
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/'
    else
        error "Neither curl nor wget found. Please install one of them."
    fi
}

# Download file
download() {
    URL="$1"
    OUTPUT="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$OUTPUT" "$URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$OUTPUT" "$URL"
    else
        error "Neither curl nor wget found. Please install one of them."
    fi
}

# Determine install directory
get_install_dir() {
    if [ -n "$HOMESTRUCT_INSTALL_DIR" ]; then
        echo "$HOMESTRUCT_INSTALL_DIR"
        return
    fi

    # Check if /usr/local/bin is writable
    if [ -w "/usr/local/bin" ]; then
        echo "/usr/local/bin"
    else
        # Fall back to ~/.local/bin
        LOCAL_BIN="${HOME}/.local/bin"
        mkdir -p "$LOCAL_BIN"
        echo "$LOCAL_BIN"
    fi
}

# Main installation function
main() {
    info "Starting homestruct installation..."

    # Detect system
    OS=$(detect_os)
    ARCH=$(detect_arch)
    info "Detected system: ${OS}/${ARCH}"

    # Validate OS/ARCH combination
    if [ "$OS" = "darwin" ] && [ "$ARCH" = "amd64" ]; then
        warn "Intel Mac detected - using darwin-arm64 binary (Rosetta compatible)"
        ARCH="arm64"
    elif [ "$OS" = "linux" ] && [ "$ARCH" = "arm64" ]; then
        error "Linux ARM64 is not currently supported. Only linux-amd64 is available."
    fi

    # Get version
    VERSION="${HOMESTRUCT_VERSION:-}"
    if [ -z "$VERSION" ]; then
        info "Fetching latest version..."
        VERSION=$(get_latest_version)
        if [ -z "$VERSION" ]; then
            error "Could not determine latest version. Please specify HOMESTRUCT_VERSION."
        fi
    fi
    info "Version: ${VERSION}"

    # Build download URL
    BINARY_FILENAME="${BINARY_NAME}-${OS}-${ARCH}"
    DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${VERSION}/${BINARY_FILENAME}"
    info "Download URL: ${DOWNLOAD_URL}"

    # Create temp directory
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT

    # Download binary
    info "Downloading ${BINARY_FILENAME}..."
    TMP_BINARY="${TMP_DIR}/${BINARY_NAME}"
    download "$DOWNLOAD_URL" "$TMP_BINARY"

    # Make executable
    chmod +x "$TMP_BINARY"

    # Verify binary works
    info "Verifying binary..."
    if ! "$TMP_BINARY" help >/dev/null 2>&1; then
        error "Downloaded binary failed verification"
    fi

    # Determine install location
    INSTALL_DIR=$(get_install_dir)
    INSTALL_PATH="${INSTALL_DIR}/${BINARY_NAME}"

    # Check if we need sudo
    NEED_SUDO=""
    if [ ! -w "$INSTALL_DIR" ]; then
        if command -v sudo >/dev/null 2>&1; then
            NEED_SUDO="sudo"
            info "Installing to ${INSTALL_PATH} (requires sudo)..."
        else
            error "Cannot write to ${INSTALL_DIR} and sudo is not available"
        fi
    else
        info "Installing to ${INSTALL_PATH}..."
    fi

    # Install binary
    $NEED_SUDO mv "$TMP_BINARY" "$INSTALL_PATH"

    success "homestruct ${VERSION} installed successfully to ${INSTALL_PATH}"

    # Check if install dir is in PATH
    case ":$PATH:" in
        *":${INSTALL_DIR}:"*)
            ;;
        *)
            warn "${INSTALL_DIR} is not in your PATH"
            warn "Add it with: export PATH=\"${INSTALL_DIR}:\$PATH\""
            ;;
    esac

    # Run generate if requested
    if [ "${HOMESTRUCT_RUN_GENERATE:-false}" = "true" ]; then
        info "Running 'homestruct generate'..."
        "$INSTALL_PATH" generate
        success "Home files generated successfully!"
    elif [ "${HOMESTRUCT_DRY_RUN:-false}" = "true" ]; then
        info "Running 'homestruct generate --dry-run'..."
        "$INSTALL_PATH" generate --dry-run
    fi

    echo ""
    success "Installation complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Preview changes:  homestruct generate --dry-run"
    echo "  2. Apply changes:    homestruct generate"
    echo ""
}

main "$@"
