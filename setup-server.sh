#!/bin/bash

################################################################################
# TrueNAS Server Setup Script
# Automates Ubuntu server configuration with NFS mounts and Docker/Dockge setup
# Author: Joseph M. Cooley
################################################################################

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAS_IP="192.168.1.100"
NAS_DOMAIN="truenas.local"
TRUENAS_UID=3000
TRUENAS_GID=3000
TRUENAS_USER="truenas"
DOCKGE_PORT=5001
DOCKGE_PATH="/opt/dockge"
STACKS_PATH="/opt/stacks"

################################################################################
# Helper Functions
################################################################################

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

################################################################################
# Diagnostic Functions
################################################################################

diagnose_network() {
    log_info "Running network diagnostics..."
    
    if ping -c 1 -W 2 $NAS_IP > /dev/null 2>&1; then
        log_info "✓ Can reach NAS at $NAS_IP"
    else
        log_error "✗ Cannot reach NAS at $NAS_IP"
        log_error "  - Check NAS IP address is correct"
        log_error "  - Verify network connectivity"
        return 1
    fi
    
    if command -v showmount &> /dev/null; then
        log_info "Checking NFS exports on NAS..."
        if showmount -e $NAS_IP > /dev/null 2>&1; then
            log_info "✓ NAS has NFS exports available"
            log_debug "Available exports:"
            showmount -e $NAS_IP | sed 's/^/  /'
        else
            log_error "✗ Cannot list NFS exports from $NAS_IP"
            log_error "  - Check if NFS is enabled on TrueNAS"
            log_error "  - Verify NFS sharing is configured for the shares"
            return 1
        fi
    fi
    
    return 0
}

################################################################################
# System Updates
################################################################################

update_system() {
    log_info "Updating system packages..."
    apt update && apt upgrade -y
    log_info "System update complete"
}

################################################################################
# User and Group Setup
################################################################################

setup_truenas_user() {
    log_info "Setting up TrueNAS user and group..."
    
    # Check if group exists
    if getent group $TRUENAS_GID > /dev/null 2>&1; then
        log_warn "Group with GID $TRUENAS_GID already exists"
    else
        groupadd -g $TRUENAS_GID $TRUENAS_USER
        log_info "Created group: $TRUENAS_USER (GID: $TRUENAS_GID)"
    fi
    
    # Check if user exists
    if id "$TRUENAS_USER" > /dev/null 2>&1; then
        log_warn "User $TRUENAS_USER already exists"
    else
        useradd -u $TRUENAS_UID -g $TRUENAS_USER -m -s /bin/bash $TRUENAS_USER
        log_info "Created user: $TRUENAS_USER (UID: $TRUENAS_UID)"
    fi
    
    # Add user to sudoers
    usermod -aG sudo $TRUENAS_USER
    log_info "Added $TRUENAS_USER to sudoers"
}

################################################################################
# NFS Setup
################################################################################

