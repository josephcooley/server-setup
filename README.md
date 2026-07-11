# Hermes Server Setup Scripts

Scripts for setting up an Ubuntu server with Docker container management, a Samba share, Hermes configuration, and NFS mounts.

## `server-setup.sh` - Hermes Server Setup

This script installs Docker, starts Dockhand, configures the Samba share used by Hermes at `/opt/stacks/hermes/workspace`, creates the Samba user, and writes the Samba share configuration for Hermes-related access.

It does not download stack files. Use `install-stacks.sh` for stack folder downloads and `hermes-after-launch.sh` for `hermesconfig/` sync.

### Usage

```bash
curl -O https://raw.githubusercontent.com/josephcooley/server-setup/main/server-setup.sh && chmod +x server-setup.sh && sudo server-setup.sh
```

## `post-startup.sh` - Post-Install / Post-Start Tasks

Run this script after your Docker Compose stacks are started. It currently includes:

- Step 1: Hermes dashboard setup (prompts for password, generates hash in container, updates `/opt/stacks/hermes/agent/config.yaml`)
- Step 2: Downloads `hermesconfig/` files into `/opt/stacks/hermes/agent/` (skips existing files)

### Usage

```bash
curl -O https://raw.githubusercontent.com/josephcooley/server-setup/main/post-startup.sh && chmod +x post-startup.sh && sudo ./post-startup.sh
```

## `uipassword.sh` - Hermes Dashboard Password Setup

Run this script to configure Hermes dashboard basic auth only. It prompts for a dashboard password, generates the password hash in the running `hermes-agent` container, prepends the dashboard auth block to `/opt/stacks/hermes/agent/config.yaml`, and restarts Hermes.

### Usage

```bash
curl -O https://raw.githubusercontent.com/josephcooley/server-setup/main/uipassword.sh && chmod +x uipassword.sh && sudo ./uipassword.sh
```

## Configuration

Edit the configuration block at the top of `server-setup.sh` before running if you want to change any defaults:

- `SHARE_DIR`: Samba share path, default `/opt/stacks/hermes/workspace`
- `SHARE_NAME`: SMB share name, default `workspace`
- `SAMBA_PASSWORD`: If blank, you will be prompted
- `SMB_HOSTS_ALLOW`: Allowed LAN ranges for SMB access
- `DOCKHAND_PORT`: Dockhand port, default `3099`
- `STACKS_DIR`: Stacks path, default `/opt/stacks`

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

## `hermes-after-launch.sh` - Hermes Config Downloader

This script downloads `hermesconfig/` into `/opt/stacks/hermes/agent/`.

### Usage

```bash
curl -O https://raw.githubusercontent.com/josephcooley/server-setup/main/hermes-after-launch.sh && chmod +x hermes-after-launch.sh && sudo ./hermes-after-launch.sh
```

Existing destination files are skipped by default.

## Recommended Run Order

1. Run `server-setup.sh` to install Docker, Dockhand, and Samba.
2. Run `install-stacks.sh` to download stack files into `/opt/stacks/`.
3. Run `hermes-after-launch.sh` to download `hermesconfig/` into `/opt/stacks/hermes/agent/`.
4. Start the stacks from Dockhand or with `docker compose` in each stack directory.


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
| Stack downloader (`install-stacks.sh`) | Downloads `hermesstacks/` and/or `mediastacks/` |
| Hermes config downloader (`hermes-after-launch.sh`) | Downloads `hermesconfig/` into `/opt/stacks/hermes/agent/` |
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
