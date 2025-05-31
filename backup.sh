#!/bin/bash

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# Default values for script arguments
DEFAULT_REMOTE_TARGET_PATH="./" # Default path on the rclone remote
DEFAULT_BACKUP_PREFIX=""        # Default backup prefix (empty)
AUTO_CONFIRM=false              # Default to requiring confirmation
DEFAULT_LOG_LEVEL="INFO"        # Default log level

# Log levels
declare -A LOG_LEVELS=(
  ["DEBUG"]=0
  ["INFO"]=1
  ["WARNING"]=2
  ["ERROR"]=3
)

# Current log level (default to INFO)
CURRENT_LOG_LEVEL="${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}"

# Validate log level
validate_log_level() {
  local level="$1"
  if [[ ! "${LOG_LEVELS[$level]:-}" ]]; then
    log_error "Invalid log level '$level'. Must be one of: ${!LOG_LEVELS[*]}"
    exit 1
  fi
}

# Validate initial log level
validate_log_level "$CURRENT_LOG_LEVEL"

# Helper Functions
log() {
  local level="$1"
  local message="$2"

  # Check if the message's level should be displayed
  if [ "${LOG_LEVELS[$level]}" -ge "${LOG_LEVELS[$CURRENT_LOG_LEVEL]}" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [$level] - $message"
  fi
}

# Convenience log functions
log_debug() {
  log "DEBUG" "$1"
}

log_info() {
  log "INFO" "$1"
}

log_warning() {
  log "WARNING" "$1"
}

log_error() {
  log "ERROR" "$1"
}

# Estimate the dir in which the Script is located
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Configuration File
CONFIG_FILE="${BACKUP_CONFIG_FILE:-$HOME/.config/rclone-backup/.env}"
if [ ! -f "$CONFIG_FILE" ] && [ -f "/etc/rclone-backup/.env" ]; then
  CONFIG_FILE="/etc/rclone-backup/.env"
fi

log_debug "Using config file: $CONFIG_FILE"

# Validate compression level
validate_compression_level() {
  local level="$1"
  if ! [[ "$level" =~ ^[1-9]$ ]]; then
    log_error "COMPRESSION_LEVEL must be between 1 and 9"
    exit 1
  fi
}

# Check available disk space
check_disk_space() {
  local source_dir="$1"
  local required_space
  required_space=$(du -s "$source_dir" | awk '{print $1}')
  required_space=$((required_space * 2)) # Double the size for safety

  local available_space
  available_space=$(df -P "$source_dir" | awk 'NR==2 {print $4}')

  if [ "$available_space" -lt "$required_space" ]; then
    log_error "Not enough disk space. Required: ${required_space}KB, Available: ${available_space}KB"
    exit 1
  fi
}

# Validate remote path
validate_remote_path() {
  local path="$1"
  if [[ "$path" =~ \.\./ ]]; then
    log_error "Remote path cannot contain '..'"
    exit 1
  fi
}

usage() {
  log_info "Usage: $0 [OPTIONS] <SOURCE_DIR>"
  log_info ""
  log_info "Arguments:"
  log_info "  SOURCE_DIR          : Mandatory. Local directory to back up."
  log_info ""
  log_info "Options:"
  log_info "  -y, --yes           : Automatically confirm deletion of old backups"
  log_info "  -r, --remote PATH   : Path on the rclone remote where backups will be stored"
  log_info "                        Defaults to '$DEFAULT_REMOTE_TARGET_PATH'"
  log_info "  -p, --prefix PREFIX : Prefix for the backup archive name"
  log_info "  -l, --log-level LVL : Set log level (DEBUG, INFO, WARNING, ERROR)"
  log_info "                        Defaults to '$DEFAULT_LOG_LEVEL'"
  log_info "  -h, --help          : Show help message"
  log_info ""
  log_info "Reads rclone remote name and retention settings from '$CONFIG_FILE'."
  exit 1
}

# Argument Parsing
while [[ $# -gt 0 ]]; do
  case $1 in
    -y|--yes)
      AUTO_CONFIRM=true
      shift
      ;;
    -r|--remote)
      ARG_REMOTE_TARGET_PATH="$2"
      validate_remote_path "$2"
      shift 2
      ;;
    -p|--prefix)
      ARG_BACKUP_PREFIX="$2"
      shift 2
      ;;
    -l|--log-level)
      CURRENT_LOG_LEVEL="$2"
      validate_log_level "$CURRENT_LOG_LEVEL"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      if [ -z "${ARG_SOURCE_DIR:-}" ]; then
        ARG_SOURCE_DIR="$1"
      else
        log "ERROR" "Unexpected argument: $1"
        usage
      fi
      shift
      ;;
  esac
done

