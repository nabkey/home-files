#!/bin/sh
# install.sh - Install homestruct binary
# Usage: curl -fsSL https://raw.githubusercontent.com/nabkey/home-files/main/install.sh | sh
#
# Environment variables:
#   HOMESTRUCT_VERSION  - Version to install (default: latest)
#   HOMESTRUCT_INSTALL  - Installation directory (default: /usr/local/bin or ~/.local/bin)

set -e

REPO="nabkey/home-files"
BINARY_NAME="homestruct"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
    exit 1
}

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Darwin)
            echo "darwin"
            ;;
        Linux)
            echo "linux"
            ;;
        *)
            error "Unsupported operating system: $(uname -s)"
            ;;
    esac
}

# Detect architecture
detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)
            echo "amd64"
            ;;
        arm64|aarch64)
            echo "arm64"
            ;;
        *)
            error "Unsupported architecture: $(uname -m)"
            ;;
    esac
}

# Get the latest release version from GitHub
get_latest_version() {
    curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | \
        grep '"tag_name":' | \
        sed -E 's/.*"([^"]+)".*/\1/'
}

# Determine installation directory
get_install_dir() {
    if [ -n "${HOMESTRUCT_INSTALL}" ]; then
        echo "${HOMESTRUCT_INSTALL}"
    elif [ -w "/usr/local/bin" ]; then
        echo "/usr/local/bin"
    else
        mkdir -p "${HOME}/.local/bin"
        echo "${HOME}/.local/bin"
    fi
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

main() {
    info "Installing ${BINARY_NAME}..."

    # Detect platform
    OS=$(detect_os)
    ARCH=$(detect_arch)
    info "Detected platform: ${OS}/${ARCH}"

    # Get version
    if [ -n "${HOMESTRUCT_VERSION}" ]; then
        VERSION="${HOMESTRUCT_VERSION}"
    else
        info "Fetching latest version..."
        VERSION=$(get_latest_version)
        if [ -z "${VERSION}" ]; then
            error "Failed to fetch latest version. Please set HOMESTRUCT_VERSION manually."
        fi
    fi
    info "Version: ${VERSION}"

    # Construct download URL
    DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${VERSION}/${BINARY_NAME}-${OS}-${ARCH}"
    info "Download URL: ${DOWNLOAD_URL}"

    # Get installation directory
    INSTALL_DIR=$(get_install_dir)
    INSTALL_PATH="${INSTALL_DIR}/${BINARY_NAME}"
    info "Installation path: ${INSTALL_PATH}"

    # Create temp directory
    TMP_DIR=$(mktemp -d)
    TMP_FILE="${TMP_DIR}/${BINARY_NAME}"
    trap "rm -rf ${TMP_DIR}" EXIT

    # Download binary
    info "Downloading ${BINARY_NAME}..."
    if command_exists curl; then
        curl -fsSL -o "${TMP_FILE}" "${DOWNLOAD_URL}"
    elif command_exists wget; then
        wget -q -O "${TMP_FILE}" "${DOWNLOAD_URL}"
    else
        error "Neither curl nor wget found. Please install one of them."
    fi

    # Make executable
    chmod +x "${TMP_FILE}"

    # Verify binary works
    if ! "${TMP_FILE}" --help >/dev/null 2>&1; then
        error "Downloaded binary appears to be invalid"
    fi

    # Install binary
    if [ -w "${INSTALL_DIR}" ]; then
        mv "${TMP_FILE}" "${INSTALL_PATH}"
    else
        info "Requesting sudo access to install to ${INSTALL_DIR}..."
        sudo mv "${TMP_FILE}" "${INSTALL_PATH}"
    fi

    info "Successfully installed ${BINARY_NAME} to ${INSTALL_PATH}"

    # Check if install dir is in PATH
    case ":${PATH}:" in
        *":${INSTALL_DIR}:"*)
            ;;
        *)
            warn "${INSTALL_DIR} is not in your PATH"
            warn "Add this to your shell profile:"
            warn "  export PATH=\"${INSTALL_DIR}:\$PATH\""
            ;;
    esac

    # Print version
    echo ""
    info "Installation complete!"
    "${INSTALL_PATH}" --help
}

main "$@"
