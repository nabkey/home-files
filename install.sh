#!/bin/sh
#
# homestruct config installer script
#
# Downloads pre-generated config files from GitHub releases and installs them
# to your home directory.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/nabkey/home-files/main/install.sh | sh
#
# Options (via environment variables):
#   HOMESTRUCT_VERSION  - Version to install (default: latest)
#   HOMESTRUCT_DRY_RUN  - Show what would be installed without making changes (default: false)
#   HOMESTRUCT_BACKUP   - Backup existing files before overwriting (default: true)
#   HOMESTRUCT_FORCE    - Overwrite without prompts (default: false)
#
# Examples:
#   # Install latest configs
#   curl -fsSL https://raw.githubusercontent.com/nabkey/home-files/main/install.sh | sh
#
#   # Preview what would be installed
#   curl -fsSL https://raw.githubusercontent.com/nabkey/home-files/main/install.sh | HOMESTRUCT_DRY_RUN=true sh
#
#   # Install specific version
#   curl -fsSL https://raw.githubusercontent.com/nabkey/home-files/main/install.sh | HOMESTRUCT_VERSION=v1.0.0 sh
#
#   # Install without backup
#   curl -fsSL https://raw.githubusercontent.com/nabkey/home-files/main/install.sh | HOMESTRUCT_BACKUP=false sh
#

set -e

REPO="nabkey/home-files"

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

# Backup a file
backup_file() {
    FILE="$1"
    BACKUP_DIR="$2"

    if [ -e "$FILE" ]; then
        REL_PATH="${FILE#$HOME/}"
        BACKUP_PATH="${BACKUP_DIR}/${REL_PATH}"
        mkdir -p "$(dirname "$BACKUP_PATH")"
        cp -a "$FILE" "$BACKUP_PATH"
        info "Backed up: $REL_PATH"
    fi
}

# Main installation function
main() {
    info "Starting homestruct config installation..."

    # Parse options
    DRY_RUN="${HOMESTRUCT_DRY_RUN:-false}"
    DO_BACKUP="${HOMESTRUCT_BACKUP:-true}"
    FORCE="${HOMESTRUCT_FORCE:-false}"

    # Detect system
    OS=$(detect_os)
    info "Detected OS: ${OS}"

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
    ARCHIVE_NAME="configs-${OS}.tar.gz"
    DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${VERSION}/${ARCHIVE_NAME}"
    info "Download URL: ${DOWNLOAD_URL}"

    # Create temp directory
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT

    # Download archive
    info "Downloading ${ARCHIVE_NAME}..."
    TMP_ARCHIVE="${TMP_DIR}/${ARCHIVE_NAME}"
    download "$DOWNLOAD_URL" "$TMP_ARCHIVE"

    # Extract to temp location for inspection
    EXTRACT_DIR="${TMP_DIR}/extracted"
    mkdir -p "$EXTRACT_DIR"
    tar -xzf "$TMP_ARCHIVE" -C "$EXTRACT_DIR"

    # List files to be installed
    info "Files to be installed:"
    cd "$EXTRACT_DIR"
    find . -type f | while read -r file; do
        REL_PATH="${file#./}"
        DEST="${HOME}/${REL_PATH}"
        if [ -e "$DEST" ]; then
            printf "  ${YELLOW}[UPDATE]${NC} %s\n" "$REL_PATH"
        else
            printf "  ${GREEN}[CREATE]${NC} %s\n" "$REL_PATH"
        fi
    done

    # Dry run - stop here
    if [ "$DRY_RUN" = "true" ]; then
        echo ""
        info "Dry run complete. No files were modified."
        exit 0
    fi

    # Confirm installation (unless forced)
    if [ "$FORCE" != "true" ]; then
        echo ""
        printf "Proceed with installation? [y/N] "
        read -r CONFIRM
        case "$CONFIRM" in
            [yY]|[yY][eE][sS])
                ;;
            *)
                info "Installation cancelled."
                exit 0
                ;;
        esac
    fi

    # Create backup directory if needed
    if [ "$DO_BACKUP" = "true" ]; then
        BACKUP_DIR="${HOME}/.homestruct-backup/$(date +%Y%m%d-%H%M%S)"
        info "Backup directory: ${BACKUP_DIR}"
    fi

    # Install files
    cd "$EXTRACT_DIR"
    find . -type f | while read -r file; do
        REL_PATH="${file#./}"
        DEST="${HOME}/${REL_PATH}"

        # Backup existing file
        if [ "$DO_BACKUP" = "true" ] && [ -e "$DEST" ]; then
            backup_file "$DEST" "$BACKUP_DIR"
        fi

        # Create parent directory
        mkdir -p "$(dirname "$DEST")"

        # Copy file
        cp -a "$file" "$DEST"
        success "Installed: ${REL_PATH}"
    done

    echo ""
    success "Installation complete!"
    if [ "$DO_BACKUP" = "true" ] && [ -d "$BACKUP_DIR" ]; then
        info "Backups stored in: ${BACKUP_DIR}"
    fi
}

main "$@"
