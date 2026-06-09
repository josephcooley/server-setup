#!/bin/bash

################################################################################
# Dockge Installation Script
# Installs Docker and Dockge container management UI on Ubuntu
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
    
    update_system
    install_docker
    install_dockge
    
    print_summary
    
    log_info "Installation completed!"
}

# Run main function
main "$@"
