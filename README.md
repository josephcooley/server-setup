# Hermes Server Setup Scripts

Scripts for setting up an Ubuntu server with Docker container management, a Samba share, Hermes configuration, and NFS mounts.

## `server-setup.sh` - Hermes Server Setup

This script installs Docker, starts Dockhand, configures the Samba share used by Hermes at `/opt/stacks/hermes/workspace`, creates the Samba user, and writes the Samba share configuration for Hermes-related access.

It does not download stack files. Use `install-stacks.sh` and `post-stacks-up.sh` for stack content sync.

### Usage

```bash
curl -O https://raw.githubusercontent.com/josephcooley/server-setup/main/server-setup.sh && chmod +x server-setup.sh && sudo server-setup.sh
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

## `post-stacks-up.sh` - Post-Stacks-Up Tasks

Run this script after your Docker Compose stacks are started. It currently includes:

- Step 1: Hermes dashboard setup (prompts for password, generates hash in container, updates `/opt/stacks/hermes/agent/config.yaml`)
- Step 2: Downloads non-`.env` and non-`compose.yaml` files from selected stack folders (`hermesstacks`, `mediastacks`, or both) into `/opt/stacks/` and overwrites existing files

### Usage

```bash
curl -O https://raw.githubusercontent.com/josephcooley/server-setup/main/post-stacks-up.sh && chmod +x post-stacks-up.sh && sudo ./post-stacks-up.sh
```

## Configuration

Edit the configuration block at the top of `server-setup.sh` before running if you want to change any defaults:

- `SHARE_DIR`: Samba share path, default `/opt/stacks/hermes/workspace`
- `SHARE_NAME`: SMB share name, default `workspace`
- `SAMBA_PASSWORD`: If blank, you will be prompted
- `SMB_HOSTS_ALLOW`: Allowed LAN ranges for SMB access
- `DOCKHAND_PORT`: Dockhand port, default `3099`
- `STACKS_DIR`: Stacks path, default `/opt/stacks`

## Recommended Run Order

1. Run `server-setup.sh` to install Docker, Dockhand, and Samba.
2. Run `install-stacks.sh` to pull `compose.yaml` and `.env` files into `/opt/stacks/`.
3. Start the stacks from Dockhand or with `docker compose` in each stack directory.
4. Run `post-stacks-up.sh` for Hermes dashboard auth setup and non-`.env`/non-`compose.yaml` file sync.


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
| Dockhand | Web UI for Docker management |
| Samba | Windows-compatible file sharing |
| Hermes-related Samba setup | Samba share and user configuration for Hermes |
| Stack bootstrap (`install-stacks.sh`) | Downloads only `compose.yaml` and `.env` files from selected stack families |
| Post-stacks sync (`post-stacks-up.sh`) | Sets Hermes dashboard auth and syncs non-`.env`/non-`compose.yaml` files with overwrite |
| NFS client | Mount support for `mounts.sh` |

## Troubleshooting

### Dockhand

Check the container and logs:

```bash
docker ps
docker logs dockhand
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
