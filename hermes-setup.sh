#!/bin/bash
################################################################################
# Combined Server Setup Script
# Automates Ubuntu server configuration with:
#   - Install Hermes Agent
#   - Docker & Dockge setup (Container management)
#   - SMB network share (Samba)
#   - Telegram bot integration (Hermes Agent)
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

# Telegram settings (fill these in or the script will prompt)
TELEGRAM_BOT_TOKEN=""
TELEGRAM_USER_ID=""

# Dockge Configuration
DOCKGE_PORT="5001"
DOCKGE_DIR="/opt/dockge"
STACKS_DIR="/opt/stacks"

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
echo "  2. Hermes Agent"
echo "  3. Docker & Docker Compose"
echo "  4. Dockge (Docker Management UI)"
echo "  5. Samba (SMB Network Share)"
echo "  6. Telegram Bot Integration"
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
# STEP 2: HERMES AGENT INSTALLATION
# ====================================================================

print_section "STEP 2: HERMES AGENT INSTALLATION"

# Check if Hermes is already installed
if command -v hermes &>/dev/null; then
    HERMES_VERSION=$(hermes --version 2>/dev/null || echo "unknown version")
    print_success "Hermes Agent is already installed: $HERMES_VERSION"
else
    print_subsection "Installing Hermes Agent"
    
    # Install Hermes Agent from GitHub releases
    print_info "Downloading and installing Hermes Agent from GitHub..."
    
    # Detect system architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        ARCH="amd64"
    elif [[ "$ARCH" == "aarch64" ]]; then
        ARCH="arm64"
    fi
    
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
# STEP 3: DOCKER & DOCKER COMPOSE INSTALLATION
# ====================================================================

print_section "STEP 3: DOCKER & DOCKER COMPOSE INSTALLATION"

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
# STEP 4: DOCKGE SETUP
# ====================================================================

print_section "STEP 4: DOCKGE SETUP"

print_subsection "Creating Dockge directories"
mkdir -p "$DOCKGE_DIR"
mkdir -p "$STACKS_DIR"
print_success "Directories created: $DOCKGE_DIR, $STACKS_DIR"

print_subsection "Creating docker-compose.yml for Dockge"
cat > "$DOCKGE_DIR/docker-compose.yml" << 'EOF'
services:
  dockge:
    image: louislam/dockge:latest
    container_name: dockge
    ports:
      - "5001:5001"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /opt/dockge/stacks:/app/data/stacks
    restart: unless-stopped
    environment:
      - DOCKGE_STACKS_DIR=/app/data/stacks
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

# Create Samba user with password (using echo to pipe password)
echo -e "${SAMBA_PASSWORD}\n${SAMBA_PASSWORD}" | smbpasswd -a "${SAMBA_USERNAME}" 2>/dev/null

if smbpasswd -e "${SAMBA_USERNAME}" &>/dev/null; then
    print_success "Samba user '${SAMBA_USERNAME}' created/updated with password"
else
    print_warning "Could not create Samba user - checking if it already exists"
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

# Force SMB2/3 protocol
if ! grep -q "server min protocol = SMB2" /etc/samba/smb.conf; then
    sed -i '/^[[:space:]]*map to guest = bad user/a\   server min protocol = SMB2\n   server max protocol = SMB3\n   client min protocol = SMB2\n   client max protocol = SMB3' /etc/samba/smb.conf
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
# STEP 6: TELEGRAM SETUP
# ====================================================================

print_section "STEP 6: TELEGRAM BOT INTEGRATION"

# Check if Hermes is installed
if ! command -v hermes &>/dev/null; then
    print_warning "Hermes CLI not found in PATH"
    echo ""
    echo "To configure Telegram after Hermes is installed:"
    echo "  1. Set TELEGRAM_BOT_TOKEN in ~/.hermes/.env"
    echo "  2. Set TELEGRAM_HOME_CHANNEL to your user ID in ~/.hermes/.env"
    echo "  3. Run: hermes gateway restart"
    echo ""
    print_info "Skipping Telegram setup — Hermes not yet installed"
