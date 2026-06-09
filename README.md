# TrueNAS Server Setup Script

An automated bash script to set up a fresh Ubuntu Linux server with NFS mounts to TrueNAS storage, Docker, and Dockge container management UI.

## Overview

This script automates the entire server setup process, eliminating manual configuration steps. It configures:

- **System**: Updates, user/group management
- **Storage**: NFS mounts to TrueNAS with persistent configuration
- **Containers**: Docker installation and Dockge deployment
- **UID/GID Mapping**: NFSv4 domain configuration for proper file permissions

## Prerequisites

- Fresh Ubuntu Linux server (20.04+)
- Root access (script requires `sudo`)
- Network access to TrueNAS storage (default: `192.168.1.100`)
- TrueNAS configured with NFS exports at `/mnt/Storage/`

## Quick Start

### 1. Download the Script

```bash
curl -O https://raw.githubusercontent.com/josephcooley/server-setup/main/setup-server.sh
chmod +x setup-server.sh
```

### 2. Run the Setup

```bash
sudo ./setup-server.sh
```

The script runs automatically and will:
- Prompt for confirmations if needed
- Create backup of `/etc/fstab` before modifications
- Provide a summary at completion

## Configuration

Edit these variables in the script to match your environment:

```bash
NAS_IP="192.168.1.100"           # TrueNAS IP address
NAS_DOMAIN="truenas.local"       # NFSv4 domain
TRUENAS_UID=3000                 # Unix UID for truenas user
TRUENAS_GID=3000                 # Unix GID for truenas group
TRUENAS_USER="truenas"           # Username
DOCKGE_PORT=5001                 # Dockge web UI port
```

## What Gets Installed

### System Updates
```bash
apt update && apt upgrade -y
```

### User & Group
- Creates `truenas` user and group (UID/GID 3000)
- Adds `truenas` to sudoers for administrative tasks

### NFS Mounts
Mounts the following shares from TrueNAS:

| Mount Point | NAS Share | Purpose |
|-----------|-----------|---------|
| `/mnt/books` | `/mnt/Storage/Books` | Book library |
| `/mnt/documents` | `/mnt/Storage/Documents` | Documents |
| `/mnt/downloads` | `/mnt/Storage/Downloads` | Download directory |
| `/mnt/tv` | `/mnt/Storage/TV` | TV shows |
| `/mnt/movies` | `/mnt/Storage/Movies` | Movies |

### NFSv4 UID/GID Mapping
Configures `/etc/idmapd.conf` for proper permission handling:
- Maps TrueNAS UIDs to local UIDs
- Ensures consistent file ownership across systems

### Docker & Dockge
- **Docker CE**: Latest stable version with Docker Compose
- **Dockge**: Web UI for Docker container management
  - Accessible at `http://<server-ip>:5001`
  - Auto-restart enabled
  - Persistent stack storage at `/opt/dockge/stacks`

## Execution Flow

```
1. Check root privileges
2. Update system packages
3. Create truenas user/group
4. Install Docker
5. Install and mount NFS shares (temporary test mount)
6. Configure NFSv4 UID/GID mapping
7. Set up persistent mounts in /etc/fstab
8. Deploy Dockge container
9. Display completion summary
```

## Output Example

```
[INFO] Starting server setup...
[INFO] Updating system packages...
[INFO] System update complete
[INFO] Setting up TrueNAS user and group...
[INFO] Created group: truenas (GID: 3000)
[INFO] Created user: truenas (UID: 3000)
[INFO] Added truenas to sudoers
[INFO] Installing Docker...
[INFO] Docker installed and enabled
[INFO] Setting up NFS mounts...
[INFO] Installed nfs-common
[INFO] Creating mount directories...
[INFO] Temporarily mounting NFS shares for testing...
[INFO] Successfully mounted: 192.168.1.100:/mnt/Storage/Books
[INFO] NFS mounts verified
[INFO] Configuring NFSv4 UID/GID mapping...
[INFO] Configured /etc/idmapd.conf
[INFO] Restarted nfs-idmapd service
[INFO] Configuring persistent NFS mounts in /etc/fstab...
[INFO] Backed up /etc/fstab to /etc/fstab.backup
[INFO] Added NFS mounts to /etc/fstab
[INFO] Reloaded and applied mounts
[INFO] Installing Dockge...
[INFO] Started Dockge container
[INFO] Setup completed successfully!

================================
Server Setup Complete!
================================

Configuration Summary:
  NAS IP: 192.168.1.100
  NAS Domain: truenas.local
  TrueNAS User: truenas (UID: 3000)
  Dockge URL: http://localhost:5001

Next Steps:
  1. Switch to the new user: su - truenas
  2. Verify NFS mounts: df -h | grep 192.168.1.100
  3. Access Dockge: http://<server-ip>:5001
```

