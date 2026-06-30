# Hermes Server Setup Scripts

Scripts for setting up an Ubuntu server with Docker container management, a Samba share, Hermes configuration, and NFS mounts.

## `hermes-setup.sh` - Hermes Server Setup

This script installs Docker and Dockge, configures the Samba share used by Hermes at `/opt/dockge/stacks/hermes/workspace`, creates the Samba user, and writes the Samba share configuration for Hermes-related access.

### Usage

```bash
curl -O https://raw.githubusercontent.com/josephcooley/server-setup/main/hermes-setup.sh
chmod +x hermes-setup.sh
sudo ./hermes-setup.sh
```

## Configuration

Edit the configuration block at the top of `hermes-setup.sh` before running if you want to change any defaults:

- `SHARE_DIR`: Samba share path, default `/opt/dockge/stacks/hermes/workspace`
- `SHARE_NAME`: SMB share name, default `workspace`
- `SAMBA_USERNAME`: Samba login name, default `joseph`
- `SMB_HOSTS_ALLOW`: Allowed LAN ranges for SMB access
- `DOCKGE_PORT`: Dockge port, default `5001`
- `DOCKGE_DIR`: Dockge install path, default `/opt/dockge`
- `STACKS_DIR`: Dockge stacks path, default `/opt/stacks`

## `dockge-setup.sh` - Dockge Only

This script installs Docker, creates the Dockge directories, writes the Dockge compose file, starts Dockge, and syncs the stack files from this repository. It does not configure Samba, Hermes, or NFS mounts.

## `mounts.sh` - NFS Mounts Only

This script only installs the NFS client, creates the local mount points, updates `/etc/fstab`, and mounts the NFS shares. It does not install Docker, Dockge, Samba, or Hermes.

## What Gets Installed

| Component | Purpose |
| --- | --- |
| Docker CE | Container runtime |
| Docker Compose plugin | Multi-container orchestration |
| Dockge | Web UI for Docker management |
| Samba | Windows-compatible file sharing |
| Hermes-related Samba setup | Samba share and user configuration for Hermes |
| NFS client | Mount support for `mounts.sh` |

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

### Hermes Setup

If you change the Hermes Samba credentials or share path, update `hermes-setup.sh` before rerunning it.

## Requirements

- Fresh Ubuntu 20.04 LTS or later
- Root/sudo access
- Network access for package installation
- Hermes already installed if you want Telegram integration configured automatically

## Author

Joseph M. Cooley

**Last Updated:** June 2026
