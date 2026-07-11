#!/bin/bash
################################################################################
# Combined Server Setup Script
# Automates Ubuntu server configuration with:
#   - Docker & Dockhand setup (Container management)
#   - SMB network share (Samba)
# Author: Joseph M. Cooley
# Usage: sudo bash server-setup.sh
################################################################################

set -e

# ====================================================================
# CONFIGURATION (edit these before running)
# ====================================================================

# SMB/Samba Configuration
SHARE_DIR="/opt/stacks/hermes/workspace"
SHARE_NAME="workspace"
SMB_WORKGROUP="WORKGROUP"
SMB_HOSTS_ALLOW="192.168.1.0/24 127.0.0.1"
SAMBA_PASSWORD=""  # Leave empty to be prompted at startup

# Dockhand Configuration
DOCKHAND_PORT="3099"
STACKS_DIR="/opt/stacks"

# Prefer the invoking user for Hermes config when running via sudo.
TARGET_USER="${SUDO_USER:-${USER:-root}}"
TARGET_GROUP="$(id -gn "$TARGET_USER")"
SAMBA_USERNAME="$TARGET_USER"

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
echo "  3. Dockhand (Docker Management UI)"
echo "  4. Samba (SMB Network Share)"
echo ""
echo "Stack files are not downloaded by this script."
echo "Use install-stacks.sh for hermesstacks/mediastacks and hermes-after-launch.sh for hermesconfig."
echo ""

# ====================================================================
# STEP 1: SYSTEM UPDATE AND TIMEZONE CONFIGURATION
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

# Verify Docker installation
if docker --version &>/dev/null; then
    DOCKER_VERSION=$(docker --version)
    print_success "$DOCKER_VERSION"
else
    print_warning "Could not verify Docker installation"
fi

# ====================================================================
# STEP 3: DOCKHAND SETUP
# ====================================================================

print_section "STEP 3: DOCKHAND SETUP"

print_subsection "Creating Dockhand directories"
mkdir -p "$STACKS_DIR"
mkdir -p "$STACKS_DIR/dockhand"
chown -R "$TARGET_USER:$TARGET_GROUP" "$STACKS_DIR/dockhand"
print_success "Directories created: $STACKS_DIR/dockhand, $STACKS_DIR"

print_subsection "Creating compose.yaml for Dockhand"
cat > "$STACKS_DIR/dockhand/compose.yaml" << EOF
services:
  dockhand:
    image: fnsys/dockhand:latest
    container_name: dockhand
    restart: unless-stopped
    ports:
      - 3099:3000
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - dockhand_data:/app/data
      - /opt/stacks:/stacks
volumes:
  dockhand_data: null
networks: {}
EOF

print_success "Dockhand compose.yaml created"

print_subsection "Starting Dockhand container"
cd "$STACKS_DIR/dockhand"
chown -R "$TARGET_USER:$TARGET_GROUP" "$STACKS_DIR/dockhand"
docker compose up -d

# Wait until the Dockhand container appears in docker ps instead of using a fixed delay.
for _ in {1..20}; do
    if docker ps --format '{{.Names}}' | grep -qx "dockhand"; then
        break
    fi
    sleep 1
done

if docker ps | grep -q dockhand; then
    print_success "Dockhand container is running"
else
    print_warning "Dockhand container status could not be verified"
fi

# ====================================================================
# STEP 4: SAMBA/SMB SETUP
# ====================================================================

print_section "STEP 4: SAMBA/SMB NETWORK SHARE SETUP"

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

# Wait for Samba service activation instead of relying on a fixed delay.
for _ in {1..20}; do
    if systemctl is-active --quiet smbd 2>/dev/null || systemctl is-active --quiet smb 2>/dev/null; then
        break
    fi
    sleep 1
done

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
# COMPLETION SUMMARY
# ====================================================================

print_section "SETUP COMPLETE"

echo -e "${GREEN}All components installed and configured!${NC}"
echo ""
echo -e "${YELLOW}Access Points:${NC}"
echo "  • Dockhand:     http://${PRIMARY_IP}:${DOCKHAND_PORT}"
echo "  • SMB Share:    \\\\${PRIMARY_IP}\\${SHARE_NAME}"
echo "  • Share Path:   ${SHARE_DIR}"
echo ""
echo -e "${YELLOW}SMB Share Credentials:${NC}"
echo "  • Username:     ${SAMBA_USERNAME}"
echo "  • Password:     (as configured during setup)"
echo ""
echo -e "${YELLOW}Installed Services:${NC}"
echo "  ✓ Docker & Docker Compose"
echo "  ✓ Dockhand (Docker Management UI)"
echo "  ✓ Samba (SMB Network Share - Authenticated)"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "1. Download stack files:"
echo "   sudo bash install-stacks.sh"
echo ""
echo "2. Download Hermes config:"
echo "   sudo bash hermes-after-launch.sh"
echo ""
echo "3. Access Dockhand:"
echo "   Open http://${PRIMARY_IP}:${DOCKHAND_PORT} in your browser"
echo ""
echo "4. Mount SMB share on Windows:"
echo "   \\\\${PRIMARY_IP}\\${SHARE_NAME}"
echo "   (When prompted, use username: ${SAMBA_USERNAME})"
echo ""
echo "5. Mount SMB share on Linux/Mac:"
echo "   sudo mount -t cifs //${PRIMARY_IP}/${SHARE_NAME} /mnt/${SHARE_NAME} -o username=${SAMBA_USERNAME},password=<your_password>"
echo ""
echo -e "${BLUE}========================================${NC}"
echo ""
