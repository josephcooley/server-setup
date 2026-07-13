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
HERMES_DEST_DIR="/opt/stacks/hermes/agent"
CONTAINER_NAME="hermes-agent"
DASHBOARD_USERNAME="joseph"
REPO="josephcooley/server-setup"
BRANCH="main"
HERMESCONFIG_SOURCE_DIR="hermesconfig"
ARCHIVE_URL="https://codeload.github.com/${REPO}/tar.gz/refs/heads/${BRANCH}"

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

	if ! command -v docker >/dev/null 2>&1; then
		print_error "docker is required but not installed"
		exit 1
	fi

	if ! command -v mktemp >/dev/null 2>&1; then
		print_error "mktemp is required but not installed"
		exit 1
	fi

	if ! command -v tar >/dev/null 2>&1; then
		print_error "tar is required but not installed"
		exit 1
	fi
}

print_subsection() {
	echo -e "${BLUE}→ $1${NC}"
}

prompt_for_step2_download_choice() {
	local response

	while true; do
		read -rp "Download hermesconfig folder from GitHub now? [Y/n]: " response
		response="${response:-Y}"

		case "$response" in
			Y|y|yes|YES)
				RUN_STEP2_DOWNLOAD=true
				return 0
				;;
			N|n|no|NO)
				RUN_STEP2_DOWNLOAD=false
				return 0
				;;
			*)
				print_warning "Please answer Y or N"
				;;
		esac
	done
}

step_2_download_hermesconfig() {
	local archive_file
	local extract_dir
	local repo_root
	local source_dir
	local source_file
	local rel_path
	local dest_path
	local downloaded_any=false
	local failed_count=0

	archive_file="$(mktemp)"
	extract_dir="$(mktemp -d)"

	cleanup_step2_temp() {
		rm -f "$archive_file"
		rm -rf "$extract_dir"
	}

	print_section "STEP 2: Download hermesconfig Files"
	print_subsection "Source: ${REPO}/${HERMESCONFIG_SOURCE_DIR} (branch: ${BRANCH}, archive mode)"
	print_subsection "Destination: $HERMES_DEST_DIR"
	mkdir -p "$HERMES_DEST_DIR"

	if ! curl -fsSL "$ARCHIVE_URL" -o "$archive_file"; then
		print_error "Failed to download repository archive: $ARCHIVE_URL"
		print_warning "Check internet access, repo/branch values, and GitHub availability"
		cleanup_step2_temp
		exit 1
	fi

	if ! tar -xzf "$archive_file" -C "$extract_dir"; then
		print_error "Failed to extract repository archive"
		cleanup_step2_temp
		exit 1
	fi

	repo_root="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
	source_dir="$repo_root/$HERMESCONFIG_SOURCE_DIR"
	if [[ -z "$repo_root" || ! -d "$source_dir" ]]; then
		print_error "Could not locate ${HERMESCONFIG_SOURCE_DIR}/ in downloaded archive"
		cleanup_step2_temp
		exit 1
	fi

	while IFS= read -r -d '' source_file; do
		[[ -z "$source_file" ]] && continue
		rel_path="${source_file#${source_dir}/}"
		dest_path="${HERMES_DEST_DIR}/${rel_path}"

		if [[ -e "$dest_path" ]]; then
			print_info "Overwriting existing file: ${rel_path}"
		fi

		mkdir -p "$(dirname "$dest_path")"
		if cp -f "$source_file" "$dest_path"; then
			print_success "Downloaded: ${rel_path}"
			downloaded_any=true
		else
			print_warning "Failed to download: ${rel_path}"
			failed_count=$((failed_count + 1))
		fi
	done < <(find "$source_dir" -type f -print0)

	if [[ "$downloaded_any" != "true" ]]; then
		print_error "No files were downloaded from ${HERMESCONFIG_SOURCE_DIR}/"
		cleanup_step2_temp
		exit 1
	fi

	if (( failed_count > 0 )); then
		print_warning "Completed with ${failed_count} file download warning(s)"
	fi

	cleanup_step2_temp
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
	local stripped_file

	stripped_file="$(mktemp)"

	if grep -q '^dashboard:' "$CONFIG_FILE"; then
		print_info "Existing dashboard block found; replacing it with new values"
		awk '
			BEGIN { skip = 0 }
			{
				if (skip == 0 && $0 ~ /^dashboard:[[:space:]]*$/) {
					skip = 1
					next
				}

				if (skip == 1) {
					if ($0 ~ /^[^[:space:]#][^:]*:[[:space:]]*($|#.*$)/) {
						skip = 0
					} else {
						next
					}
				}

				print
			}
		' "$CONFIG_FILE" > "$stripped_file"
	else
		cp "$CONFIG_FILE" "$stripped_file"
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
		cat "$stripped_file"
	} > "$tmp_file"

	mv "$tmp_file" "$CONFIG_FILE"
	rm -f "$stripped_file"

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
	prompt_for_step2_download_choice

	if [[ "$RUN_STEP2_DOWNLOAD" == "true" ]]; then
		step_2_download_hermesconfig
	else
		print_section "STEP 2: Skipped"
		print_warning "Skipping hermesconfig download by user choice"
	fi

	print_section "COMPLETE"
	print_success "Step 1 and Step 2 finished"
}

main "$@"
