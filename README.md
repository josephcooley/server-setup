# Hermes Server Setup Scripts

Scripts for setting up an Ubuntu server with Docker container management, a Samba share, Hermes configuration, and NFS mounts.

## `hermes-setup.sh` - Hermes Server Setup

This script will install Docker, downloads your selected stack set (`hermesstacks/` or `mediastacks/`) into `/opt/dockge/stacks/`, starts Dockge, configures the Samba share used by Hermes at `/opt/dockge/stacks/hermes/workspace`, creates the Samba user, and writes the Samba share configuration for Hermes-related access.

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
- `STACKS_DIR`: Dockge stacks path, default `/opt/dockge/stacks`

## `install-mediastacks.sh` - Media Stacks Only

This script downloads the `mediastacks/` contents from this repository directly into `/opt/dockge/stacks/` so the stack files are available at the root of Dockge's stacks directory instead of inside a `mediastacks` subfolder.

### Usage

```bash
curl -O https://raw.githubusercontent.com/josephcooley/server-setup/main/install-mediastacks.sh
chmod +x install-mediastacks.sh
sudo ./install-mediastacks.sh
```

## `install-hermesstacks.sh` - General Stacks Only

This script downloads the `hermesstacks/` contents from this repository directly into `/opt/dockge/stacks/` so the standard Dockge stack files are available at the root of the stacks directory.

### Usage

```bash
curl -O https://raw.githubusercontent.com/josephcooley/server-setup/main/install-hermesstacks.sh
chmod +x install-hermesstacks.sh
sudo ./install-hermesstacks.sh
```

## `dockge-setup.sh` - Dockge Only

This script installs Docker, creates the Dockge directories, writes the Dockge compose file, starts Dockge, and syncs the stack files from this repository. It does not configure Samba, Hermes, or NFS mounts.

### Usage

```bash
curl -O https://raw.githubusercontent.com/josephcooley/server-setup/main/dockge-setup.sh
chmod +x dockge-setup.sh
sudo ./dockge-setup.sh
```

## `mounts.sh` - NFS Mounts Only

This script only installs the NFS client, creates the local mount points, updates `/etc/fstab`, and mounts the NFS shares. It does not install Docker, Dockge, Samba, or Hermes.

### Usage

```bash
curl -O https://raw.githubusercontent.com/josephcooley/server-setup/main/mounts.sh
chmod +x mounts.sh
sudo ./mounts.sh
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

## `transfer-hermes.sh` - Hermes Stack Migration

This script migrates a Hermes Docker Compose stack (compose file plus bind-mounted data) from the current machine to a remote machine over SSH.

### Usage

Download and run:

```bash
curl -O https://raw.githubusercontent.com/josephcooley/server-setup/main/transfer-hermes.sh
chmod +x transfer-hermes.sh
```

Dry run (preview only, no stop/copy/start actions):
```bash
sudo ./transfer-hermes.sh --dry-run
```
Real run stop/copy/start actions:
```bash
sudo ./transfer-hermes.sh
```
sudo ./transfer-hermes.sh
### What It Prompts For

At startup, it prompts for:

- Remote host IP/hostname (with a default value)

For SSH authentication, the script now uses normal interactive SSH/rsync prompts. If you are using password auth, SSH may ask for your password multiple times during a run unless SSH multiplexing is enabled.

### Default Configuration Variables

You can edit the configuration block in the script or export environment variables before running:

- `LOCAL_STACK_DIR` (default: `/opt/dockge/stacks/hermes`)
- `REMOTE_USER` (default: `joseph`)
- `REMOTE_HOST` (default: `192.168.1.1X`)
- `REMOTE_STACK_DIR` (default: `/opt/dockge/stacks/hermes`)
- `SSH_KEY` (default: empty)
- `COMPOSE_FILE` (default: `compose.yaml`)

### Migration Flow

The script performs these steps:

1. Validates local stack path and compose file.
2. Validates SSH connectivity and remote Docker availability.
3. Detects known DB containers (Postgres/MySQL/MariaDB) and optionally creates a logical DB dump.
4. Stops the local stack (`docker compose down`) unless running with `--dry-run`.
5. Transfers stack files with `rsync` (excluding `.git`).
6. Starts the stack on the remote host (`docker compose up -d`).
7. Shows remote container status (`docker compose ps`).

### Notes

- Built for bind mounts, not named Docker volumes.
- Leaves the source stack stopped (not deleted) after migration as a safety net.

## Author

Joseph M. Cooley

**Last Updated:** June 2026