# Set default values if not provided
ARG_REMOTE_TARGET_PATH="${ARG_REMOTE_TARGET_PATH:-$DEFAULT_REMOTE_TARGET_PATH}"
ARG_BACKUP_PREFIX="${ARG_BACKUP_PREFIX:-$DEFAULT_BACKUP_PREFIX}"

if [ -z "${ARG_SOURCE_DIR:-}" ]; then
  log_error "SOURCE_DIR argument is mandatory."
  usage
fi

if [ ! -d "$ARG_SOURCE_DIR" ]; then
  log_error "Source directory '$ARG_SOURCE_DIR' not found."
  exit 1
fi

# Load Configuration from .env file
DEFAULT_RCLONE_REMOTE_NAME=""
DEFAULT_KEEP_DAILY=7
DEFAULT_KEEP_WEEKLY=4
DEFAULT_KEEP_MONTHLY=6
DEFAULT_COMPRESSION_LEVEL=6

if [ -f "$CONFIG_FILE" ]; then
  log_debug "Sourcing $CONFIG_FILE"
  # shellcheck source=.env
  source "$CONFIG_FILE"
  log_debug "Sourced $CONFIG_FILE"
else
  log_error "Configuration file '$CONFIG_FILE' not found."
  log_info "Please create '$CONFIG_FILE' with RCLONE_REMOTE_NAME and KEEP_* settings."
  exit 1
fi

# Assign variables from .env or use defaults
RCLONE_REMOTE_NAME="${RCLONE_REMOTE_NAME:-$DEFAULT_RCLONE_REMOTE_NAME}"
KEEP_DAILY="${KEEP_DAILY:-$DEFAULT_KEEP_DAILY}"
KEEP_WEEKLY="${KEEP_WEEKLY:-$DEFAULT_KEEP_WEEKLY}"
KEEP_MONTHLY="${KEEP_MONTHLY:-$DEFAULT_KEEP_MONTHLY}"
COMPRESSION_LEVEL="${COMPRESSION_LEVEL:-$DEFAULT_COMPRESSION_LEVEL}"

# Validate configuration
validate_compression_level "$COMPRESSION_LEVEL"

if [ -z "$RCLONE_REMOTE_NAME" ]; then
  log_error "RCLONE_REMOTE_NAME is not set in '$CONFIG_FILE'."
  exit 1
fi

# Validate Tools
if ! command -v rclone &> /dev/null; then
    log_error "rclone command not found. Please install rclone."
    exit 1
fi
if ! command -v tar &> /dev/null; then
    log_error "tar command not found. Please install tar."
    exit 1
fi
if ! command -v gzip &> /dev/null; then
    log_error "gzip command not found. Please install gzip."
    exit 1
fi

# Check disk space before proceeding
check_disk_space "$ARG_SOURCE_DIR"

# Construct full rclone remote path
FULL_RCLONE_DESTINATION="${RCLONE_REMOTE_NAME}:${ARG_REMOTE_TARGET_PATH}"

log_info "--- Backup Configuration"
log_info "Source Directory: $ARG_SOURCE_DIR"
log_info "Rclone Remote Name: $RCLONE_REMOTE_NAME"
log_info "Remote Target Path: $ARG_REMOTE_TARGET_PATH"
log_info "Full Rclone Destination: $FULL_RCLONE_DESTINATION"
log_info "Backup Prefix: '$ARG_BACKUP_PREFIX'"
log_info "Keep Daily: $KEEP_DAILY"
log_info "Keep Weekly: $KEEP_WEEKLY"
log_info "Keep Monthly: $KEEP_MONTHLY"
log_info "Compression Level: $COMPRESSION_LEVEL"
log_info "---------------------------"

# Create backup archive
create_backup_archive() {
  local source_dir="$1"
  local archive_name="$2"
  local compression_level="$3"
  local temp_archive_path="/tmp/${archive_name}"

  log_info "Starting backup for $source_dir"
  log_info "Creating archive: $archive_name"

  source_dir_basename=$(basename "$source_dir")

  if tar -C "$(dirname "$source_dir")" -cf "$temp_archive_path" "$source_dir_basename" \
      --owner=0 --group=0 \
      --use-compress-program="gzip -${compression_level}"; then
    log_info "Archive created successfully: $temp_archive_path"
    echo "$temp_archive_path"
  else
    log_error "Failed to create archive."
    exit 1
  fi
}

# Upload backup to remote
upload_backup() {
  local archive_path="$1"
  local remote_destination="$2"
  local archive_name=$(basename "$archive_path")

  log_info "Uploading $archive_name to $remote_destination"
  if rclone copy "$archive_path" "$remote_destination/" --progress; then
    log_info "Upload successful."
    rm -f "$archive_path"
    log_info "Local archive $archive_path removed."
  else
    log_error "rclone upload failed."
    rm -f "$archive_path"
    exit 1
  fi
}