else
    print_subsection "Hermes CLI found — proceeding with Telegram setup"
    
    ENV_FILE="$HOME/.hermes/.env"
    
    # Create .env if it doesn't exist
    if [[ ! -f "$ENV_FILE" ]]; then
        print_info "Creating $ENV_FILE"
        mkdir -p "$HOME/.hermes"
        touch "$ENV_FILE"
        chmod 600 "$ENV_FILE"
    fi
    
    # Check if Telegram is already configured
    if grep -q "^TELEGRAM_BOT_TOKEN=" "$ENV_FILE" 2>/dev/null && \
       grep -q "^TELEGRAM_HOME_CHANNEL=" "$ENV_FILE" 2>/dev/null; then
        EXISTING_TOKEN=$(grep "^TELEGRAM_BOT_TOKEN=" "$ENV_FILE" | cut -d= -f2)
        EXISTING_CHAT=$(grep "^TELEGRAM_HOME_CHANNEL=" "$ENV_FILE" | cut -d= -f2)
        print_info "Telegram already configured in .env"
        print_info "  Bot token: ${EXISTING_TOKEN:0:10}..."
        print_info "  Home chat: $EXISTING_CHAT"
        
        read -p "Reconfigure Telegram? (y/N): " RECONFIG
        if [[ "$RECONFIG" != "y" && "$RECONFIG" != "Y" ]]; then
            print_info "Keeping existing Telegram config"
        else
            TELEGRAM_BOT_TOKEN=""
            TELEGRAM_USER_ID=""
        fi
    fi
    
    # If not already configured or user chose to reconfigure
    if [[ -z "$TELEGRAM_BOT_TOKEN" ]]; then
        echo ""
        echo "To set up Telegram, you need:"
        echo "  1. A bot token from @BotFather on Telegram"
        echo "     (send /newbot, follow the steps, copy the token)"
        echo "  2. Your Telegram numeric user ID"
        echo "     (message @userinfobot on Telegram to get it)"
        echo ""
        
        read -p "Paste your Telegram bot token: " TELEGRAM_BOT_TOKEN
        read -p "Paste your Telegram numeric user ID: " TELEGRAM_USER_ID
        
        if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_USER_ID" ]]; then
            print_error "Both bot token and user ID are required"
            print_warning "Skipping Telegram setup"
        else
            print_subsection "Writing Telegram configuration"
            
            # Remove old entries
            sed -i '/^TELEGRAM_BOT_TOKEN=/d' "$ENV_FILE"
            sed -i '/^TELEGRAM_HOME_CHANNEL=/d' "$ENV_FILE"
            sed -i '/^TELEGRAM_ALLOWED_USERS=/d' "$ENV_FILE"
            
            # Append new entries
            cat >> "$ENV_FILE" << EOF

# TELEGRAM INTEGRATION
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
TELEGRAM_HOME_CHANNEL=${TELEGRAM_USER_ID}
TELEGRAM_ALLOWED_USERS=${TELEGRAM_USER_ID}
EOF
            
            chmod 600 "$ENV_FILE"
            print_success "Telegram config written to $ENV_FILE"
            
            print_subsection "Enabling Telegram in Hermes gateway"
            hermes config set gateway.platforms.telegram.enabled true 2>/dev/null || true
            
            print_subsection "Restarting Hermes gateway"
            if systemctl --user is-active --quiet hermes-gateway 2>/dev/null; then
                systemctl --user restart hermes-gateway
                sleep 3
                if systemctl --user is-active --quiet hermes-gateway; then
                    print_success "Hermes gateway restarted successfully"
                else
                    print_warning "Gateway restart may have failed"
                    echo "Check with: systemctl --user status hermes-gateway"
                fi
            else
                print_warning "Hermes gateway service not found"
                echo "Start it manually with:"
                echo "  systemctl --user start hermes-gateway"
                echo "  or: hermes gateway start"
            fi
            
            print_success "Telegram bot token: ${TELEGRAM_BOT_TOKEN:0:10}..."
            print_success "Home chat ID: ${TELEGRAM_USER_ID}"
        fi
    fi
fi

# ====================================================================
# COMPLETION SUMMARY
# ====================================================================

print_section "SETUP COMPLETE"

echo -e "${GREEN}All components installed and configured!${NC}"
echo ""
echo -e "${YELLOW}Access Points:${NC}"
echo "  • Dockge:       http://${PRIMARY_IP}:${DOCKGE_PORT}"
echo "  • SMB Share:    \\\\\\\\${PRIMARY_IP}\\\\${SHARE_NAME}"
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
if command -v hermes &>/dev/null && grep -q "TELEGRAM_BOT_TOKEN=" "$HOME/.hermes/.env" 2>/dev/null; then
    echo "  ✓ Telegram Integration"
fi
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "1. Access Dockge:"
echo "   Open http://${PRIMARY_IP}:${DOCKGE_PORT} in your browser"
echo ""
echo "2. Mount SMB share on Windows:"
echo "   \\\\\\\\${PRIMARY_IP}\\\\${SHARE_NAME}"
echo "   (When prompted, use username: ${SAMBA_USERNAME})"
echo ""
echo "3. Mount SMB share on Linux/Mac:"
echo "   sudo mount -t cifs //${PRIMARY_IP}/${SHARE_NAME} /mnt/${SHARE_NAME} -o username=${SAMBA_USERNAME},password=<your_password>"
echo ""
if command -v hermes &>/dev/null; then
    echo "4. Test Telegram:"
    echo "   Send a message to your bot on Telegram"
    echo "   Check logs: journalctl --user -u hermes-gateway -f"
    echo ""
fi
echo -e "${BLUE}========================================${NC}"
echo ""
