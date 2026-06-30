#!/bin/bash
################################################################################
# Dockge Server Setup Script
# Automates Ubuntu server configuration with Docker and Dockge setup
# Author: Joseph M. Cooley
################################################################################

set -e

# ====================================================================
# CONFIGURATION (edit these before running)
# ====================================================================

DOCKGE_PORT="5001"
DOCKGE_DIR="/opt/dockge"
STACKS_DIR="/opt/dockge/stacks"

TARGET_USER="${SUDO_USER:-${USER:-root}}"
TARGET_GROUP="$(id -gn "$TARGET_USER")"

# ====================================================================
# COLOR CODES & OUTPUT FUNCTIONS
# ====================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# ====================================================================
# PRE-FLIGHT CHECKS
# ====================================================================

print_section "PRE-FLIGHT CHECKS"

if [[ $EUID -ne 0 ]]; then
  print_error "This script must be run as root (use sudo)"
  exit 1
fi

print_success "Running with root privileges"

PRIMARY_IP=$(hostname -I | awk '{print $1}')
print_success "Primary IP: $PRIMARY_IP"

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  DOCKGE SETUP${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "This script will set up:"
echo "  1. System updates"
echo "  2. Docker & Docker Compose"
echo "  3. Dockge"
echo "  4. Dockge stacks from GitHub"
echo ""

# ====================================================================
# STEP 1: SYSTEM UPDATE
# ====================================================================

print_section "STEP 1: SYSTEM UPDATE"

print_subsection "Updating package lists and upgrading system"
apt update
apt upgrade -y
apt autoremove -y
apt autoclean -y

timedatectl set-timezone America/Los_Angeles #set timezone for los angeles

print_success "System packages updated"

# ====================================================================
# STEP 2: DOCKER & DOCKER COMPOSE INSTALLATION
# ====================================================================

print_section "STEP 2: DOCKER & DOCKER COMPOSE INSTALLATION"

print_subsection "Installing Docker prerequisites"
apt install ca-certificates curl gnupg -y
print_success "Prerequisites installed"

print_subsection "Adding Docker GPG key and repository"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

print_success "Docker repository configured"

print_subsection "Installing Docker packages"
apt update
apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

print_subsection "Enabling Docker service"
systemctl enable --now docker

print_success "Docker installed and enabled"

if docker --version &>/dev/null; then
  DOCKER_VERSION=$(docker --version)
  print_success "$DOCKER_VERSION"
else
  print_warning "Could not verify Docker installation"
fi

# ====================================================================
# STEP 3: DOCKGE SETUP
# ====================================================================

print_section "STEP 3: DOCKGE SETUP"

print_subsection "Creating Dockge directories"
mkdir -p "$DOCKGE_DIR"
mkdir -p "$STACKS_DIR"
chown -R "$TARGET_USER:$TARGET_GROUP" "$DOCKGE_DIR"
print_success "Directories created: $DOCKGE_DIR, $STACKS_DIR"

print_subsection "Creating docker-compose.yml for Dockge"
cat > "$DOCKGE_DIR/docker-compose.yml" << EOF
services:
  dockge:
    image: louislam/dockge:latest
    container_name: dockge
    ports:
      - "${DOCKGE_PORT}:5001"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ${STACKS_DIR}:/app/data/stacks
    restart: unless-stopped
    environment:
      - DOCKGE_STACKS_DIR=/app/data/stacks
      - DOCKGE_ENABLE_CONSOLE=true
EOF

print_success "docker-compose.yml created"

print_subsection "Starting Dockge container"
cd "$DOCKGE_DIR"
chown -R "$TARGET_USER:$TARGET_GROUP" "$DOCKGE_DIR"
docker compose up -d
sleep 3

if docker ps | grep -q dockge; then
  print_success "Dockge container is running"
else
  print_warning "Dockge container status could not be verified"
fi

# ====================================================================
# STEP 4: DOWNLOAD DOCKGE STACKS FROM GITHUB
# ====================================================================

print_section "STEP 4: DOWNLOAD DOCKGE STACKS FROM GITHUB"

REPO="josephcooley/server-setup"
BRANCH="main"
STACKS_RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}/stacks"
GITHUB_API="https://api.github.com/repos/${REPO}/git/trees/${BRANCH}?recursive=1"

print_subsection "Fetching file list from GitHub API"
API_RESPONSE=$(curl -fsSL "$GITHUB_API")
if [[ -z "$API_RESPONSE" ]]; then
  print_error "Failed to reach GitHub API"
  exit 1
fi

STACK_FILES=$(echo "$API_RESPONSE" | awk '
  /"path"[[:space:]]*:[[:space:]]*"stacks\// { path=$0; sub(/^.*"path"[[:space:]]*:[[:space:]]*"/, "", path); sub(/".*$/, "", path) }
  /"type"[[:space:]]*:[[:space:]]*"blob"/ && path ~ /^stacks\// { print path; path="" }
')

if [[ -z "$STACK_FILES" ]]; then
  print_warning "No files found under stacks/ in the repository"
else
  print_subsection "Downloading stacks to $STACKS_DIR"
  while IFS= read -r FULL_PATH; do
    REL_PATH="${FULL_PATH#stacks/}"
    DEST="$STACKS_DIR/$REL_PATH"
    mkdir -p "$(dirname "$DEST")"
    if curl -fsSL "$STACKS_RAW_BASE/$REL_PATH" -o "$DEST"; then
      print_success "Downloaded: $REL_PATH"
    else
      print_warning "Failed to download: $REL_PATH"
    fi
  done <<< "$STACK_FILES"
fi

# ====================================================================
# COMPLETION SUMMARY
# ====================================================================

print_section "SETUP COMPLETE"

echo -e "${GREEN}Dockge is installed and configured!${NC}"
echo ""
echo -e "${YELLOW}Access Point:${NC}"
echo "  • Dockge:    http://${PRIMARY_IP}:${DOCKGE_PORT}"
echo ""
echo -e "${YELLOW}Installed Services:${NC}"
echo "  ✓ Docker & Docker Compose"
echo "  ✓ Dockge (Docker Management UI)"
echo "  ✓ Dockge stacks synced from GitHub"
echo ""
