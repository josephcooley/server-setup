# TrueNAS Server Setup Scripts

Collection of modular bash scripts for setting up a Ubuntu server with TrueNAS storage mounts and Docker container management.

## Available Scripts

### 1. `dockge-install.sh` - Docker & Dockge Installation

**What it does:**
- Updates system packages
- Installs Docker CE with Docker Compose
- Deploys Dockge web UI for Docker container management

**When to use:** 
- Just want Docker and Dockge on your server
- Skip NFS mount configuration

**Usage:**
```bash
curl -O https://raw.githubusercontent.com/josephcooley/server-setup/main/dockge-install.sh
chmod +x dockge-install.sh
sudo ./dockge-install.sh
```

**Access Dockge:**
Open browser to `http://<server-ip>:5001`

---

### 2. `mounts.sh` - NFS Mounts Setup

**What it does:**
- Creates truenas user and group (UID/GID 3000)
- Installs NFS utilities
- Mounts 5 NAS shares with proper TCP configuration:
  - `/mnt/books` → `/mnt/Storage/Books`
  - `/mnt/documents` → `/mnt/Storage/Documents`
  - `/mnt/downloads` → `/mnt/Storage/Downloads`
  - `/mnt/tv` → `/mnt/Storage/TV`
  - `/mnt/movies` → `/mnt/Storage/Movies`
- Configures persistent mounts in `/etc/fstab`
- Sets up NFSv4 UID/GID mapping (idmapd)

**When to use:**
- Need to mount TrueNAS storage on your server
- Setting up a new truenas user account

**Usage:**
```bash
curl -O https://raw.githubusercontent.com/josephcooley/server-setup/main/mounts.sh
chmod +x mounts.sh
sudo ./mounts.sh
```

**Verify mounts:**
```bash
df -h | grep 192.168.1.100
ls /mnt/books
```

---

### 3. `setup-server.sh` - Complete Server Setup (Legacy)

**What it does:**
Combines all functionality from dockge-install.sh and mounts.sh in one script.

**When to use:**
- Automated one-shot setup of entire server
- All components needed at once

**Usage:**
```bash
curl -O https://raw.githubusercontent.com/josephcooley/server-setup/main/setup-server.sh
chmod +x setup-server.sh
sudo ./setup-server.sh
```

---

## Quick Start Guide

### Option A: Complete Setup
```bash
sudo ./setup-server.sh
```

### Option B: Step-by-Step
```bash
# Step 1: Install Docker & Dockge
sudo ./dockge-install.sh

# Step 2: Setup NFS Mounts
sudo ./mounts.sh
```

---

## Configuration

### Default Settings

**NFS Configuration (mounts.sh):**
- NAS IP: `192.168.1.100`
- NAS Domain: `truenas.local`
- Truenas User UID: `3000`
- Truenas User GID: `3000`

**Docker Configuration (dockge-install.sh):**
- Dockge Port: `5001`
- Install Path: `/opt/dockge`
- Stacks Path: `/opt/stacks`

**To customize:** Edit the `Configuration` section at the top of each script before running.

---

## Troubleshooting

### NFS Mounts Failing

Check network connectivity:
```bash
ping 192.168.1.100
showmount -e 192.168.1.100
```

Manual mount test:
```bash
sudo mount -t nfs -o vers=3,proto=tcp,nolock 192.168.1.100:/mnt/Storage/Books /mnt/books
```

### Docker/Dockge Issues

Check Docker status:
```bash
docker ps
docker logs dockge
```

Access system logs:
```bash
journalctl -xu docker.service
```

### Mount Permissions

If you get "Permission denied":
```bash
sudo chmod 755 /mnt/books /mnt/documents /mnt/downloads /mnt/tv /mnt/movies
```

---

## Backups

The `mounts.sh` script automatically backs up `/etc/fstab`:
```bash
/etc/fstab.backup
```

Restore if needed:
```bash
sudo cp /etc/fstab.backup /etc/fstab
sudo systemctl daemon-reload
```

---

## Security Considerations

- Scripts require root access via `sudo`
- Dockge UI should be behind authentication/firewall in production
- NFS shares transmitted unencrypted (configure on TrueNAS if needed)
- Consider restricting NFS access by IP in TrueNAS settings

---

## Requirements

- Fresh Ubuntu 20.04 LTS or later
- Root/sudo access
- Network access to TrueNAS (default: `192.168.1.100`)
- TrueNAS with NFS exports configured at `/mnt/Storage/`

---

## What Gets Installed

| Component | Script | Purpose |
|-----------|--------|---------|
| Docker CE | dockge-install.sh | Container runtime |
| Docker Compose | dockge-install.sh | Multi-container orchestration |
| Dockge | dockge-install.sh | Web UI for Docker management |
| NFS Utils | mounts.sh | NFS client utilities |
| Truenas User | mounts.sh | Dedicated service account |
| Mount Points | mounts.sh | `/mnt/books`, `/mnt/documents`, etc. |

---

## Manual Commands Reference

If you prefer manual configuration:

### Create Truenas User
```bash
sudo groupadd -g 3000 truenas
sudo useradd -u 3000 -g truenas -m -s /bin/bash truenas
sudo usermod -aG sudo truenas
```

### Mount NFS Manually
```bash
sudo mount -t nfs -o vers=3,proto=tcp,nolock 192.168.1.100:/mnt/Storage/Books /mnt/books
```

### Install Docker
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
```

### Start Dockge
```bash
docker run -d \
  --name dockge \
  -p 5001:5001 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  louislam/dockge:latest
```

---

## License

MIT License - Feel free to modify for your needs

## Author

Joseph M. Cooley

---

**Last Updated:** June 2026  
**Tested On:** Ubuntu 22.04 LTS, Ubuntu 24.04 LTS