# Handle backup retention
handle_backup_retention() {
  local remote_destination="$1"
  local backup_prefix="$2"
  local keep_daily="$3"
  local keep_weekly="$4"
  local keep_monthly="$5"

  log_info "Starting remote backup retention management for $remote_destination"

  remote_backups_raw=$(rclone lsf "$remote_destination/" --files-only 2>/dev/null || echo "")

  if [ -z "$remote_backups_raw" ]; then
    log_info "No remote backups found at $remote_destination matching the pattern."
    return 0
  fi

  # Construct the grep pattern based on whether BACKUP_PREFIX is set
  if [ -n "$backup_prefix" ]; then
    remote_grep_pattern="^[0-9]{4}-[0-9]{2}-[0-9]{2}_${backup_prefix}\\.tar\\.gz$"
  else
    remote_grep_pattern="^[0-9]{4}-[0-9]{2}-[0-9]{2}\\.tar\\.gz$"
  fi

  mapfile -t sorted_backups < <(echo "$remote_backups_raw" | grep -E "$remote_grep_pattern" | sort -r)

  log_info "Found ${#sorted_backups[@]} remote backups matching the pattern '$remote_grep_pattern'."

  declare -a daily_kept_files=()
  declare -A weekly_kept_weeks=()
  declare -A monthly_kept_months=()
  declare -a to_delete_files=()

  for backup_file in "${sorted_backups[@]}"; do
    backup_date_str=$(get_backup_date_from_filename "$backup_file")
    if [ -z "$backup_date_str" ]; then
      log_warning "Could not parse date from '$backup_file'. Skipping for retention."
      continue
    fi

    backup_year_week=$(get_week_number "$backup_date_str")
    backup_year_month=$(get_month "$backup_date_str")
    is_kept=false

    if [ ${#daily_kept_files[@]} -lt "$keep_daily" ]; then
      daily_kept_files+=("$backup_file")
      is_kept=true
      continue
    fi

    if ! $is_kept && [ ${#weekly_kept_weeks[@]} -lt "$keep_weekly" ]; then
      if [ -z "${weekly_kept_weeks[$backup_year_week]}" ]; then
        weekly_kept_weeks[$backup_year_week]="$backup_file"
        is_kept=true
        continue
      fi
    fi

    if ! $is_kept && [ ${#monthly_kept_months[@]} -lt "$keep_monthly" ]; then
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

  log_info "--- Retention Summary"
  log_info "Daily to keep: $keep_daily. Found qualifying: ${#daily_kept_files[@]}"
  log_info "Weekly to keep: $keep_weekly (distinct weeks). Found qualifying: ${#weekly_kept_weeks[@]}"
  log_info "Monthly to keep: $keep_monthly (distinct months). Found qualifying: ${#monthly_kept_months[@]}"

  if [ ${#to_delete_files[@]} -gt 0 ]; then
    log_info "Backups to delete (${#to_delete_files[@]}):"
    printf "  %s\n" "${to_delete_files[@]}"

    if [ "$AUTO_CONFIRM" = true ]; then
      log_info "Auto-confirmation enabled. Proceeding with deletion..."
    else
      read -r -p "Proceed with deleting ${#to_delete_files[@]} remote backups? (yes/NO): " confirmation
      if [[ ! "$confirmation" =~ ^[yY][eE][sS]$ ]]; then
        log_info "Deletion aborted by user."
        return 0
      fi
    fi

    log_info "Deleting backups..."
    for file_to_delete in "${to_delete_files[@]}"; do
      log_info "Deleting $remote_destination/$file_to_delete"
      if rclone delete "$remote_destination/$file_to_delete"; then
        log_info "Successfully deleted $file_to_delete"
      else
        log_error "Error deleting $file_to_delete. Check rclone output."
      fi
    done
    log_info "Deletion process finished."
  else
    log_info "No backups to delete according to the retention policy."
  fi
}

# Main Script

# Create backup archive
current_date=$(date '+%Y-%m-%d')
archive_name_core="${current_date}"

if [ -n "$ARG_BACKUP_PREFIX" ]; then
  archive_name="${archive_name_core}_${ARG_BACKUP_PREFIX}.tar.gz"
else
  archive_name="${archive_name_core}.tar.gz"
fi

temp_archive_path=$(create_backup_archive "$ARG_SOURCE_DIR" "$archive_name" "$COMPRESSION_LEVEL")

# Upload backup
upload_backup "$temp_archive_path" "$FULL_RCLONE_DESTINATION"

# Handle retention
handle_backup_retention "$FULL_RCLONE_DESTINATION" "$ARG_BACKUP_PREFIX" "$KEEP_DAILY" "$KEEP_WEEKLY" "$KEEP_MONTHLY"

log_info "Backup script finished."
