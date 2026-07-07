#!/usr/bin/env bash
#
# transfer_hermes.sh
#
# Moves a Hermes docker-compose stack (config + bind-mounted data) from this
# machine to a remote machine over SSH. Assumes bind mounts (not named
# Docker volumes) — see the "Does Hermes use bind mounts" assumption this
# script was built around.
#
# Usage:
#   ./transfer_hermes.sh [--dry-run]
#
#   --dry-run   Show what would happen (including an rsync preview of files
#               that would be transferred) without stopping any containers,
#               dumping any database, or copying/starting anything for real.
#
# Configure the variables below before running, or export them as
# environment variables before calling the script.

set -euo pipefail

DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        --dry-run)
            DRY_RUN=true
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: $0 [--dry-run]" >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# CONFIGURATION - edit these before running
# ---------------------------------------------------------------------------

# Local path to the Hermes compose stack directory (contains docker-compose.yml
# plus bind-mounted folders like ./data, ./config, etc.)
LOCAL_STACK_DIR="${LOCAL_STACK_DIR:-/opt/dockge/stacks/hermes}"

# Remote connection details
REMOTE_USER="${REMOTE_USER:-joseph}"
REMOTE_HOST="${REMOTE_HOST:-192.168.1.1X}"
REMOTE_STACK_DIR="${REMOTE_STACK_DIR:-/opt/dockge/stacks/hermes}"

# Optional: path to a specific SSH key
SSH_KEY="${SSH_KEY:-}"

# Compose file name (change if yours isn't the default)
COMPOSE_FILE="${COMPOSE_FILE:-compose.yml}"

# ---------------------------------------------------------------------------
# Prompt for remote host at startup.
read -rp "Remote host IP/hostname [${REMOTE_HOST}]: " INPUT_REMOTE_HOST
REMOTE_HOST="${INPUT_REMOTE_HOST:-$REMOTE_HOST}"

# Internal setup
# ---------------------------------------------------------------------------

SSH_OPTS=()
if [[ -n "$SSH_KEY" ]]; then
    SSH_OPTS+=(-i "$SSH_KEY")
fi

ssh_cmd() {
    ssh "${SSH_OPTS[@]}" "${REMOTE_USER}@${REMOTE_HOST}" "$@"
}

rsync_cmd() {
    local rsync_flags=(-avz --progress)
    if [[ "$DRY_RUN" == true ]]; then
        rsync_flags+=(--dry-run)
    fi
    if [[ -n "$SSH_KEY" ]]; then
        rsync "${rsync_flags[@]}" -e "ssh -i $SSH_KEY" "$@"
    else
        rsync "${rsync_flags[@]}" "$@"
    fi
}

