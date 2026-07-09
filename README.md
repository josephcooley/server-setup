# Hermes Server Setup Scripts

Scripts for setting up an Ubuntu server with Docker container management, a Samba share, Hermes configuration, and NFS mounts.

## `hermes-setup.sh` - Hermes Server Setup

This script will install Docker, downloads your selected stack set (`hermesstacks/` or `mediastacks/`) into `/opt/stacks/`, starts Dockge, configures the Samba share used by Hermes at `/opt/stacks/hermes/workspace`, creates the Samba user, and writes the Samba share configuration for Hermes-related access.

### Usage

```bash
curl -O https://raw.githubusercontent.com/josephcooley/server-setup/main/hermes-setup.sh && chmod +x hermes-setup.sh && sudo hermes-setup.sh
```

## `post-startup.sh` - Post-Install / Post-Start Tasks

Run this script after your Docker Compose stacks are started. It currently includes:

- Step 1: Hermes dashboard setup (prompts for password, generates hash in container, updates `/opt/stacks/hermes/agent/config.yaml`)
- Step 2: Generates and populates secrets in stack `.env` files:
	- `manifest` -> `BETTER_AUTH_SECRET`
	- `sure` -> `SECRET_KEY_BASE`

### Usage

```bash
curl -O https://raw.githubusercontent.com/josephcooley/server-setup/main/post-startup.sh && chmod +x post-startup.sh && sudo ./post-startup.sh
```

## Configuration

Edit the configuration block at the top of `hermes-setup.sh` before running if you want to change any defaults:

- `SHARE_DIR`: Samba share path, default `/opt/stacks/hermes/workspace`
- `SHARE_NAME`: SMB share name, default `workspace`
- `SAMBA_USERNAME`: Samba login name, default `joseph`
- `SMB_HOSTS_ALLOW`: Allowed LAN ranges for SMB access
- `DOCKGE_PORT`: Dockge port, default `5001`
- `DOCKGE_DIR`: Dockge install path, default `/opt/dockge`
- `STACKS_DIR`: Dockge stacks path, default `/opt/stacks`

## `install-stacks.sh` - Stack Downloader

This script downloads selected stack contents from `hermesstacks/`, `mediastacks/`, or both into `/opt/stacks/`.

### Usage

```bash
curl -O https://raw.githubusercontent.com/josephcooley/server-setup/main/install-stacks.sh && chmod +x install-stacks.sh && sudo ./install-stacks.sh
```

When run, it prompts you to choose:

- `hermesstacks`
- `mediastacks`
- `both`

Existing destination files are skipped by default.


## `mounts.sh` - NFS Mounts Only

This script only installs the NFS client, creates the local mount points, updates `/etc/fstab`, and mounts the NFS shares. It does not install Docker, Dockge, Samba, or Hermes.

### Usage

```bash
curl -O https://raw.githubusercontent.com/josephcooley/server-setup/main/mounts.sh && chmod +x mounts.sh && sudo ./mounts.sh
```

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


## Author

Joseph M. Cooley

**Last Updated:** June 2026
