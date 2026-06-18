#!/bin/bash
################################################################################
# Combined Server Setup Script
# Automates Ubuntu server configuration with:
#   - Install Hermes Agent
#   - Docker & Dockge setup (Container management)
#   - SMB network share (Samba)
#
# Author: Joseph M. Cooley
# Usage: sudo bash hermes-setup.sh
################################################################################

set -e

# ====================================================================
# CONFIGURATION (edit these before running)
# ====================================================================

# SMB/Samba Configuration
SHARE_DIR="/srv/samba/share"
SHARE_NAME="hermes-share"
SMB_WORKGROUP="WORKGROUP"
SMB_HOSTS_ALLOW="192.168.1.0/24 127.0.0.1"
SAMBA_USERNAME="Joseph"
SAMBA_PASSWORD=""  # Leave empty to be prompted at startup

# Dockge Configuration
DOCKGE_PORT="5001"
DOCKGE_DIR="/opt/dockge"
STACKS_DIR="/opt/dockge/stacks"

# Prefer the invoking user for Hermes config when running via sudo.
TARGET_USER="${SUDO_USER:-${USER:-root}}"
if [[ "$TARGET_USER" == "root" ]]; then
    TARGET_HOME="/root"
else
    TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
    if [[ -z "$TARGET_HOME" ]]; then
        TARGET_HOME="/home/$TARGET_USER"
    fi
fi

# ====================================================================
# COLOR CODES & OUTPUT FUNCTIONS
# ====================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Standardized output functions
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

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

print_success "Running with root privileges"

# Get primary IP for display
PRIMARY_IP=$(hostname -I | awk '{print $1}')
print_success "Primary IP: $PRIMARY_IP"

# ====================================================================
# PROMPT FOR SAMBA PASSWORD (if not set in configuration)
# ====================================================================