## Post-Setup Verification

### Verify NFS Mounts

```bash
df -h | grep 192.168.1.100
```

Expected output:
```
192.168.1.100:/mnt/Storage/Books      10G  5.2G  4.8G  52% /mnt/books
192.168.1.100:/mnt/Storage/Documents  20G  10G   10G  50% /mnt/documents
192.168.1.100:/mnt/Storage/Downloads  50G  25G   25G  50% /mnt/downloads
192.168.1.100:/mnt/Storage/TV        100G  80G   20G  80% /mnt/tv
192.168.1.100:/mnt/Storage/Movies    100G  90G   10G  90% /mnt/movies
```

### Access Dockge

Open your browser and navigate to:
```
http://<server-ip>:5001
```

### Check Docker Status

```bash
docker ps --filter "name=dockge"
```

### Verify Permanent Mounts

```bash
cat /etc/fstab | grep 192.168.1.100
```

### Switch to Truenas User

```bash
su - truenas
```

## Troubleshooting

### NFS Mount Fails

**Problem**: Mounts fail or permissions are incorrect

**Solution**:
1. Verify TrueNAS NFS exports are active
2. Check firewall allows NFS (ports 111, 2049, 20048)
3. Verify NFSv4 domain on TrueNAS matches script (`truenas.local`)
4. Check `/etc/idmapd.conf` configuration

```bash
# Debug NFS
showmount -e 192.168.1.100

# Restart NFS idmapd
sudo systemctl restart nfs-idmapd
```

### Docker Fails to Start

**Problem**: Docker installation or startup fails

**Solution**:
1. Ensure Ubuntu is up-to-date: `sudo apt update && sudo apt upgrade -y`
2. Verify internet connectivity
3. Check disk space: `df -h`
4. Review Docker installation logs

### Dockge Not Accessible

**Problem**: Cannot reach Dockge UI on port 5001

**Solution**:
1. Verify container is running: `docker ps | grep dockge`
2. Check port availability: `sudo netstat -tlnp | grep 5001`
3. Check firewall: `sudo ufw status`
4. Restart container: `docker restart dockge`

## Backups

The script creates a backup of `/etc/fstab` before making changes:

```bash
/etc/fstab.backup
```

Restore if needed:
```bash
sudo cp /etc/fstab.backup /etc/fstab
sudo systemctl daemon-reload
```

## Security Considerations

- Script requires root privileges
- Creates new user account with sudo access
- NFS shares are mounted without encryption (configure on TrueNAS if needed)
- Dockge UI should be behind authentication/firewall in production
- Consider restricting NFS access by IP in TrueNAS settings

## Manual Steps Reference

If you prefer to configure manually or need to troubleshoot, here are the key commands:

### Create User
```bash
sudo groupadd -g 3000 truenas
sudo useradd -u 3000 -g truenas -m -s /bin/bash truenas
sudo usermod -aG sudo truenas
```

### Mount NFS (Temporary)
```bash
sudo mount -t nfs 192.168.1.100:/mnt/Storage/Books /mnt/books
```

### Configure Persistent Mounts
```bash
sudo nano /etc/fstab
# Add: 192.168.1.100:/mnt/Storage/Books /mnt/books nfs defaults,_netdev 0 0
sudo mount -a
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

## Support & Issues

For issues or questions:
1. Check troubleshooting section above
2. Verify prerequisites are met
3. Review script logs in terminal output
4. Check system logs: `sudo journalctl -xe`

## License

MIT License - Feel free to modify for your needs

## Author

Joseph M. Cooley

---

**Last Updated**: June 2026
**Tested On**: Ubuntu 22.04 LTS, Ubuntu 24.04 LTS
