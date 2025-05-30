#!/bin/bash

set -e

# --- Default values for script arguments ---
DEFAULT_REMOTE_TARGET_PATH="./" # Default path on the rclone remote
DEFAULT_BACKUP_PREFIX=""        # Default backup prefix (empty)

# --- Estimate the dir in which the Script is located ---
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# --- Configuration File ---
CONFIG_FILE="${SCRIPT_DIR}/.env"

# --- Helper Functions ---
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

usage() {
  echo "Usage: $0 <SOURCE_DIR> [REMOTE_TARGET_PATH] [BACKUP_PREFIX]"
  echo ""
  echo "Arguments:"
  echo "  SOURCE_DIR          : Mandatory. Local directory to back up."
  echo "  REMOTE_TARGET_PATH  : Optional. Path on the rclone remote where backups will be stored."
  echo "                        Defaults to '$DEFAULT_REMOTE_TARGET_PATH' (current directory on remote)."
  echo "  BACKUP_PREFIX       : Optional. Prefix for the backup archive name (e.g., 'mydata')."
  echo "                        If empty, archive name will be 'YYYY-MM-DD.tar.gz'."
  echo "                        If set, 'YYYY-MM-DD_PREFIX.tar.gz'."
  echo ""
  echo "Reads rclone remote name and retention settings from '$CONFIG_FILE'."
  exit 1
}

# --- Argument Parsing ---
ARG_SOURCE_DIR="$1"
ARG_REMOTE_TARGET_PATH="${2:-$DEFAULT_REMOTE_TARGET_PATH}"
ARG_BACKUP_PREFIX="${3:-$DEFAULT_BACKUP_PREFIX}"

if [ -z "$ARG_SOURCE_DIR" ]; then
  log "Error: SOURCE_DIR argument is mandatory."
  usage
fi

if [ ! -d "$ARG_SOURCE_DIR" ]; then
  log "Error: Source directory '$ARG_SOURCE_DIR' not found."
  exit 1
fi

# --- Load Configuration from .env file ---
# These are expected in .env: RCLONE_REMOTE_NAME, KEEP_DAILY, KEEP_WEEKLY, KEEP_MONTHLY
# Optional in .env: COMPRESSION_LEVEL
DEFAULT_RCLONE_REMOTE_NAME=""
DEFAULT_KEEP_DAILY=7
DEFAULT_KEEP_WEEKLY=4
DEFAULT_KEEP_MONTHLY=6
DEFAULT_COMPRESSION_LEVEL=6

if [ -f "$CONFIG_FILE" ]; then
  # shellcheck source=.env
  source "$CONFIG_FILE"
else
  log "Error: Configuration file '$CONFIG_FILE' not found."
  echo "Please create '$CONFIG_FILE' with RCLONE_REMOTE_NAME and KEEP_* settings."
  exit 1
fi

# Assign variables from .env or use defaults (though some are now errors if not set)
RCLONE_REMOTE_NAME="${RCLONE_REMOTE_NAME:-$DEFAULT_RCLONE_REMOTE_NAME}"
KEEP_DAILY="${KEEP_DAILY:-$DEFAULT_KEEP_DAILY}"
KEEP_WEEKLY="${KEEP_WEEKLY:-$DEFAULT_KEEP_WEEKLY}"
KEEP_MONTHLY="${KEEP_MONTHLY:-$DEFAULT_KEEP_MONTHLY}"
COMPRESSION_LEVEL="${COMPRESSION_LEVEL:-$DEFAULT_COMPRESSION_LEVEL}"

# --- Validate Essential .env Configuration ---
if [ -z "$RCLONE_REMOTE_NAME" ]; then
  log "Error: RCLONE_REMOTE_NAME is not set in '$CONFIG_FILE'."
  exit 1
fi

# --- Validate Tools ---
if ! command -v rclone &> /dev/null; then
    log "Error: rclone command not found. Please install rclone."
    exit 1
fi
if ! command -v tar &> /dev/null; then
    log "Error: tar command not found. Please install tar."
    exit 1
fi

# --- Construct full rclone remote path ---
# Ensure no double slashes if ARG_REMOTE_TARGET_PATH starts with one, though rclone usually handles it.
# For simplicity, we'll just concatenate. `remote:path` or `remote:./path`
FULL_RCLONE_DESTINATION="${RCLONE_REMOTE_NAME}:${ARG_REMOTE_TARGET_PATH}"

log "--- Backup Configuration ---"
log "Source Directory: $ARG_SOURCE_DIR"
log "Rclone Remote Name: $RCLONE_REMOTE_NAME"
log "Remote Target Path: $ARG_REMOTE_TARGET_PATH"
log "Full Rclone Destination: $FULL_RCLONE_DESTINATION"
log "Backup Prefix: '$ARG_BACKUP_PREFIX'"
log "Keep Daily: $KEEP_DAILY"
log "Keep Weekly: $KEEP_WEEKLY"
log "Keep Monthly: $KEEP_MONTHLY"
log "---------------------------"


# --- Main Script ---

# 1. Create Backup Archive
current_date=$(date '+%Y-%m-%d')
archive_name_core="${current_date}"

if [ -n "$ARG_BACKUP_PREFIX" ]; then
  archive_name="${archive_name_core}_${ARG_BACKUP_PREFIX}.tar.gz"
  REMOTE_FILENAME_PATTERN_CORE="${archive_name_core}_${ARG_BACKUP_PREFIX}"
else
  archive_name="${archive_name_core}.tar.gz"
  REMOTE_FILENAME_PATTERN_CORE="${archive_name_core}"
