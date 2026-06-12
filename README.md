# TrueNAS Server Setup Scripts

Script for setting up a Ubuntu server with TrueNAS storage mounts and Docker container management.

### `setup-server.sh` - Complete Server Setup (Legacy)

**What it does:**
Combines all functionality from mount NFS shares and install docker and dockge

**Usage:**
```bash
curl -O https://raw.githubusercontent.com/josephcooley/server-setup/main/setup-server.sh
chmod +x setup-server.sh
sudo ./setup-server.sh
```

### `dockge-setup.sh` - Complete Server Setup (Legacy)

**What it does:**
Combines all functionality from mount NFS shares and install docker and dockge

**Usage:**
```bash
curl -O https://raw.githubusercontent.com/josephcooley/server-setup/main/dockge-setup.sh
chmod +x dockge-setup.sh
sudo ./dockge-setup.sh
```
---

## Quick Start Guide

### Setup
```bash
sudo ./setup-server.sh
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

## Requirements

- Fresh Ubuntu 20.04 LTS or later
- Root/sudo access
- Network access to TrueNAS (default: `192.168.1.100`)
- TrueNAS with NFS exports configured at `/mnt/Storage/`

---

## What Gets Installed

| Component  | Purpose |
|-----------|---------|
| Docker CE |  Container runtime |
| Docker Compose | Multi-container orchestration |
| Dockge |  Web UI for Docker management |
| NFS Utils | NFS client utilities |
| Mount Points |  `/mnt/books`, `/mnt/documents`, etc. |


## License

MIT License - Feel free to modify for your needs

## Author

Joseph M. Cooley

---

**Last Updated:** June 2026  
**Tested On:** Ubuntu 22.04 LTS, Ubuntu 24.04 LTS
