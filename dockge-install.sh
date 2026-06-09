#!/bin/bash

################################################################################
# Dockge Installation Script
# Installs Docker and Dockge container management UI on Ubuntu 20+
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
# Network Configuration - Static to Dynamic IP
################################################################################

convert_static_to_dynamic() {
    log_info "Checking network configuration..."
    
    if [ ! -d /etc/netplan ]; then
        log_error "Netplan not found. This script requires Ubuntu 20.04 or later."
        exit 1
    fi
    
    log_debug "Found Netplan configuration"
    
    local static_config_found=false
    
    for config_file in /etc/netplan/*.yaml /etc/netplan/*.yml; do
        if [ -f "$config_file" ]; then
            # Check if file contains static IP configuration
            if grep -q "addresses:" "$config_file" && ! grep -q "dhcp4: true" "$config_file"; then
                log_info "✓ Found static IP configuration in: $config_file"
                static_config_found=true
                
                # Backup the original config
                cp "$config_file" "${config_file}.backup"
                log_info "  Backed up to: ${config_file}.backup"
                
                # Create new dynamic IP config
                log_info "  Converting to dynamic IP (DHCP)..."
                
                # Extract interface name from config
                local interface=$(grep -oP '^\s*\K[a-zA-Z0-9-]+(?=:)' "$config_file" | grep -v "network\|version\|renderer" | head -1)
                
                if [ -n "$interface" ]; then
                    # Create dynamic IP configuration
                    cat > "$config_file" << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $interface:
      dhcp4: true
EOF
                    log_info "  Created new DHCP configuration for interface: $interface"
                else
                    log_error "  Could not determine interface name"
                    return 1
                fi
            fi
        fi
    done
    
    if [ "$static_config_found" = true ]; then
        # Apply the new configuration
        log_info "Applying network configuration..."
        netplan apply
        log_info "✓ Network configuration applied"
        
        # Give it a moment to acquire IP
        sleep 2
        
        # Verify DHCP
        log_info "Verifying dynamic IP assignment..."
        local interface=$(ip -4 route ls | grep default | grep -oP '(?<=dev\s)\S+' | head -1)
        if [ -n "$interface" ]; then
            local current_ip=$(ip -4 addr show "$interface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
            log_info "✓ Interface $interface has IP: $current_ip (DHCP)"
        fi
    else
        log_info "✓ No static IP configuration found (already using DHCP)"
    fi
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
    echo -e "${GREEN}Installation Complete!${NC}"
    echo -e "${GREEN}================================${NC}"
    echo ""
    echo "Dockge Configuration:"
    echo "  Dockge URL: http://localhost:$DOCKGE_PORT"
    echo "  Install Path: $DOCKGE_PATH"
    echo "  Stacks Path: $STACKS_PATH"
    echo ""
    echo "Network Configuration:"
    local current_ip=$(hostname -I | awk '{print $1}')
    echo "  Current IP: $current_ip (DHCP)"
    echo ""
    echo "Docker Status:"
    docker ps --filter "name=dockge" || echo "  (Dockge may not be running)"
    echo ""
    echo "Next Steps:"
    echo "  1. Access Dockge: http://<server-ip>:$DOCKGE_PORT"
    echo "  2. Manage Docker containers via web UI"
    echo ""
}

################################################################################
# Main Execution
################################################################################

main() {
    log_info "Starting Docker and Dockge installation..."
    
    check_root
    
    # Convert static IP to dynamic (DHCP) first
    convert_static_to_dynamic
    
    update_system
    install_docker
    install_dockge
    
    print_summary
    
    log_info "Installation completed!"
}

# Run main function
main "$@"