if [[ -z "$SAMBA_PASSWORD" ]]; then
    echo ""
    print_section "SAMBA AUTHENTICATION SETUP"
    echo ""
    echo "The Samba share will require authentication."
    echo "Username: ${SAMBA_USERNAME}"
    echo ""
    
    while true; do
        read -sp "Enter password for '${SAMBA_USERNAME}': " SAMBA_PASSWORD
        echo ""
        read -sp "Confirm password: " SAMBA_PASSWORD_CONFIRM
        echo ""
        
        if [[ "$SAMBA_PASSWORD" == "$SAMBA_PASSWORD_CONFIRM" ]]; then
            print_success "Passwords match"
            break
        else
            print_error "Passwords do not match. Please try again."
            echo ""
        fi
    done
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  COMBINED SERVER SETUP${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "This script will set up:"
echo "  1. System updates"
echo "  2. Docker & Docker Compose"
echo "  3. Dockge (Docker Management UI)"
echo "  4. Dockge Stacks (from GitHub)"
echo "  5. Samba (SMB Network Share)"
echo "  6. Hermes Agent"
echo ""

# ====================================================================
# STEP 1: SYSTEM UPDATE (consolidated)
# ====================================================================

print_section "STEP 1: SYSTEM UPDATE"

print_subsection "Updating package lists and upgrading system"
apt update
apt upgrade -y

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

# Verify Docker installation
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

# Extract all blob paths under stacks/
STACK_FILES=$(echo "$API_RESPONSE" | grep -oP '"path"\s*:\s*"\Kstacks/[^"]+(?=")' | grep -v '/$')

if [[ -z "$STACK_FILES" ]]; then
    print_warning "No files found under stacks/ in the repository"
else
    print_subsection "Downloading stacks to $STACKS_DIR"
    while IFS= read -r FULL_PATH; do
        # Strip leading "stacks/" to get relative path within STACKS_DIR
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
# STEP 5: SAMBA/SMB SETUP
# ====================================================================

print_section "STEP 5: SAMBA/SMB NETWORK SHARE SETUP"

print_subsection "Installing Samba packages"
apt install samba samba-common-bin -y

if command -v smbd &>/dev/null; then
    SAMBA_VERSION=$(smbd --version | head -1)
    print_success "Samba installed: $SAMBA_VERSION"
else
    print_warning "Could not verify Samba installation"
fi

print_subsection "Creating share directory: $SHARE_DIR"
mkdir -p "$SHARE_DIR"
chmod 2775 "$SHARE_DIR"
chown root:root "$SHARE_DIR"
print_success "Share directory configured"

print_subsection "Backing up existing smb.conf (if present)"
if [[ -f /etc/samba/smb.conf ]]; then
    BACKUP="/etc/samba/smb.conf.bak.$(date +%Y%m%d%H%M%S)"
    cp /etc/samba/smb.conf "$BACKUP"
    print_success "Backed up to: $BACKUP"
fi

print_subsection "Configuring Samba share"

# Remove old hermes-share section if it exists (idempotent)
if grep -q "^\[${SHARE_NAME}\]" /etc/samba/smb.conf 2>/dev/null; then
    print_warning "Existing [$SHARE_NAME] section found — removing old config"
    sed -i "/^\[${SHARE_NAME}\]/,/^$/d" /etc/samba/smb.conf
    sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' /etc/samba/smb.conf
fi

# Append the share definition
cat >> /etc/samba/smb.conf << EOF

[${SHARE_NAME}]
   comment = Hermes Output Files
   path = ${SHARE_DIR}
   browseable = yes
   read only = no
   writable = yes
   valid users = ${SAMBA_USERNAME}
   read list = ${SAMBA_USERNAME}
   write list = ${SAMBA_USERNAME}
   create mask = 0666
   directory mask = 0777
   hosts allow = ${SMB_HOSTS_ALLOW}
   hosts deny = 0.0.0.0/0
EOF

print_success "Share definition added to smb.conf"

# ====================================================================
# CREATE SAMBA USER
# ====================================================================

print_subsection "Creating Samba user: ${SAMBA_USERNAME}"

# Check if user exists in system, if not create them
if ! id "${SAMBA_USERNAME}" &>/dev/null; then
    useradd -m -s /usr/sbin/nologin "${SAMBA_USERNAME}"
    print_info "System user '${SAMBA_USERNAME}' created"
else
    print_info "System user '${SAMBA_USERNAME}' already exists"
fi

# Create or update Samba user password without failing on reruns
if pdbedit -L -u "${SAMBA_USERNAME}" &>/dev/null; then
    printf '%s\n%s\n' "$SAMBA_PASSWORD" "$SAMBA_PASSWORD" | smbpasswd -s "${SAMBA_USERNAME}" 2>/dev/null
    smbpasswd -e "${SAMBA_USERNAME}" &>/dev/null || true
    print_success "Samba user '${SAMBA_USERNAME}' password updated"
else
    printf '%s\n%s\n' "$SAMBA_PASSWORD" "$SAMBA_PASSWORD" | smbpasswd -a -s "${SAMBA_USERNAME}" 2>/dev/null
    smbpasswd -e "${SAMBA_USERNAME}" &>/dev/null || true
    print_success "Samba user '${SAMBA_USERNAME}' created with password"
fi

# Ensure share directory is accessible by the Samba user
chown "${SAMBA_USERNAME}:${SAMBA_USERNAME}" "$SHARE_DIR" 2>/dev/null || chown "${SAMBA_USERNAME}" "$SHARE_DIR"
chmod 755 "$SHARE_DIR"
print_success "Share directory permissions configured for ${SAMBA_USERNAME}"

# Ensure NetBIOS is enabled
if grep -q "^[[:space:]]*disable netbios = yes" /etc/samba/smb.conf; then
    sed -i 's/^[[:space:]]*disable netbios = yes/   disable netbios = no/' /etc/samba/smb.conf
    print_info "Enabled NetBIOS for Windows discovery"
fi

# Apply workgroup setting to [global] section
if grep -q "^[[:space:]]*workgroup" /etc/samba/smb.conf; then
    sed -i "s/^[[:space:]]*workgroup[[:space:]]*=.*/   workgroup = ${SMB_WORKGROUP}/" /etc/samba/smb.conf
else
    sed -i "/^\[global\]/a\   workgroup = ${SMB_WORKGROUP}" /etc/samba/smb.conf
fi
print_info "Workgroup set to ${SMB_WORKGROUP}"

# Force SMB2/3 protocol (anchor on [global] section, not a specific line)
if ! grep -q "server min protocol = SMB2" /etc/samba/smb.conf; then
    sed -i "/^\[global\]/a\   client max protocol = SMB3\n   client min protocol = SMB2\n   server max protocol = SMB3\n   server min protocol = SMB2" /etc/samba/smb.conf
    print_info "Enforced SMB2/3 protocol for Windows 10/11 compatibility"
fi

print_subsection "Validating Samba configuration"
if testparm -s &>/dev/null; then
    print_success "Samba configuration is valid"
else
    print_warning "Samba configuration validation had issues"
fi

print_subsection "Starting Samba services"
systemctl enable smbd nmbd 2>/dev/null || systemctl enable smb 2>/dev/null || true
systemctl restart smbd nmbd 2>/dev/null || systemctl restart smb 2>/dev/null || true
sleep 2

if systemctl is-active --quiet smbd 2>/dev/null || systemctl is-active --quiet smb 2>/dev/null; then
    print_success "Samba services are running"
else
    print_warning "Samba services status could not be verified"
fi

if ss -tlnp | grep -qE ':(139|445)'; then
    print_success "SMB ports 139 and 445 are listening"
else
    print_warning "SMB ports not detected — check firewall"
fi

print_subsection "Configuring UFW firewall (if active)"
if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow samba
    print_success "Samba ports opened in UFW"
else
    print_info "UFW not active or not installed"
fi

# ====================================================================
# STEP 6: HERMES AGENT INSTALLATION
# ====================================================================

print_section "STEP 6: HERMES AGENT INSTALLATION"

# Check if Hermes is already installed
if command -v hermes &>/dev/null; then
    HERMES_VERSION=$(hermes --version 2>/dev/null || echo "unknown version")
    print_success "Hermes Agent is already installed: $HERMES_VERSION"
else
    print_subsection "Installing Hermes Agent"
    
    # Install Hermes Agent from GitHub releases
    print_info "Downloading and installing Hermes Agent from GitHub..."
    
    # Create temp directory for installation
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT
    
    # Install Hermes Agent from official Nous Research installer
    if curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash; then
        print_success "Hermes Agent installed successfully"
    else
        print_error "Failed to install Hermes Agent from official installer"
        echo ""
        echo "Installation URL: curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash"
        echo ""
        echo "Please visit: https://hermes-agent.nousresearch.com/ for more information"
        exit 1
    fi
fi

# Verify Hermes installation
if command -v hermes &>/dev/null; then
    print_success "Hermes Agent is ready"
    print_info "Run 'hermes --help' for available commands"
    sleep 1
else
    print_warning "Hermes Agent not found in PATH — you may need to install it manually"
fi

# ====================================================================
# COMPLETION SUMMARY
# ====================================================================

print_section "SETUP COMPLETE"

echo -e "${GREEN}All components installed and configured!${NC}"
echo ""
echo -e "${YELLOW}Access Points:${NC}"
echo "  • Dockge:       http://${PRIMARY_IP}:${DOCKGE_PORT}"
echo "  • SMB Share:    \\\\${PRIMARY_IP}\\${SHARE_NAME}"
echo "  • Share Path:   ${SHARE_DIR}"
echo ""
echo -e "${YELLOW}SMB Share Credentials:${NC}"
echo "  • Username:     ${SAMBA_USERNAME}"
echo "  • Password:     (as configured during setup)"
echo ""
echo -e "${YELLOW}Installed Services:${NC}"
echo "  ✓ Docker & Docker Compose"
echo "  ✓ Dockge (Docker Management UI)"
echo "  ✓ Samba (SMB Network Share - Authenticated)"
echo "  ✓ Hermes Agent"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "1. Access Dockge:"
echo "   Open http://${PRIMARY_IP}:${DOCKGE_PORT} in your browser"
echo ""
echo "2. Mount SMB share on Windows:"
echo "   \\\\${PRIMARY_IP}\\${SHARE_NAME}"
echo "   (When prompted, use username: ${SAMBA_USERNAME})"
echo ""
echo "3. Mount SMB share on Linux/Mac:"
echo "   sudo mount -t cifs //${PRIMARY_IP}/${SHARE_NAME} /mnt/${SHARE_NAME} -o username=${SAMBA_USERNAME},password=<your_password>"
echo ""
echo -e "${BLUE}========================================${NC}"
echo ""
