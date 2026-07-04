#!/bin/bash
################################################################################
# Standalone downloader for the mediastacks folder
# Downloads all files from the GitHub repo into /opt/dockge/stacks/
#
# Usage: sudo bash mediastacks.sh
################################################################################

set -euo pipefail

REPO="josephcooley/server-setup"
BRANCH="main"
SOURCE_DIR="mediastacks"
DEST_DIR="/opt/dockge/stacks"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}/${SOURCE_DIR}"
TREE_API="https://api.github.com/repos/${REPO}/git/trees/${BRANCH}?recursive=1"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}>>> $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC}  $1"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

if ! command -v curl &>/dev/null; then
    print_error "curl is required but not installed"
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    print_error "python3 is required but not installed"
    exit 1
fi

print_section "DOWNLOAD MEDIA STACKS"
print_info "Source: ${SOURCE_DIR}"
print_info "Destination: ${DEST_DIR}"

mkdir -p "$DEST_DIR"

print_info "Fetching file list from GitHub"
API_RESPONSE=$(curl -fsSL "$TREE_API")
if [[ -z "$API_RESPONSE" ]]; then
    print_error "Failed to reach GitHub API"
    exit 1
fi

STACK_FILES=$(echo "$API_RESPONSE" | awk '
    /"path"[[:space:]]*:[[:space:]]*"mediastacks\// { path=$0; sub(/^.*"path"[[:space:]]*:[[:space:]]*"/, "", path); sub(/".*$/, "", path) }
    /"type"[[:space:]]*:[[:space:]]*"blob"/ && path ~ /^mediastacks\// { print path; path="" }
')

if [[ -z "$STACK_FILES" ]]; then
    print_warning "No files found under ${SOURCE_DIR}/ in the repository"
    exit 0
fi

download_file() {
    local rel_path="$1"
    local dest_path="$2"
    local encoded_path

    encoded_path=$(python3 - "$rel_path" <<'PY'
import sys
from urllib.parse import quote
print(quote(sys.argv[1]))
PY
)

    if [[ -e "$dest_path" ]]; then
        print_info "Skipping existing file: ${rel_path}"
        return 0
    fi

    mkdir -p "$(dirname "$dest_path")"
    if curl -fsSL "${RAW_BASE}/${encoded_path}" -o "$dest_path"; then
        print_success "Downloaded: ${rel_path}"
    else
        print_warning "Failed to download: ${rel_path}"
    fi
}

while IFS= read -r FULL_PATH; do
    REL_PATH="${FULL_PATH#${SOURCE_DIR}/}"
    DEST_PATH="${DEST_DIR}/${REL_PATH}"
    download_file "$REL_PATH" "$DEST_PATH"
done <<< "$STACK_FILES"

print_section "COMPLETE"
print_success "Mediastacks downloaded to ${DEST_DIR}"