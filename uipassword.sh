#!/usr/bin/env bash
set -euo pipefail

PRIMARY_CONFIG_FILE="/opt/stacks/hermes/agent/config.yaml"
CONTAINER_NAME="hermes-agent"
USERNAME="joseph"

info() {
	printf '[INFO] %s\n' "$1"
}

warn() {
	printf '[WARN] %s\n' "$1"
}

error() {
	printf '[ERROR] %s\n' "$1" >&2
}

require_command() {
	local cmd="$1"
	if ! command -v "$cmd" >/dev/null 2>&1; then
		error "Required command not found: $cmd"
		exit 1
	fi
}

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
	error "This script must be run as root (sudo)."
	exit 1
fi

require_command docker
require_command mktemp
require_command date
require_command cp
require_command mv
require_command grep
require_command stat

if ! docker ps --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
	error "Container '$CONTAINER_NAME' is not running."
	exit 1
fi

if [[ -f "$PRIMARY_CONFIG_FILE" ]]; then
	CONFIG_FILE="$PRIMARY_CONFIG_FILE"
else
	error "Target config file not found: $PRIMARY_CONFIG_FILE"
	exit 1
fi

if grep -Eq '^[[:space:]]*dashboard:[[:space:]]*$' "$CONFIG_FILE"; then
	warn "'dashboard:' already exists in $CONFIG_FILE. No changes made."
	exit 0
fi

password=''
confirm=''
while true; do
	read -rsp 'Enter dashboard password: ' password
	printf '\n'
	read -rsp 'Confirm dashboard password: ' confirm
	printf '\n'

	if [[ -z "$password" ]]; then
		warn 'Password cannot be empty. Please try again.'
		continue
	fi

	if [[ "$password" != "$confirm" ]]; then
		warn 'Passwords do not match. Please try again.'
		continue
	fi

	break
done

# Hash the password inside the running container without exposing it in logs.
password_hash="$(
	docker exec -i "$CONTAINER_NAME" python3 -c "from plugins.dashboard_auth.basic import hash_password; import sys; print(hash_password(sys.stdin.read().rstrip('\\n')))" <<<"$password"
)"

unset password
unset confirm

if [[ -z "$password_hash" ]]; then
	error 'Failed to generate password hash.'
	exit 1
fi

timestamp="$(date +%Y%m%d%H%M%S)"
backup_file="${CONFIG_FILE}.bak.${timestamp}"
cp -a "$CONFIG_FILE" "$backup_file"
info "Backup created: $backup_file"

config_dir="$(dirname "$CONFIG_FILE")"
tmp_file="$(mktemp "${config_dir}/config.yaml.tmp.XXXXXX")"

orig_owner_group="$(stat -c '%u:%g' "$CONFIG_FILE")"
orig_mode="$(stat -c '%a' "$CONFIG_FILE")"

cleanup() {
	if [[ -n "${tmp_file:-}" && -f "$tmp_file" ]]; then
		rm -f "$tmp_file"
	fi
}
trap cleanup EXIT

{
	printf '%s\n' 'dashboard:'
	printf '%s\n' '  bind: 0.0.0.0'
	printf '%s\n' '  basic_auth:'
	printf '%s\n' "    username: $USERNAME"
	printf '%s\n' "    password_hash: \"$password_hash\""
	printf '\n'
} >"$tmp_file"

cat "$CONFIG_FILE" >>"$tmp_file"
chown "$orig_owner_group" "$tmp_file"
chmod "$orig_mode" "$tmp_file"
mv -f "$tmp_file" "$CONFIG_FILE"

trap - EXIT

info "Dashboard basic auth added successfully to $CONFIG_FILE"

if docker restart "$CONTAINER_NAME" >/dev/null; then
	info "Hermes restarted successfully ($CONTAINER_NAME)."
else
	error "Config updated, but failed to restart Hermes ($CONTAINER_NAME)."
	exit 1
fi
