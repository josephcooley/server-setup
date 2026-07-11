#!/bin/bash
################################################################################
# Hermes post-launch downloader
# Downloads hermesconfig/ from this repository into /opt/stacks/hermes/agent
#
# Usage: sudo bash hermes-after-launch.sh
################################################################################

set -euo pipefail

REPO="josephcooley/server-setup"
BRANCH="main"
SOURCE_DIR="hermesconfig"
DEST_DIR="/opt/stacks/hermes/agent"
TREE_API="https://api.github.com/repos/${REPO}/git/trees/${BRANCH}?recursive=1"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

print_section() {
    echo ""
    echo "==================================================="
    echo ">>> $1"
    echo "==================================================="
    echo ""
}

print_info() {
    echo "[INFO]  $1"
}

print_success() {
    echo "[OK]    $1"
}

print_warning() {
    echo "[WARN]  $1"
}

print_error() {
    echo "[ERROR] $1"
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

require_tools() {
    if ! command -v curl >/dev/null 2>&1; then
        print_error "curl is required but not installed"
        exit 1
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        print_error "python3 is required but not installed"
        exit 1
    fi
}

fetch_file_list() {
    print_info "Fetching file list from GitHub API"
    API_RESPONSE=$(curl -fsSL "$TREE_API")
    if [[ -z "$API_RESPONSE" ]]; then
        print_error "Failed to reach GitHub API"
        exit 1
    fi
}

list_source_files() {
    echo "$API_RESPONSE" | awk -v source_dir="$SOURCE_DIR" '
        $0 ~ "\"path\"[[:space:]]*:[[:space:]]*\"" source_dir "/" {
            path=$0
            sub(/^.*"path"[[:space:]]*:[[:space:]]*"/, "", path)
            sub(/".*$/, "", path)
        }
        /"type"[[:space:]]*:[[:space:]]*"blob"/ && path ~ ("^" source_dir "/") {
            print path
            path=""
        }
    '
}

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
        print_info "Skipping existing file: ${SOURCE_DIR}/${rel_path}"
        return 0
    fi

    mkdir -p "$(dirname "$dest_path")"
    if curl -fsSL "${RAW_BASE}/${SOURCE_DIR}/${encoded_path}" -o "$dest_path"; then
        print_success "Downloaded: ${SOURCE_DIR}/${rel_path}"
    else
        print_warning "Failed to download: ${SOURCE_DIR}/${rel_path}"
    fi
}

download_hermes_config() {
    local source_files
    local full_path
    local rel_path
    local dest_path

    print_section "DOWNLOAD HERMESCONFIG"
    print_info "Source: ${SOURCE_DIR}"
    print_info "Destination: ${DEST_DIR}"

    source_files=$(list_source_files)

    if [[ -z "$source_files" ]]; then
        print_warning "No files found under ${SOURCE_DIR}/ in the repository"
        return 0
    fi

    while IFS= read -r full_path; do
        rel_path="${full_path#${SOURCE_DIR}/}"
        dest_path="${DEST_DIR}/${rel_path}"
        download_file "$rel_path" "$dest_path"
    done <<< "$source_files"
}

main() {
    require_root
    require_tools
    mkdir -p "$DEST_DIR"

    fetch_file_list
    download_hermes_config

    print_section "COMPLETE"
    print_success "Hermes config downloaded to ${DEST_DIR}"
}

main "$@"
