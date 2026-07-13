# Hermes Server Setup Scripts

Scripts for setting up an Ubuntu server with Docker container management, a Samba share, Hermes configuration, and NFS mounts.

## `server-setup.sh` - Hermes Server Setup

This script installs Docker, starts Dockge, configures the Samba share used by Hermes at `/opt/stacks/hermes/workspace`, creates the Samba user, and writes the Samba share configuration for Hermes-related access.

It does not download stack files. Use `install-stacks.sh` for stack bootstrap files and `hermes-config.sh` for Hermes config tasks.

### Usage

```bash
curl -O https://raw.githubusercontent.com/josephcooley/server-setup/main/server-setup.sh && chmod +x server-setup.sh && sudo ./server-setup.sh
```

## `install-stacks.sh` - Stack Bootstrap Downloader

This script downloads only `compose.yaml` and `.env` files from selected stack folders (`hermesstacks`, `mediastacks`, or both) into `/opt/stacks`.

When run, it prompts for:

- Stack source (`hermesstacks`, `mediastacks`, or `both`)
- File handling mode:
	- Only download new files (skip existing)
	- Overwrite existing files

### Usage

```bash
curl -O https://raw.githubusercontent.com/josephcooley/server-setup/main/install-stacks.sh && chmod +x install-stacks.sh && sudo ./install-stacks.sh
```

Current stack folders in this repo:

- `hermesstacks`: `code-server`, `dashboards`, `dockhand`, `hermes`, `homeassistant`, `homepage-hermes`, `llama-cpp`, `manifest`, `omniroute`, `paperless-ngx`, `sure`, `tandoor`
- `mediastacks`: `arrstack`, `book-stack`, `grimmory`, `homepage-media`, `qbittorrent`

## `hermes-config.sh` - Post-Stacks-Up Tasks

Run this script after your Docker Compose stacks are started. It currently includes:

- Step 1: Hermes dashboard setup (prompts for password, generates hash in container, updates `/opt/stacks/hermes/agent/config.yaml`)
- Step 2: Optionally downloads files from the repo `hermesconfig/` folder into `/opt/stacks/hermes/` and overwrites existing files

### Usage

```bash
curl -O https://raw.githubusercontent.com/josephcooley/server-setup/main/hermes-config.sh && chmod +x hermes-config.sh && sudo ./hermes-config.sh
```

## Configuration

Edit the configuration block at the top of `server-setup.sh` before running if you want to change any defaults:

- `SHARE_DIR`: Samba share path, default `/opt/stacks/hermes/workspace`
- `SHARE_NAME`: SMB share name, default `workspace`
- `SAMBA_PASSWORD`: If blank, you will be prompted
- `SMB_HOSTS_ALLOW`: Allowed LAN ranges for SMB access
- `DOCKGE_PORT`: Dockge port, default `3099`
- `STACKS_DIR`: Stacks path, default `/opt/stacks`

## Recommended Run Order

1. Run `server-setup.sh` to install Docker, Dockge, and Samba.
2. Run `install-stacks.sh` to pull `compose.yaml` and `.env` files into `/opt/stacks/`.
3. Start the stacks from Dockge or with `docker compose` in each stack directory.
4. Run `hermes-config.sh` for Hermes dashboard auth setup and optional `hermesconfig/` file download.


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
| Stack bootstrap (`install-stacks.sh`) | Downloads only `compose.yaml` and `.env` files from selected stack families |
| Post-stacks tasks (`hermes-config.sh`) | Sets Hermes dashboard auth and optionally downloads repo `hermesconfig/` files into `/opt/stacks/hermes/` |
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

If you change the Hermes Samba credentials or share path, update `server-setup.sh` before rerunning it.

## Requirements

- Fresh Ubuntu 20.04 LTS or later
- Root/sudo access
- Network access for package installation


## Author

Joseph M. Cooley

**Last Updated:** July 2026