log()  { echo -e "\033[1;34m[*]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[OK]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
err()  { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

if [[ "$DRY_RUN" == true ]]; then
    warn "DRY RUN MODE: no containers will be stopped/started, no database"
    warn "will be dumped, and no files will actually be copied. This only"
    warn "previews what rsync would transfer."
fi

# ---------------------------------------------------------------------------
# 1. Pre-flight checks
# ---------------------------------------------------------------------------

log "Checking local stack directory..."
if [[ ! -d "$LOCAL_STACK_DIR" ]]; then
    err "Local stack directory not found: $LOCAL_STACK_DIR"
    exit 1
fi

if [[ ! -f "$LOCAL_STACK_DIR/$COMPOSE_FILE" ]]; then
    err "Compose file not found: $LOCAL_STACK_DIR/$COMPOSE_FILE"
    exit 1
fi
ok "Found stack at $LOCAL_STACK_DIR"

log "Checking SSH connectivity to $REMOTE_HOST..."
if ! ssh_cmd "echo connected" &>/dev/null; then
    err "Could not SSH to ${REMOTE_USER}@${REMOTE_HOST}. Check host, user, and SSH key."
    exit 1
fi
ok "SSH connection works"

log "Checking Docker is available on remote host..."
if ! ssh_cmd "command -v docker" &>/dev/null; then
    err "Docker not found on remote host. Install Docker there first."
    exit 1
fi
if ! ssh_cmd "docker compose version" &>/dev/null; then
    err "docker compose (v2 plugin) not found on remote host."
    exit 1
fi
ok "Docker and Docker Compose available on remote host"

# ---------------------------------------------------------------------------
# 2. Detect a database container in the compose file
# ---------------------------------------------------------------------------

log "Scanning compose file for known database images..."
DB_DETECTED=""
if grep -qiE "image:\s*(postgres|postgis)" "$LOCAL_STACK_DIR/$COMPOSE_FILE"; then
    DB_DETECTED="postgres"
elif grep -qiE "image:\s*(mysql|mariadb)" "$LOCAL_STACK_DIR/$COMPOSE_FILE"; then
    DB_DETECTED="mysql"
fi

if [[ -n "$DB_DETECTED" ]] && [[ "$DRY_RUN" == false ]]; then
    warn "Detected a $DB_DETECTED database container in the stack."
    warn "Raw bind-mount copies of DB files usually work fine if the DB is"
    warn "stopped cleanly first (which this script does), but a logical"
    warn "dump is a good extra safety net."
    read -rp "Take a database dump before transfer as a backup? [y/N] " DO_DUMP
    if [[ "$DO_DUMP" =~ ^[Yy]$ ]]; then
        DUMP_DIR="$LOCAL_STACK_DIR/pre_transfer_dump"
        mkdir -p "$DUMP_DIR"
        DB_SERVICE=$(grep -B5 -iE "image:\s*(postgres|postgis|mysql|mariadb)" \
            "$LOCAL_STACK_DIR/$COMPOSE_FILE" | grep -E "^\s{2}[a-zA-Z0-9_-]+:" \
            | tail -1 | tr -d ' :')
        read -rp "Confirm the database service name in compose [$DB_SERVICE]: " CONFIRM_SVC
        DB_SERVICE="${CONFIRM_SVC:-$DB_SERVICE}"

        if [[ "$DB_DETECTED" == "postgres" ]]; then
            read -rp "Postgres username: " PG_USER
            read -rp "Database name: " PG_DB
            (cd "$LOCAL_STACK_DIR" && docker compose exec -T "$DB_SERVICE" \
                pg_dump -U "$PG_USER" "$PG_DB") > "$DUMP_DIR/db_dump.sql"
        else
            read -rp "MySQL/MariaDB username: " MY_USER
            read -rsp "MySQL/MariaDB password: " MY_PASS
            echo
            read -rp "Database name: " MY_DB
            (cd "$LOCAL_STACK_DIR" && docker compose exec -T "$DB_SERVICE" \
                mysqldump -u "$MY_USER" -p"$MY_PASS" "$MY_DB") > "$DUMP_DIR/db_dump.sql"
        fi
        ok "Database dump saved to $DUMP_DIR/db_dump.sql (will be transferred with the rest)"
    fi
elif [[ -n "$DB_DETECTED" ]]; then
    log "Dry run — skipping database dump prompt (detected: $DB_DETECTED)."
else
    log "No known database image detected — assuming SQLite/flat-file storage, no dump needed."
fi

# ---------------------------------------------------------------------------
# 3. Stop the stack locally
# ---------------------------------------------------------------------------

if [[ "$DRY_RUN" == true ]]; then
    log "Dry run — not stopping the local stack (leaving it running)."
else
    log "Stopping Hermes stack on this machine..."
    (cd "$LOCAL_STACK_DIR" && docker compose down)
    ok "Stack stopped"
fi

# ---------------------------------------------------------------------------
# 4. Transfer files via rsync
# ---------------------------------------------------------------------------

if [[ "$DRY_RUN" == false ]]; then
    log "Creating remote directory (if needed)..."
    ssh_cmd "mkdir -p '$REMOTE_STACK_DIR'"
fi

if [[ "$DRY_RUN" == true ]]; then
    log "Dry run — previewing what would be transferred to ${REMOTE_HOST}:${REMOTE_STACK_DIR} ..."
else
    log "Transferring stack to ${REMOTE_HOST}:${REMOTE_STACK_DIR} ..."
fi
rsync_cmd \
    --exclude '.git' \
    "$LOCAL_STACK_DIR"/ "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_STACK_DIR}/"

if [[ "$DRY_RUN" == true ]]; then
    ok "Dry run preview complete — no files were actually copied."
    echo
    echo "Re-run without --dry-run to perform the real migration."
    exit 0
fi
ok "Transfer complete"

# ---------------------------------------------------------------------------
# 5. Start the stack on the remote machine
# ---------------------------------------------------------------------------

log "Starting Hermes stack on remote host..."
ssh_cmd "cd '$REMOTE_STACK_DIR' && docker compose up -d"
ok "Stack started on remote host"

# ---------------------------------------------------------------------------
# 6. Verify
# ---------------------------------------------------------------------------

log "Checking container status on remote host..."
sleep 5
ssh_cmd "cd '$REMOTE_STACK_DIR' && docker compose ps"

echo
ok "Migration complete."
echo "Verify Hermes is working correctly on ${REMOTE_HOST} before deleting"
echo "the original data at: $LOCAL_STACK_DIR"
echo
echo "The source stack has been left stopped (not deleted) as a safety net."