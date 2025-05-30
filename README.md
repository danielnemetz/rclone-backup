# Backup Script

A robust bash script for creating and managing backups using rclone. The script creates compressed archives of specified directories and uploads them to a configured rclone remote storage, with configurable retention policies for daily, weekly, and monthly backups.

## Prerequisites

- `rclone` installed and configured with at least one remote
- `tar` command-line utility
- Bash shell environment

## Configuration

Create a `.env` file in the same directory as the script with the following variables:

```bash
# Required
RCLONE_REMOTE_NAME="your_remote_name"  # The name of your configured rclone remote

# Optional (defaults shown)
KEEP_DAILY=7      # Number of daily backups to keep
KEEP_WEEKLY=4     # Number of weekly backups to keep
KEEP_MONTHLY=6    # Number of monthly backups to keep
COMPRESSION_LEVEL=6  # Compression level for tar (1-9)
```

## Usage

```bash
./backup.sh <SOURCE_DIR> [REMOTE_TARGET_PATH] [BACKUP_PREFIX]
```

### Arguments

1. `SOURCE_DIR` (Mandatory)
   - The local directory to back up
   - Must be an existing directory

2. `REMOTE_TARGET_PATH` (Optional)
   - Path on the rclone remote where backups will be stored
   - Default: `./` (current directory on remote)
   - Example: `backups/` or `my_backups/2024/`

3. `BACKUP_PREFIX` (Optional)
   - Prefix for the backup archive name
   - If not provided, archive name will be `YYYY-MM-DD.tar.gz`
   - If provided, archive name will be `YYYY-MM-DD_PREFIX.tar.gz`

## Examples

1. Basic backup of a directory:
```bash
./backup.sh /path/to/my/data
```

2. Backup with custom remote path:
```bash
./backup.sh /path/to/my/data backups/2024/
```

3. Backup with prefix:
```bash
./backup.sh /path/to/my/data ./ mydata
```

4. Full example with all options:
```bash
./backup.sh /path/to/my/data backups/2024/ mydata
```

## Backup Retention

The script implements a tiered retention policy:

- **Daily Backups**: Keeps the most recent N daily backups (default: 7)
- **Weekly Backups**: Keeps one backup per week for N weeks (default: 4)
- **Monthly Backups**: Keeps one backup per month for N months (default: 6)

The retention policy is applied in this order:
1. Keep the most recent daily backups
2. For older backups, keep one per week
3. For even older backups, keep one per month
4. Delete all other backups

## Backup Process

1. Creates a compressed tar archive of the source directory
2. Uploads the archive to the configured rclone remote
3. Manages backup retention according to the configured policy
4. Prompts for confirmation before deleting old backups

## Notes

- The script uses `tar` with gzip compression
- All backups are stored with consistent ownership (root:root)
- The script includes error handling and logging
- A confirmation prompt is shown before deleting old backups
- All operations are logged with timestamps 