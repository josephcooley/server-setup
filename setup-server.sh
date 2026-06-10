################################################################################
# TrueNAS Server Setup Script
# Automates Ubuntu server configuration with NFS mounts and Docker/Dockge setup
# Author: Joseph M. Cooley
################################################################################
#!/bin/bash

# Ubuntu Server Setup Script
# This script automates the setup of an Ubuntu server with NFS, Docker, and Dockge
# Run with: sudo bash ubuntu-server-setup.sh

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
print_section "Step 1: Updating system packages"
apt update && apt upgrade -y
print_success "System packages updated"
echo ""

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

# Add NFS mount entries
cat >> /etc/fstab << 'EOF'

# NFS Mounts
192.168.1.100:/mnt/Storage/Books      /mnt/books      nfs   defaults,_netdev   0  0
192.168.1.100:/mnt/Storage/Documents  /mnt/documents  nfs   defaults,_netdev   0  0
192.168.1.100:/mnt/Storage/Downloads  /mnt/downloads  nfs   defaults,_netdev   0  0
192.168.1.100:/mnt/Storage/TV         /mnt/tv         nfs   defaults,_netdev   0  0
192.168.1.100:/mnt/Storage/Movies     /mnt/movies     nfs   defaults,_netdev   0  0
EOF

print_success "NFS mount entries added to /etc/fstab"
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
# 6. Install Docker prerequisites
# ==========================================
print_section "Step 6: Installing Docker prerequisites"
apt install ca-certificates curl gnupg -y
print_success "Prerequisites installed"
echo ""

# ==========================================
# 7. Add Docker repository and install Docker
# ==========================================
print_section "Step 7: Installing Docker"

# Create keyrings directory
install -m 0755 -d /etc/apt/keyrings

# Add Docker GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker packages
apt update && apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

# Enable and start Docker
systemctl enable --now docker

print_success "Docker installed and enabled"
echo ""

# ==========================================
# 8. Install Dockge
# ==========================================
print_section "Step 8: Installing Dockge"

# Create Dockge directories
mkdir -p /opt/dockge
mkdir -p /opt/stacks

# Create docker-compose.yml for Dockge
cat > /opt/dockge/docker-compose.yml << 'EOF'
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

print_success "Dockge docker-compose.yml created"
echo ""

# ==========================================
# 9. Start Dockge
# ==========================================
print_section "Step 9: Starting Dockge"
cd /opt/dockge
docker compose up -d
print_success "Dockge container started"
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
echo "3. Access Dockge at: http://$(hostname -I | awk '{print $1}'):5001"
echo ""
echo -e "${YELLOW}Installed Services:${NC}"
echo "✓ NFS Client"
echo "✓ Docker & Docker Compose"
echo "✓ Dockge (Docker Management)"
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
