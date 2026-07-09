#!/bin/bash
################################################################################
# Post-install / post-start tasks for stacks in /opt/stacks
#
# Step 1: Configure Hermes dashboard basic auth
# - Prompts for dashboard password (hidden input)
# - Generates password hash inside the running hermes-agent container
# - Prepends dashboard block to /opt/stacks/hermes/agent/config.yaml
################################################################################

set -euo pipefail

CONFIG_FILE="/opt/stacks/hermes/agent/config.yaml"
CONTAINER_NAME="hermes-agent"
DASHBOARD_USERNAME="joseph"
MANIFEST_ENV_FILE="/opt/stacks/manifest/.env"
SURE_ENV_FILE="/opt/stacks/sure/.env"

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
	if ! command -v docker >/dev/null 2>&1; then
		print_error "docker is required but not installed"
		exit 1
	fi

	if ! command -v openssl >/dev/null 2>&1; then
		print_error "openssl is required but not installed"
		exit 1
	fi

	if ! command -v mktemp >/dev/null 2>&1; then
		print_error "mktemp is required but not installed"
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

ensure_env_file() {
	local env_file="$1"

	if [[ ! -f "$env_file" ]]; then
		print_error "Env file not found: $env_file"
		exit 1
	fi
}

maybe_overwrite_key() {
	local env_file="$1"
	local env_key="$2"
	local existing_value
	local answer

	existing_value="$(grep -E "^${env_key}=" "$env_file" | head -n1 | cut -d'=' -f2-)"

	if [[ -n "$existing_value" ]]; then
		while true; do
			read -r -p "${env_key} is already set in ${env_file}. Overwrite? [y/N]: " answer
			case "$answer" in
				y|Y|yes|YES)
					return 0
					;;
				n|N|no|NO|"")
					print_warning "Skipping ${env_key} in ${env_file}"
					return 1
					;;
				*)
					print_warning "Please answer y or n"
					;;
			esac
		done
	fi

	return 0
}

generate_random_hex_key() {
	openssl rand -hex 32
}

set_env_key_value() {
	local env_file="$1"
	local env_key="$2"
	local env_value="$3"

	if grep -qE "^${env_key}=" "$env_file"; then
		sed -i "s|^${env_key}=.*|${env_key}=${env_value}|" "$env_file"
	else
		printf '\n%s=%s\n' "$env_key" "$env_value" >> "$env_file"
	fi
}

update_env_secret() {
	local env_file="$1"
	local env_key="$2"
	local backup_file
	local new_key

	ensure_env_file "$env_file"

	if ! maybe_overwrite_key "$env_file" "$env_key"; then
		return 0
	fi

	backup_file="${env_file}.bak.$(date +%Y%m%d%H%M%S)"
	cp "$env_file" "$backup_file"

	new_key="$(generate_random_hex_key)"
	set_env_key_value "$env_file" "$env_key" "$new_key"

	print_success "Updated ${env_key} in ${env_file}"
	print_success "Backup created: ${backup_file}"
}

step_2_generate_env_keys() {
	print_section "STEP 2: Generate and Populate .env Keys"

	update_env_secret "$MANIFEST_ENV_FILE" "BETTER_AUTH_SECRET"
	update_env_secret "$SURE_ENV_FILE" "SECRET_KEY_BASE"
}

main() {
	require_root
	require_tools

	step_1_setup_hermes_dashboard
	step_2_generate_env_keys

	print_section "COMPLETE"
	print_success "Step 1 and Step 2 finished"
	print_success "You can add more post-start steps in this script next"
}

main "$@"
