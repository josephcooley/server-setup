#!/bin/bash
################################################################################
# Standalone downloader for stack folders in this repository
# Downloads selected files from hermesstacks/ and/or mediastacks/ into /opt/stacks
# Hermes stacks include the Dockhand compose file under hermesstacks/dockhand/.
#
# Usage: sudo bash install-stacks.sh
################################################################################

set -euo pipefail

REPO="josephcooley/server-setup"
BRANCH="main"
DEST_DIR="/opt/stacks"
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

print_subsection() {
    echo -e "${BLUE}→ $1${NC}"
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

require_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

require_tools() {
    if ! command -v curl &>/dev/null; then
        print_error "curl is required but not installed"
        exit 1
    fi

    if ! command -v python3 &>/dev/null; then
        print_error "python3 is required but not installed"
        exit 1
    fi
}

choose_sources() {
    local choice

    print_section "STACK SELECTION"
    echo "Choose which stack folder(s) to download into ${DEST_DIR}:"
    echo "  1) hermesstacks (includes Dockhand)"
    echo "  2) mediastacks"
    echo "  3) both"
    echo ""

    while true; do
        read -r -p "Enter selection [1-3]: " choice
        case "$choice" in
            1)
                SELECTED_SOURCES=("hermesstacks")
                return 0
                ;;
            2)
                SELECTED_SOURCES=("mediastacks")
                return 0
                ;;
            3)
                SELECTED_SOURCES=("hermesstacks" "mediastacks")
                return 0
                ;;
            *)
                print_warning "Invalid choice. Enter 1, 2, or 3."
                ;;
        esac
    done
}

choose_file_behavior() {
    local choice

    print_section "FILE HANDLING"
    echo "Choose how to handle files that already exist in ${DEST_DIR}:"
    echo "  1) Only download new files (skip existing)"
    echo "  2) Overwrite existing files"
    echo ""

    while true; do
        read -r -p "Enter selection [1-2]: " choice
        case "$choice" in
            1)
                OVERWRITE_EXISTING=false
                print_info "Mode selected: only download new files"
                return 0
                ;;
            2)
                OVERWRITE_EXISTING=true
                print_info "Mode selected: overwrite existing files"
                return 0
                ;;
            *)
                print_warning "Invalid choice. Enter 1 or 2."
                ;;
        esac
    done
}

fetch_file_list() {
    print_subsection "Fetching file list from GitHub API"
    API_RESPONSE=$(curl -fsSL "$TREE_API")
    if [[ -z "$API_RESPONSE" ]]; then
        print_error "Failed to reach GitHub API"
        exit 1
    fi
}

list_source_files() {
    local source_dir="$1"
    echo "$API_RESPONSE" | awk -v source_dir="$source_dir" '
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

download_repo_subtree() {
    local source_dir="$1"
    local destination_root="$2"
    local source_files
    local full_path
    local rel_path
    local dest_path

    print_section "DOWNLOAD ${source_dir^^} FROM GITHUB"
    print_subsection "Downloading ${source_dir} into ${destination_root}"

    source_files=$(list_source_files "$source_dir")

    if [[ -z "$source_files" ]]; then
        print_warning "No files found under ${source_dir}/ in the repository"
        return 0
    fi

    while IFS= read -r full_path; do
        rel_path="${full_path#${source_dir}/}"
        dest_path="${destination_root}/${rel_path}"
        download_file "$source_dir" "$rel_path" "$dest_path"
    done <<< "$source_files"
}

download_file() {
    local source_dir="$1"
    local rel_path="$2"
    local dest_path="$3"
    local encoded_path

    encoded_path=$(python3 - "$rel_path" <<'PY'
import sys
from urllib.parse import quote
print(quote(sys.argv[1]))
PY
)

    if [[ -e "$dest_path" ]]; then
        if [[ "${OVERWRITE_EXISTING:-false}" != "true" ]]; then
            print_info "Skipping existing file: ${source_dir}/${rel_path}"
            return 0
        fi

        print_info "Overwriting existing file: ${source_dir}/${rel_path}"
    fi

    mkdir -p "$(dirname "$dest_path")"
    if curl -fsSL "https://raw.githubusercontent.com/${REPO}/${BRANCH}/${source_dir}/${encoded_path}" -o "$dest_path"; then
        print_success "Downloaded: ${source_dir}/${rel_path}"
    else
        print_warning "Failed to download: ${source_dir}/${rel_path}"
    fi
}

download_source() {
    local source_dir="$1"
    download_repo_subtree "$source_dir" "$DEST_DIR"
}

main() {
    require_root
    require_tools
    mkdir -p "$DEST_DIR"

    choose_sources
    choose_file_behavior
    fetch_file_list

    for source in "${SELECTED_SOURCES[@]}"; do
        download_source "$source"
    done

    print_section "COMPLETE"
    print_success "Selected stack files downloaded to ${DEST_DIR}"
}

main "$@"
