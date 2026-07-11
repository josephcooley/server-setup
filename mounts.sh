################################################################################
# TrueNAS Server Setup Script
# Automates Ubuntu server configuration with NFS mounts
# Author: Joseph M. Cooley
################################################################################
#!/bin/bash

# Ubuntu Server Setup Script
# This script automates the setup of an Ubuntu server with NFS mounts
# Run with: sudo bash mounts.sh

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root (use sudo)${NC}"
   exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Ubuntu Server Setup Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to print section headers
print_section() {
    echo -e "${BLUE}>>> $1${NC}"
}

# Function to print subsection headers
print_subsection() {
    echo -e "${BLUE}→ $1${NC}"
}

# Function to print success messages
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function to print warnings
print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# ==========================================
# 1. System Update
# ==========================================
print_section "STEP 1: SYSTEM UPDATE"

print_subsection "Updating package lists and upgrading system"
apt update
apt upgrade -y
apt autoremove -y
apt autoclean -y

timedatectl set-timezone America/Los_Angeles #set timezone for los angeles

print_success "System packages updated" 

# ==========================================
# 2. Install NFS
# ==========================================
print_section "Step 2: Installing NFS client"
apt install nfs-common -y
print_success "NFS client installed"
echo ""

# ==========================================
# 3. Create NFS mount directories
# ==========================================
print_section "Step 3: Creating NFS mount directories"
mkdir -p /mnt/books /mnt/documents /mnt/downloads /mnt/movies /mnt/tv
print_success "Directories created: /mnt/books, /mnt/documents, /mnt/downloads, /mnt/movies, /mnt/tv"
echo ""

# ==========================================
# 4. Configure NFS mounts in fstab
# ==========================================
print_section "Step 4: Configuring NFS mounts in /etc/fstab"

# Backup original fstab
cp /etc/fstab /etc/fstab.backup
print_warning "Backup of original fstab created at /etc/fstab.backup"

# Add NFS mount entries idempotently (avoid duplicates on reruns)
ensure_fstab_entry() {
    local entry="$1"
    if grep -Fqx "$entry" /etc/fstab; then
        print_info "fstab entry already exists, skipping: $entry"
    else
        echo "$entry" >> /etc/fstab
        print_success "Added fstab entry: $entry"
    fi
}

# Add a section header once
if ! grep -Fqx "# NFS Mounts" /etc/fstab; then
    echo "" >> /etc/fstab
    echo "# NFS Mounts" >> /etc/fstab
fi

ensure_fstab_entry "192.168.1.100:/mnt/Storage/Books      /mnt/books      nfs   defaults,_netdev   0  0"
ensure_fstab_entry "192.168.1.100:/mnt/Storage/Documents  /mnt/documents  nfs   defaults,_netdev   0  0"
ensure_fstab_entry "192.168.1.100:/mnt/Storage/Downloads  /mnt/downloads  nfs   defaults,_netdev   0  0"
ensure_fstab_entry "192.168.1.100:/mnt/Storage/TV         /mnt/tv         nfs   defaults,_netdev   0  0"
ensure_fstab_entry "192.168.1.100:/mnt/Storage/Movies     /mnt/movies     nfs   defaults,_netdev   0  0"

print_success "NFS mount entries ensured in /etc/fstab"
print_warning "⚠ IMPORTANT: Edit /etc/fstab and replace 192.168.1.100 with your actual NFS server IP address"
echo ""

# ==========================================
# 5. Mount NFS filesystems
# ==========================================
print_section "Step 5: Reloading systemd daemon and mounting NFS filesystems"
systemctl daemon-reload
mount -a
print_success "NFS filesystems mounted"
echo ""

# ==========================================
# Completion Summary
# ==========================================
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Important Next Steps:${NC}"
echo "1. Edit /etc/fstab and replace 192.168.1.100 with your actual NFS server IP:"
echo "   nano /etc/fstab"
echo ""
echo "2. Remount NFS filesystems after editing:"
echo "   sudo mount -a"
echo ""
echo -e "${YELLOW}Installed Services:${NC}"
echo "✓ NFS Client"
echo ""
echo -e "${YELLOW}Created Directories:${NC}"
echo "✓ /mnt/books"
echo "✓ /mnt/documents"
echo "✓ /mnt/downloads"
echo "✓ /mnt/movies"
echo "✓ /mnt/tv"
echo "✓ /opt/dockge"
echo "✓ /opt/stacks"
echo ""