fi
temp_archive_path="/tmp/${archive_name}"

log "Starting backup for $ARG_SOURCE_DIR"
log "Creating archive: $archive_name"

source_dir_basename=$(basename "$ARG_SOURCE_DIR")

if tar -C "$(dirname "$ARG_SOURCE_DIR")" -czf "$temp_archive_path" "$source_dir_basename" --owner=0 --group=0; then
  log "Archive created successfully: $temp_archive_path"
else
  log "Error: Failed to create archive."
  exit 1
fi

# 2. Upload Backup using rclone
log "Uploading $archive_name to $FULL_RCLONE_DESTINATION"
# Using rclone copy ... remote:path/ where path is ARG_REMOTE_TARGET_PATH
# If ARG_REMOTE_TARGET_PATH ends with /, rclone copies into it. If not, and it's a dir, also into it.
# If it does not exist, rclone creates it.
if rclone copy "$temp_archive_path" "$FULL_RCLONE_DESTINATION/" --progress; then # Added trailing slash for clarity
  log "Upload successful."
else
  log "Error: rclone upload failed."
  exit 1
fi

rm -f "$temp_archive_path"
log "Local archive $temp_archive_path removed."

# 3. Remote Backup Retention Management
log "Starting remote backup retention management for $FULL_RCLONE_DESTINATION"

remote_backups_raw=$(rclone lsf "$FULL_RCLONE_DESTINATION/" --files-only 2>/dev/null || echo "") # Added trailing slash

if [ -z "$remote_backups_raw" ]; then
  log "No remote backups found at $FULL_RCLONE_DESTINATION matching the pattern."
  log "Backup script finished."
  exit 0
fi

# Construct the grep pattern based on whether BACKUP_PREFIX is set
if [ -n "$ARG_BACKUP_PREFIX" ]; then
  remote_grep_pattern="^[0-9]{4}-[0-9]{2}-[0-9]{2}_${ARG_BACKUP_PREFIX}\\.tar\\.gz$"
else
  remote_grep_pattern="^[0-9]{4}-[0-9]{2}-[0-9]{2}\\.tar\\.gz$"
fi

mapfile -t sorted_backups < <(echo "$remote_backups_raw" | grep -E "$remote_grep_pattern" | sort -r)

log "Found ${#sorted_backups[@]} remote backups matching the pattern '$remote_grep_pattern'."

declare -a daily_kept_files=()
declare -A weekly_kept_weeks=()
declare -A monthly_kept_months=()
declare -a to_delete_files=()

current_ts=$(date +%s)

# Function to parse date from backup filename (YYYY-MM-DD from YYYY-MM-DD_prefix.tar.gz or YYYY-MM-DD.tar.gz)
get_backup_date_from_filename() {
  local filename="$1"
  echo "$filename" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}'
}


for backup_file in "${sorted_backups[@]}"; do
  backup_date_str=$(get_backup_date_from_filename "$backup_file")
  if [ -z "$backup_date_str" ]; then
    log "Warning: Could not parse date from '$backup_file'. Skipping for retention."
    continue
  fi

  backup_year_week=$(date -d "$backup_date_str" '+%Y-%V')
  backup_year_month=$(date -d "$backup_date_str" '+%Y-%m')
  is_kept=false

  if [ ${#daily_kept_files[@]} -lt "$KEEP_DAILY" ]; then
    daily_kept_files+=("$backup_file")
    is_kept=true
    continue
  fi

  if ! $is_kept && [ ${#weekly_kept_weeks[@]} -lt "$KEEP_WEEKLY" ]; then
    if [ -z "${weekly_kept_weeks[$backup_year_week]}" ]; then
      weekly_kept_weeks[$backup_year_week]="$backup_file"
      is_kept=true
      continue
    fi
  fi

  if ! $is_kept && [ ${#monthly_kept_months[@]} -lt "$KEEP_MONTHLY" ]; then
    if [ -z "${monthly_kept_months[$backup_year_month]}" ]; then
      monthly_kept_months[$backup_year_month]="$backup_file"
      is_kept=true
      continue
    fi
  fi

  if ! $is_kept; then
    to_delete_files+=("$backup_file")
  fi
done

log "--- Retention Summary ---"
log "Daily to keep: $KEEP_DAILY. Found qualifying: ${#daily_kept_files[@]}"
log "Weekly to keep: $KEEP_WEEKLY (distinct weeks). Found qualifying: ${#weekly_kept_weeks[@]}"
log "Monthly to keep: $KEEP_MONTHLY (distinct months). Found qualifying: ${#monthly_kept_months[@]}"

if [ ${#to_delete_files[@]} -gt 0 ]; then
  log "Backups to delete (${#to_delete_files[@]}):"
  printf "  %s\n" "${to_delete_files[@]}"
  
  read -r -p "Proceed with deleting ${#to_delete_files[@]} remote backups? (yes/NO): " confirmation
  if [[ "$confirmation" =~ ^[yY][eE][sS]$ ]]; then
    log "Deleting backups..."
    for file_to_delete in "${to_delete_files[@]}"; do
      log "Deleting $FULL_RCLONE_DESTINATION/$file_to_delete"
      # Ensure the path for deletion is correct, rclone delete remote:path/to/file
      if rclone delete "$FULL_RCLONE_DESTINATION/$file_to_delete"; then
         log "Successfully deleted $file_to_delete"
      else
        log "Error deleting $file_to_delete. Check rclone output."
      fi
    done
    log "Deletion process finished."
  else
    log "Deletion aborted by user."
  fi
else
  log "No backups to delete according to the retention policy."
fi

log "Backup script finished."
