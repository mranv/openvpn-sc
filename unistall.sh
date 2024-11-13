#!/bin/bash

# OpenVPN Static IP Manager Uninstaller
# Created with ❤️ by @mranv
# Version: 2.0.0

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Directories and files to remove
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/openvpn"
SYSTEMD_DIR="/etc/systemd/system"
UTILS_DIR="${INSTALL_DIR}/utils"
LOG_DIR="/var/log/openvpn"

# Print functions
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Print banner
print_banner() {
    echo -e "${BLUE}"
    echo '    ____                  _    ______  _   __   ___  ___'
    echo '   / __ \____  ___  ____| |  / / __ \/ | / /  |__ \|__ \'
    echo '  / / / / __ \/ _ \/ __ \ | / / /_/ /  |/ /   __/ /__/ /'
    echo ' / /_/ / /_/ /  __/ / / / |/ / ____/ /|  /   / __// __/'
    echo ' \____/ .___/\___/_/ /_/|___/_/   /_/ |_/   /____/____/'
    echo '     /_/    Static IP Manager Uninstaller'
    echo -e "${NC}"
    echo -e "${YELLOW}Created with ❤️ by @mranv${NC}\n"
}

# Check root privileges
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run as root"
        exit 1
    fi
}

# Stop OpenVPN service
stop_services() {
    print_header "Stopping Services"
    
    # Stop OpenVPN service if running
    if systemctl is-active --quiet openvpn.service; then
        systemctl stop openvpn.service
        print_success "Stopped OpenVPN service"
    fi
    
    # Stop and disable OpenVPN manager service if exists
    if [ -f "${SYSTEMD_DIR}/openvpn-manager.service" ]; then
        systemctl stop openvpn-manager.service 2>/dev/null
        systemctl disable openvpn-manager.service 2>/dev/null
        print_success "Stopped and disabled OpenVPN manager service"
    fi
    
    # Reload systemd
    systemctl daemon-reload
}

# Remove configuration files
remove_configs() {
    print_header "Removing Configuration Files"
    
    # Backup configuration if requested
    if [ "$BACKUP" = true ]; then
        BACKUP_DIR="/root/openvpn-backup-$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        
        if [ -d "$CONFIG_DIR" ]; then
            cp -r "$CONFIG_DIR" "$BACKUP_DIR/"
            print_success "Configuration backed up to $BACKUP_DIR"
        fi
    fi
    
    # Remove configuration directories
    local dirs=(
        "$CONFIG_DIR/server"
        "$CONFIG_DIR/ccd"
        "$CONFIG_DIR/clients"
    )
    
    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ]; then
            rm -rf "$dir"
            print_success "Removed $dir"
        fi
    done
    
    # Remove main config directory if empty
    if [ -d "$CONFIG_DIR" ] && [ -z "$(ls -A $CONFIG_DIR)" ]; then
        rm -rf "$CONFIG_DIR"
        print_success "Removed empty $CONFIG_DIR"
    fi
}

# Remove installed files
remove_files() {
    print_header "Removing Installed Files"
    
    # Remove binary files
    local files=(
        "${INSTALL_DIR}/openvpn-manager"
        "${INSTALL_DIR}/ovpn"
        "${UTILS_DIR}/colors.sh"
        "${SYSTEMD_DIR}/openvpn-manager.service"
    )
    
    for file in "${files[@]}"; do
        if [ -f "$file" ] || [ -L "$file" ]; then
            rm -f "$file"
            print_success "Removed $file"
        fi
    done
    
    # Remove utils directory if empty
    if [ -d "$UTILS_DIR" ] && [ -z "$(ls -A $UTILS_DIR)" ]; then
        rm -rf "$UTILS_DIR"
        print_success "Removed empty $UTILS_DIR"
    fi
    
    # Remove log directory
    if [ -d "$LOG_DIR" ]; then
        rm -rf "$LOG_DIR"
        print_success "Removed $LOG_DIR"
    fi
}

# Clean up system
cleanup_system() {
    print_header "Cleaning Up System"
    
    # Remove any remaining PID files
    rm -f /var/run/openvpn*.pid 2>/dev/null
    
    # Remove any remaining lock files
    rm -f /var/run/openvpn*.lock 2>/dev/null
    
    print_success "Removed temporary files"
}

# Ask for confirmation
confirm_uninstall() {
    echo -e "${YELLOW}WARNING: This will remove OpenVPN Static IP Manager and all its configurations.${NC}"
    read -p "Do you want to backup configurations before uninstalling? (y/N): " backup_choice
    if [[ $backup_choice =~ ^[Yy]$ ]]; then
        BACKUP=true
    else
        BACKUP=false
    fi
    
    read -p "Are you sure you want to continue with uninstallation? (y/N): " choice
    if [[ ! $choice =~ ^[Yy]$ ]]; then
        echo -e "\n${YELLOW}Uninstallation cancelled.${NC}"
        exit 0
    fi
}

# Main uninstallation process
main() {
    clear
    print_banner
    
    check_root
    confirm_uninstall
    
    stop_services
    remove_configs
    remove_files
    cleanup_system
    
    print_header "Uninstallation Complete!"
    if [ "$BACKUP" = true ]; then
        echo -e "\n${YELLOW}Your configuration has been backed up to: $BACKUP_DIR${NC}"
    fi
    echo -e "\n${GREEN}OpenVPN Static IP Manager has been successfully uninstalled.${NC}"
}

# Execute main uninstallation
main