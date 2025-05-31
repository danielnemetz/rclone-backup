# rclone-backup Script

A robust backup script that creates compressed archives of specified directories and uploads them to a remote storage using rclone. The script includes automatic retention management for daily, weekly, and monthly backups.

## Installation

You can install the rclone-backup script using the provided installation script. The installer will guide you through the configuration process and set up everything automatically.

### Quick Install

```bash
curl -sSL https://raw.githubusercontent.com/danielnemetz/rclone-backup/refs/heads/main/install.sh | bash
```

### Manual Install

1. Download the installation script:
```bash
curl -sSL https://raw.githubusercontent.com/danielnemetz/rclone-backup/refs/heads/main/install.sh -o install.sh
chmod +x install.sh
```

2. Run the installer:
```bash
./install.sh
```

The installer will:
- Download and install the rclone-backup script to the appropriate location
- Create a configuration directory at `~/.config/rclone-backup` (or `/etc/rclone-backup` for global config)
- Guide you through the configuration process
- Set up the configuration file with your preferences
- If run as root, you will be offered the option to create a global config at `/etc/rclone-backup/.env` (usable by all users)

The script will be installed to:
- `/usr/local/bin/rclone-backup` if run as root
- `~/.local/bin/rclone-backup` if run as a normal user

## Features

- Creates compressed tar.gz archives of specified directories
- Uploads backups to remote storage using rclone
- Configurable compression level
- Automatic retention management with configurable policies
- Support for backup prefixes
- Automatic cleanup of old backups based on retention policies
- Configurable through environment variables
- Command-line options for flexible usage

## Prerequisites

- `rclone` installed and configured
- `tar` command available
- `gzip` command available
- Bash shell

## Configuration

Create a `.env` file in the appropriate config directory:
- Per-user: `~/.config/rclone-backup/.env`
- Global (optional, for all users): `/etc/rclone-backup/.env`

**Config file selection logic:**
- The script will use the per-user config at `~/.config/rclone-backup/.env` if it exists.
- If not, it will fall back to the global config at `/etc/rclone-backup/.env` (if present).
- You can override the config location by setting the `BACKUP_CONFIG_FILE` environment variable.

**Debugging:**
- When running, the script prints which config file it is using and when it is sourced. This helps with troubleshooting config issues.

```bash
# Required
RCLONE_REMOTE_NAME="your_remote_name"

# Optional (with defaults)
KEEP_DAILY=7        # Number of daily backups to keep
KEEP_WEEKLY=4       # Number of weekly backups to keep
KEEP_MONTHLY=6      # Number of monthly backups to keep
COMPRESSION_LEVEL=6 # Compression level (1-9, where 9 is maximum compression)
```

## Usage

```bash
rclone-backup [OPTIONS] <SOURCE_DIR>
```

### Arguments

- `SOURCE_DIR`: Mandatory. Local directory to back up.

### Options

- `-y, --yes`: Automatically confirm deletion of old backups
- `-r, --remote PATH`: Path on the rclone remote where backups will be stored (default: "./")
- `-p, --prefix PREFIX`: Prefix for the backup archive name
- `-h, --help`: Show help message

### Examples

```bash
# Basic usage
rclone-backup /path/to/source

# With all options
rclone-backup -y -r "remote/path" -p "mydata" /path/to/source

# Using long options
rclone-backup --yes --remote "remote/path" --prefix "mydata" /path/to/source

# Mix of short and long options
rclone-backup -y --remote "remote/path" -p "mydata" /path/to/source
```

## Backup Naming

- Without prefix: `YYYY-MM-DD.tar.gz`
- With prefix: `YYYY-MM-DD_PREFIX.tar.gz`

## Retention Policy

The script maintains three types of backups:

1. **Daily Backups**: Keeps the most recent N daily backups (default: 7)
2. **Weekly Backups**: Keeps one backup per week for N weeks (default: 4)
3. **Monthly Backups**: Keeps one backup per month for N months (default: 6)

The script will automatically delete older backups that don't fall into these categories, after asking for confirmation (unless `-y` or `--yes` is specified).

## Compression

The script uses gzip compression with a configurable compression level (1-9):
- Level 1: Fastest compression, least compressed
- Level 9: Slowest compression, most compressed
- Level 6: Default (balanced)

You can configure the compression level in the `.env` file using the `COMPRESSION_LEVEL` variable.

## Error Handling

The script includes error handling for:
- Missing required tools (rclone, tar, gzip)
- Missing or invalid source directory
- Missing configuration file
- Failed archive creation
- Failed upload
- Failed deletion of old backups

## License

This script is provided under the MIT License. See the LICENSE file for details. 