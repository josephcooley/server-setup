#!/bin/bash
################################################################################
# Post-install / post-start tasks for stacks in /opt/stacks
#
# Step 1: Configure Hermes dashboard basic auth
# - Prompts for dashboard password (hidden input)
# - Generates password hash inside the running hermes-agent container
# - Prepends dashboard block to /opt/stacks/hermes/agent/config.yaml
#
# Step 2: Download hermesconfig files from GitHub
# - Downloads files from the repo's hermesconfig/ folder into /opt/stacks/hermes/
# - Overwrites existing files
################################################################################

set -euo pipefail

CONFIG_FILE="/opt/stacks/hermes/agent/config.yaml"
HERMES_DEST_DIR="/opt/stacks/hermes"
CONTAINER_NAME="hermes-agent"
DASHBOARD_USERNAME="joseph"
REPO="josephcooley/server-setup"
BRANCH="main"
HERMESCONFIG_SOURCE_DIR="hermesconfig"
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

print_subsection() {
	echo -e "${BLUE}→ $1${NC}"
}

fetch_hermesconfig_file_list() {
	curl -fsSL "$TREE_API" | python3 - "$HERMESCONFIG_SOURCE_DIR" <<'PY'
import json
import sys

source_dir = sys.argv[1].rstrip('/') + '/'
data = json.load(sys.stdin)

for node in data.get("tree", []):
    path = node.get("path", "")
    if node.get("type") == "blob" and path.startswith(source_dir):
        print(path)
PY
}

url_encode_path() {
	python3 - "$1" <<'PY'
import sys
from urllib.parse import quote

print(quote(sys.argv[1]))
PY
}

step_2_download_hermesconfig() {
	local full_path
	local rel_path
	local dest_path
	local encoded_path
	local downloaded_any=false

	print_section "STEP 2: Download hermesconfig Files"
	print_subsection "Source: ${REPO}/${HERMESCONFIG_SOURCE_DIR} (branch: ${BRANCH})"
	print_subsection "Destination: $HERMES_DEST_DIR"
	mkdir -p "$HERMES_DEST_DIR"

	while IFS= read -r full_path; do
		[[ -z "$full_path" ]] && continue
		rel_path="${full_path#${HERMESCONFIG_SOURCE_DIR}/}"
		dest_path="${HERMES_DEST_DIR}/${rel_path}"
		encoded_path="$(url_encode_path "$full_path")"

		if [[ -e "$dest_path" ]]; then
			print_info "Overwriting existing file: ${rel_path}"
		fi

		mkdir -p "$(dirname "$dest_path")"
		if curl -fsSL "${RAW_BASE}/${encoded_path}" -o "$dest_path"; then
			print_success "Downloaded: ${rel_path}"
			downloaded_any=true
		else
			print_warning "Failed to download: ${rel_path}"
		fi
	done < <(fetch_hermesconfig_file_list)

	if [[ "$downloaded_any" != "true" ]]; then
		print_error "No files were downloaded from ${HERMESCONFIG_SOURCE_DIR}/"
		exit 1
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
	step_2_download_hermesconfig

	print_section "COMPLETE"
	print_success "Step 1 and Step 2 finished"
}

main "$@"
