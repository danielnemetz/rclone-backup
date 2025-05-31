#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to validate input
validate_input() {
    local input=$1
    local message=$2
    while [ -z "$input" ]; do
        print_message "$RED" "Error: $message cannot be empty"
        read -r -p "$message: " input
    done
    echo "$input"
}

# Function to validate number input
validate_number() {
    local input=$1
    local message=$2
    local min=$3
    local max=$4
    while ! [[ "$input" =~ ^[0-9]+$ ]] || [ "$input" -lt "$min" ] || [ "$input" -gt "$max" ]; do
        print_message "$RED" "Error: $message must be a number between $min and $max"
        read -r -p "$message: " input
    done
    echo "$input"
}

# Function to check if running as root
is_root() {
    [ "$(id -u)" -eq 0 ]
}

# Function to get installation directory
get_install_dir() {
    if is_root; then
        echo "/usr/local/bin"
    else
        echo "$HOME/.local/bin"
    fi
}

# Function to ensure directory exists
ensure_dir() {
    local dir=$1
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
    fi
}

# Main installation process
print_message "$GREEN" "Starting backup script installation..."

# Get installation directory
INSTALL_DIR=$(get_install_dir)
ensure_dir "$INSTALL_DIR"

# Download the backup script
print_message "$YELLOW" "Downloading backup script..."
curl -sSL "https://raw.githubusercontent.com/danielnemetz/rclone-backup/refs/heads/main/backup.sh" -o "$INSTALL_DIR/rclone-backup"
chmod +x "$INSTALL_DIR/rclone-backup"

# Determine config location
if is_root; then
    read -r -p "Do you want to create a global config for all users? (y/N): " GLOBAL_CONFIG
    if [[ "$GLOBAL_CONFIG" =~ ^[Yy]$ ]]; then
        CONFIG_DIR="/etc/rclone-backup"
        CONFIG_PATH="/etc/rclone-backup/.env"
    else
        CONFIG_DIR="$HOME/.config/rclone-backup"
        CONFIG_PATH="$CONFIG_DIR/.env"
    fi
else
    CONFIG_DIR="$HOME/.config/rclone-backup"
    CONFIG_PATH="$CONFIG_DIR/.env"
fi
ensure_dir "$CONFIG_DIR"

# Interactive configuration
echo
print_message "$YELLOW" "Please provide the following configuration details:"

# RCLONE_REMOTE_NAME
read -r -p "Rclone remote name: " RCLONE_REMOTE_NAME
RCLONE_REMOTE_NAME=$(validate_input "$RCLONE_REMOTE_NAME" "Rclone remote name")

# KEEP_DAILY
read -r -p "Number of daily backups to keep (default: 7): " KEEP_DAILY
KEEP_DAILY=${KEEP_DAILY:-7}
KEEP_DAILY=$(validate_number "$KEEP_DAILY" "Number of daily backups" 1 365)

# KEEP_WEEKLY
read -r -p "Number of weekly backups to keep (default: 4): " KEEP_WEEKLY
KEEP_WEEKLY=${KEEP_WEEKLY:-4}
KEEP_WEEKLY=$(validate_number "$KEEP_WEEKLY" "Number of weekly backups" 1 52)

# KEEP_MONTHLY
read -r -p "Number of monthly backups to keep (default: 6): " KEEP_MONTHLY
KEEP_MONTHLY=${KEEP_MONTHLY:-6}
KEEP_MONTHLY=$(validate_number "$KEEP_MONTHLY" "Number of monthly backups" 1 60)

# COMPRESSION_LEVEL
read -r -p "Compression level (1-9, default: 6): " COMPRESSION_LEVEL
COMPRESSION_LEVEL=${COMPRESSION_LEVEL:-6}
COMPRESSION_LEVEL=$(validate_number "$COMPRESSION_LEVEL" "Compression level" 1 9)

# Create .env file
print_message "$YELLOW" "\nCreating configuration file..."
cat > "$CONFIG_PATH" << EOF
# Backup Configuration
RCLONE_REMOTE_NAME="$RCLONE_REMOTE_NAME"
KEEP_DAILY=$KEEP_DAILY
KEEP_WEEKLY=$KEEP_WEEKLY
KEEP_MONTHLY=$KEEP_MONTHLY
COMPRESSION_LEVEL=$COMPRESSION_LEVEL
EOF

print_message "$GREEN" "\nInstallation completed successfully!"
print_message "$YELLOW" "\nThe backup script has been installed to: $INSTALL_DIR/rclone-backup"
print_message "$YELLOW" "Configuration file location: $CONFIG_PATH"
print_message "$YELLOW" "\nYou can now use the backup script with:"
print_message "$GREEN" "  rclone-backup [OPTIONS] <SOURCE_DIR>"
print_message "$YELLOW" "\nFor help, run:"
print_message "$GREEN" "  rclone-backup --help"