setup_nfs_mounts() {
    log_info "Setting up NFS mounts..."
    
    # Install NFS common utilities
    apt install -y nfs-common
    log_info "Installed nfs-common"
    
    # Create mount directories
    log_info "Creating mount directories..."
    mkdir -p /mnt/books
    mkdir -p /mnt/documents
    mkdir -p /mnt/downloads
    mkdir -p /mnt/movies
    mkdir -p /mnt/tv
    
    # Fix permissions on mount directories (may have been created by previous runs)
    chmod 755 /mnt/books /mnt/documents /mnt/downloads /mnt/movies /mnt/tv
    
    # Define NFS mounts
    declare -A NFS_MOUNTS=(
        ["/mnt/books"]="$NAS_IP:/mnt/Storage/Books"
        ["/mnt/documents"]="$NAS_IP:/mnt/Storage/Documents"
        ["/mnt/downloads"]="$NAS_IP:/mnt/Storage/Downloads"
        ["/mnt/tv"]="$NAS_IP:/mnt/Storage/TV"
        ["/mnt/movies"]="$NAS_IP:/mnt/Storage/Movies"
    )
    
    # Unmount any existing mounts first (from previous attempts)
    log_info "Cleaning up any previous mount attempts..."
    for mount_point in "${!NFS_MOUNTS[@]}"; do
        if mountpoint -q "$mount_point" 2>/dev/null; then
            log_debug "Unmounting $mount_point..."
            umount -l "$mount_point" 2>/dev/null || true
        fi
    done
    
    # Temporary mount to test connectivity
    log_info "Temporarily mounting NFS shares for testing..."
    local mount_success=0
    local mount_fail=0
    
    for mount_point in "${!NFS_MOUNTS[@]}"; do
        nfs_share="${NFS_MOUNTS[$mount_point]}"
        
        # Try NFSv3 first (more commonly compatible) - use only vers=3, not nfsvers
        if mount -t nfs -o vers=3 "$nfs_share" "$mount_point" 2>/dev/null; then
            log_info "✓ Successfully mounted (NFSv3): $nfs_share"
            ((mount_success++))
        # Then try NFSv4
        elif mount -t nfs -o vers=4 "$nfs_share" "$mount_point" 2>/dev/null; then
            log_info "✓ Successfully mounted (NFSv4): $nfs_share"
            ((mount_success++))
        # Try default NFS (let the system choose)
        elif mount -t nfs "$nfs_share" "$mount_point" 2>/dev/null; then
            log_info "✓ Successfully mounted (auto): $nfs_share"
            ((mount_success++))
        else
            log_error "✗ Failed to mount: $nfs_share"
            ((mount_fail++))
        fi
    done
    
    # Test access
    log_info "Testing NFS access..."
    if df -h | grep -q "$NAS_IP"; then
        log_info "✓ NFS mounts verified ($mount_success successful)"
    else
        log_error "✗ Failed to verify NFS mounts"
        log_warn "  Continuing with script - you may need to troubleshoot NFS separately"
    fi
    
    if [ $mount_fail -gt 0 ]; then
        log_warn "  $mount_fail mount(s) failed - may retry on reboot"
    fi
}

################################################################################
# Persistent NFS Mounts (fstab)
################################################################################

setup_persistent_mounts() {
    log_info "Configuring persistent NFS mounts in /etc/fstab..."
    
    # Backup fstab
    cp /etc/fstab /etc/fstab.backup
    log_info "Backed up /etc/fstab to /etc/fstab.backup"
    
    # Check if entries already exist to avoid duplicates
    if grep -q "$NAS_IP:/mnt/Storage/Books" /etc/fstab 2>/dev/null; then
        log_warn "NFS mounts already in /etc/fstab, skipping..."
        return 0
    fi
    
    # Add NFS entries to fstab with NFSv3 (more compatible) - use only vers=3
    cat >> /etc/fstab << EOF
$NAS_IP:/mnt/Storage/Books      /mnt/books      nfs   defaults,_netdev,vers=3   0  0
$NAS_IP:/mnt/Storage/Documents  /mnt/documents  nfs   defaults,_netdev,vers=3   0  0
$NAS_IP:/mnt/Storage/Downloads  /mnt/downloads  nfs   defaults,_netdev,vers=3   0  0
$NAS_IP:/mnt/Storage/TV         /mnt/tv         nfs   defaults,_netdev,vers=3   0  0
$NAS_IP:/mnt/Storage/Movies     /mnt/movies     nfs   defaults,_netdev,vers=3   0  0
EOF
    
    log_info "Added NFS mounts to /etc/fstab (using NFSv3)"
    
    # Reload and apply mounts
    systemctl daemon-reload
    if mount -a 2>/dev/null; then
        log_info "✓ Applied persistent mount configuration"
    else
        log_warn "Some mounts failed during 'mount -a'"
        log_warn "Check NFS connectivity - remaining mounts will retry on reboot"
    fi
}

################################################################################
# IDMapD Configuration (NFSv4 UID/GID mapping)
################################################################################

