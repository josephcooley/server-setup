#!/bin/bash
################################################################################
# Post-install / post-start tasks for stacks in /opt/stacks
#
# Step 1: Configure Hermes dashboard basic auth
# - Prompts for dashboard password (hidden input)
# - Generates password hash inside the running hermes-agent container
# - Prepends dashboard block to /opt/stacks/hermes/agent/config.yaml
#
# Step 2: Download non-.env and non-compose.yaml stack files
# - Prompts for hermesstacks, mediastacks, or both
# - Downloads all other files into /opt/stacks and always overwrites existing files
################################################################################

set -euo pipefail

CONFIG_FILE="/opt/stacks/hermes/agent/config.yaml"
CONTAINER_NAME="hermes-agent"
DASHBOARD_USERNAME="joseph"
REPO="josephcooley/server-setup"
BRANCH="main"
STACKS_DEST_DIR="/opt/stacks"
TREE_API="https://api.github.com/repos/${REPO}/git/trees/${BRANCH}?recursive=1"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

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

	if ! command -v docker >/dev/null 2>&1; then
		print_error "docker is required but not installed"
		exit 1
	fi

	if ! command -v mktemp >/dev/null 2>&1; then
		print_error "mktemp is required but not installed"
		exit 1
	fi
}

fetch_repo_file_list() {
	print_subsection "Fetching file list from GitHub API"
	API_RESPONSE=$(curl -fsSL "$TREE_API")
	if [[ -z "$API_RESPONSE" ]]; then
		print_error "Failed to reach GitHub API"
		exit 1
	fi
}

print_subsection() {
	echo -e "${BLUE}→ $1${NC}"
}

choose_stack_sources() {
	local choice

	print_section "STEP 2: Stack File Selection"
	echo "Choose which stack folder(s) to sync into ${STACKS_DEST_DIR}:"
	echo "  1) hermesstacks"
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

is_overlay_target_file() {
	local rel_path="$1"

	case "$rel_path" in
		compose.yaml|*/compose.yaml|.env|*/.env)
			return 1
			;;
		*)
			return 0
			;;
	esac
}

download_overlay_file() {
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
		print_info "Overwriting existing file: ${source_dir}/${rel_path}"
	fi

	mkdir -p "$(dirname "$dest_path")"
	if curl -fsSL "${RAW_BASE}/${source_dir}/${encoded_path}" -o "$dest_path"; then
		print_success "Downloaded: ${source_dir}/${rel_path}"
	else
		print_warning "Failed to download: ${source_dir}/${rel_path}"
	fi
}

step_2_download_stack_overlays() {
	local source_dir
	local source_files
	local full_path
	local rel_path
	local dest_path
	local downloaded_any=false

	choose_stack_sources
	fetch_repo_file_list

	for source_dir in "${SELECTED_SOURCES[@]}"; do
		print_section "STEP 2: Sync Non-.env/Non-compose Files (${source_dir})"
		print_subsection "Source: ${source_dir}"
		print_subsection "Destination: ${STACKS_DEST_DIR}"

		source_files=$(list_source_files "$source_dir")
		if [[ -z "$source_files" ]]; then
			print_warning "No files found under ${source_dir}/ in the repository"
			continue
		fi

		while IFS= read -r full_path; do
			rel_path="${full_path#${source_dir}/}"

			if ! is_overlay_target_file "$rel_path"; then
				continue
			fi

			dest_path="${STACKS_DEST_DIR}/${rel_path}"
			download_overlay_file "$source_dir" "$rel_path" "$dest_path"
			downloaded_any=true
		done <<< "$source_files"
	done

	if [[ "$downloaded_any" != "true" ]]; then
		print_warning "No non-.env/non-compose.yaml files matched for selected source(s)"
	fi
}

ensure_container_running() {
	if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
		print_error "Container '$CONTAINER_NAME' is not running"
		print_warning "Start your compose stacks first, then rerun this script"
		exit 1
	fi
}

ensure_config_file() {
	if [[ ! -f "$CONFIG_FILE" ]]; then
		print_error "Config file not found: $CONFIG_FILE"
		exit 1
	fi
}

prompt_for_password() {
	local pass1
	local pass2

	while true; do
		read -rsp "Enter Hermes dashboard password: " pass1
		echo ""
		read -rsp "Confirm Hermes dashboard password: " pass2
		echo ""

		if [[ -z "$pass1" ]]; then
			print_warning "Password cannot be empty"
			continue
		fi

		if [[ "$pass1" != "$pass2" ]]; then
			print_warning "Passwords do not match. Try again."
			continue
		fi

		DASHBOARD_PASSWORD="$pass1"
		break
	done
}

generate_password_hash() {
	PASS_HASH="$(printf '%s' "$DASHBOARD_PASSWORD" | docker exec -i "$CONTAINER_NAME" python -c "import sys; from plugins.dashboard_auth.basic import hash_password; print(hash_password(sys.stdin.read()))")"

	if [[ -z "$PASS_HASH" ]]; then
		print_error "Failed to generate dashboard password hash"
		exit 1
	fi
}

prepend_dashboard_block() {
	local backup_file
	local tmp_file

	if grep -q '^dashboard:' "$CONFIG_FILE"; then
		print_warning "A dashboard block already exists in $CONFIG_FILE"
		print_warning "Skipping insertion to avoid duplicate config"
		return 0
	fi

	backup_file="${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
	cp "$CONFIG_FILE" "$backup_file"

	tmp_file="$(mktemp)"

	{
		printf 'dashboard:\n'
		printf '  bind: 0.0.0.0\n'
		printf '  basic_auth:\n'
		printf '    username: %s\n' "$DASHBOARD_USERNAME"
		printf '    password_hash: "%s"\n\n' "$PASS_HASH"
		cat "$CONFIG_FILE"
	} > "$tmp_file"

	mv "$tmp_file" "$CONFIG_FILE"

	print_success "Dashboard config inserted at top of $CONFIG_FILE"
	print_success "Backup created: $backup_file"
}

step_1_setup_hermes_dashboard() {
	print_section "STEP 1: Hermes Dashboard Setup"

	ensure_container_running
	ensure_config_file
	prompt_for_password
	generate_password_hash
	prepend_dashboard_block
}

main() {
	require_root
	require_tools

	step_1_setup_hermes_dashboard
	step_2_download_stack_overlays

	print_section "COMPLETE"
	print_success "Step 1 and Step 2 finished"
	print_success "You can add more post-start steps in this script next"
}

main "$@"
