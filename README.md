# TrueNAS Server Setup Scripts

Scripts for setting up an Ubuntu server with Docker container management, a Samba share, and optional Hermes Telegram integration.

## `hermes-setup.sh` - Complete Hermes Server Setup

This script installs Docker and Dockge, configures a Samba share at `/srv/samba/share`, and writes Hermes Telegram settings when Hermes is available.

### Usage

```bash
sudo bash hermes-setup.sh
```

## Configuration

Edit the configuration block at the top of `hermes-setup.sh` before running if you want to change any defaults:

- `SHARE_DIR`: Samba share path, default `/srv/samba/share`
- `SHARE_NAME`: SMB share name, default `hermes-share`
- `SAMBA_USERNAME`: Samba login name, default `Joseph`
- `SMB_HOSTS_ALLOW`: Allowed LAN ranges for SMB access
- `DOCKGE_PORT`: Dockge port, default `5001`
- `DOCKGE_DIR`: Dockge install path, default `/opt/dockge`
- `STACKS_DIR`: Dockge stacks path, default `/opt/stacks`

## What Gets Installed

| Component | Purpose |
| --- | --- |
| Docker CE | Container runtime |
| Docker Compose plugin | Multi-container orchestration |
| Dockge | Web UI for Docker management |
| Samba | Windows-compatible file sharing |
| Hermes CLI integration | Telegram gateway config when Hermes is installed |

## Troubleshooting

### Dockge

Check the container and logs:

```bash
docker ps
docker logs dockge
```

### Samba

Validate the Samba configuration and service status:

```bash
testparm -s
systemctl status smbd
```

### Hermes Telegram Setup

If Telegram is skipped during install, configure it later from the Hermes user's home directory and restart the Hermes gateway.

## Requirements

- Fresh Ubuntu 20.04 LTS or later
- Root/sudo access
- Network access for package installation
- Hermes already installed if you want Telegram integration configured automatically

## Author

Joseph M. Cooley

**Last Updated:** June 2026