setup_idmapd() {
    log_info "Configuring NFSv4 UID/GID mapping (optional)..."
    
    # Configure idmapd.conf with nsswitch method (more reliable than 'file')
    cat > /etc/idmapd.conf << EOF
[General]
Domain = $NAS_DOMAIN
Verbosity = 0
Pipefs-Directory = /run/rpc_pipefs
Cache-Expiration = 600
Enable-GSS = yes

[Mapping]
Nobody-User = nobody
Nobody-Group = nogroup

[Translation]
Method = nsswitch

[Static]
$TRUENAS_UID@$NAS_DOMAIN = 1000
1000@$NAS_DOMAIN = $TRUENAS_UID
EOF
    
    log_info "Configured /etc/idmapd.conf (using nsswitch method)"
    
    # Try to restart NFS idmapd, but don't fail if it doesn't work
    # This is only needed for NFSv4 with UID/GID mapping
    if command -v systemctl &> /dev/null; then
        if systemctl restart nfs-idmapd 2>&1; then
            log_info "✓ Restarted nfs-idmapd service"
        else
            log_warn "⚠ nfs-idmapd failed to start (usually not critical for NFSv3)"
            log_debug "  This only affects NFSv4 UID/GID mapping"
        fi
    fi
}

################################################################################
# Docker Installation
################################################################################

install_docker() {
    log_info "Installing Docker..."
    
    # Check if already installed
    if command -v docker &> /dev/null; then
        log_warn "Docker already installed"
        return 0
    fi
    
    # Install prerequisites
    apt install -y ca-certificates curl gnupg
    
    # Setup Docker GPG key and repository
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Enable and start Docker
    systemctl enable --now docker
    log_info "✓ Docker installed and enabled"
}

################################################################################
# Dockge Installation
################################################################################

install_dockge() {
    log_info "Installing Dockge..."
    
    # Create directories
    mkdir -p $DOCKGE_PATH
    mkdir -p $STACKS_PATH
    log_info "Created Dockge directories"
    
    # Create docker-compose.yml
    cat > $DOCKGE_PATH/docker-compose.yml << EOF
services:
  dockge:
    image: louislam/dockge:latest
    container_name: dockge
    ports:
      - "$DOCKGE_PORT:5001"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - $DOCKGE_PATH/stacks:/app/data/stacks
    restart: unless-stopped
EOF
    
    log_info "Created Dockge docker-compose.yml"
    
    # Start Dockge
    cd $DOCKGE_PATH
    if docker compose up -d; then
        log_info "✓ Started Dockge container"
    else
        log_error "✗ Failed to start Dockge"
        return 1
    fi
}

################################################################################
# Summary
################################################################################

print_summary() {
    echo ""
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}Server Setup Complete!${NC}"
    echo -e "${GREEN}================================${NC}"
    echo ""
    echo "Configuration Summary:"
    echo "  NAS IP: $NAS_IP"
    echo "  NAS Domain: $NAS_DOMAIN"
    echo "  TrueNAS User: $TRUENAS_USER (UID: $TRUENAS_UID)"
    echo "  Dockge URL: http://localhost:$DOCKGE_PORT"
    echo "  NFS Version: NFSv3 (with NFSv4 fallback)"
    echo ""
    echo "NFS Mounts:"
    df -h | grep "$NAS_IP" || echo "  ⚠ No mounts currently visible (will attempt on reboot)"
    echo ""
    echo "Docker Status:"
    docker ps --filter "name=dockge" || echo "  (Dockge may not be running)"
    echo ""
    echo "Next Steps:"
    echo "  1. Switch to the new user: su - $TRUENAS_USER"
    echo "  2. Verify NFS mounts: df -h | grep $NAS_IP"
    echo "  3. Access Dockge: http://<server-ip>:$DOCKGE_PORT"
    echo ""
    echo "Permanent mounts configured in /etc/fstab"
    echo "Backup saved to /etc/fstab.backup"
    echo ""
}

################################################################################
# Main Execution
################################################################################

main() {
    log_info "Starting server setup..."
    
    check_root
    
    # Run diagnostics first
    if ! diagnose_network; then
        log_warn "Network diagnostics failed - NFS mounts may fail"
        log_warn "Continue anyway? (y/n)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_info "Setup cancelled"
            exit 1
        fi
    fi
    
    update_system
    setup_truenas_user
    install_docker
    setup_nfs_mounts
    setup_idmapd
    setup_persistent_mounts
    install_dockge
    
    print_summary
    
    log_info "Setup completed!"
}

# Run main function
main "$@"
