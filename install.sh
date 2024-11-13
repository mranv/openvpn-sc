#!/bin/bash

# OpenVPN Static IP Manager Installer
# Created with ❤️ by @mranv
# Version: 2.0.0

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create colors.sh if it doesn't exist
create_colors_file() {
    local utils_dir="${SCRIPT_DIR}/scripts/utils"
    mkdir -p "$utils_dir"
    
    cat > "${utils_dir}/colors.sh" << 'EOF'
# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}
EOF

    chmod +x "${utils_dir}/colors.sh"
}

# Create and source colors file
create_colors_file
source "${SCRIPT_DIR}/scripts/utils/colors.sh"

# Configuration
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/openvpn"
SYSTEMD_DIR="/etc/systemd/system"
UTILS_DIR="${INSTALL_DIR}/utils"

# Progress spinner
spinner() {
    local pid=$1
    local message=$2
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    echo -ne "$message "
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf "[%c]" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b"
    done
    printf "   \b\b\b"
    echo -e "${GREEN}✓${NC}"
}

# Print banner
print_banner() {
    echo -e "${BLUE}"
    echo '    ____                  _    ______  _   __   ___  ___'
    echo '   / __ \____  ___  ____| |  / / __ \/ | / /  |__ \|__ \'
    echo '  / / / / __ \/ _ \/ __ \ | / / /_/ /  |/ /   __/ /__/ /'
    echo ' / /_/ / /_/ /  __/ / / / |/ / ____/ /|  /   / __// __/'
    echo ' \____/ .___/\___/_/ /_/|___/_/   /_/ |_/   /____/____/'
    echo '     /_/    Static IP Manager'
    echo -e "${NC}"
    echo -e "${YELLOW}Created with ❤️ by @mranv${NC}\n"
}

# Error handler
handle_error() {
    echo -e "\n${RED}[ERROR] $1${NC}"
    echo -e "${YELLOW}Installation failed. Please check the error message above.${NC}"
    exit 1
}

# Check root privileges
check_root() {
    if [ "$EUID" -ne 0 ]; then
        handle_error "Please run as root"
    fi
}

# Function to check system requirements
check_requirements() {
    print_header "Checking System Requirements"
    
    # Check OS
    if [ -f /etc/debian_version ]; then
        print_success "Debian-based system detected"
        OS_TYPE="debian"
    elif [ -f /etc/redhat-release ]; then
        print_success "RedHat-based system detected"
        OS_TYPE="redhat"
    else
        handle_error "Unsupported operating system"
    fi
    
    # Check dependencies
    local deps=("curl" "wget" "openvpn")
    MISSING_DEPS=()
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            MISSING_DEPS+=("$dep")
        fi
    done
    
    if [ ${#MISSING_DEPS[@]} -eq 0 ]; then
        print_success "All dependencies are installed"
    else
        print_warning "Missing dependencies: ${MISSING_DEPS[*]}"
        return 1
    fi
}

# Function to install dependencies
install_dependencies() {
    print_header "Installing Dependencies"
    
    case $OS_TYPE in
        debian)
            {
                apt-get update &> /dev/null
                apt-get install -y openvpn easy-rsa curl wget &> /dev/null
            } & spinner $! "Installing packages..."
            ;;
        redhat)
            {
                yum install -y epel-release &> /dev/null
                yum install -y openvpn easy-rsa curl wget &> /dev/null
            } & spinner $! "Installing packages..."
            ;;
    esac
    
    # Verify installation
    for dep in "${MISSING_DEPS[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            handle_error "Failed to install $dep"
        fi
    done
    
    print_success "Dependencies installed successfully"
}

# Function to setup directories
setup_directories() {
    print_header "Setting up Directories"
    
    local dirs=(
        "$CONFIG_DIR/server"
        "$CONFIG_DIR/ccd"
        "$CONFIG_DIR/clients"
        "/var/log/openvpn"
        "$UTILS_DIR"
    )
    
    for dir in "${dirs[@]}"; do
        if ! mkdir -p "$dir" 2>/dev/null; then
            handle_error "Failed to create directory: $dir"
        fi
        print_success "Created $dir"
    done
}

# Function to copy configuration files
copy_configurations() {
    print_header "Copying Configuration Files"
    
    # Copy colors.sh to the installation directory
    cp "${SCRIPT_DIR}/scripts/utils/colors.sh" "${UTILS_DIR}/"
    chmod 644 "${UTILS_DIR}/colors.sh"
    
    # Verify source files exist
    if [ ! -f "${SCRIPT_DIR}/config/server.conf.template" ] || \
       [ ! -f "${SCRIPT_DIR}/config/client.conf.template" ]; then
        handle_error "Configuration templates not found"
    fi
    
    # Copy with error checking
    if ! cp "${SCRIPT_DIR}/config/server.conf.template" "${CONFIG_DIR}/server.conf"; then
        handle_error "Failed to copy server configuration"
    fi
    print_success "Copied server configuration"
    
    if ! cp "${SCRIPT_DIR}/config/client.conf.template" "${CONFIG_DIR}/client-template.txt"; then
        handle_error "Failed to copy client configuration"
    fi
    print_success "Copied client configuration template"
    
    # Set proper permissions
    chmod 644 "${CONFIG_DIR}/server.conf" "${CONFIG_DIR}/client-template.txt"
}

# Function to install manager script
install_manager() {
    print_header "Installing OpenVPN Manager"
    
    # Copy manager script
    if ! cp "${SCRIPT_DIR}/scripts/manager.sh" "${INSTALL_DIR}/openvpn-manager"; then
        handle_error "Failed to copy manager script"
    fi
    chmod +x "${INSTALL_DIR}/openvpn-manager"
    print_success "Installed OpenVPN manager script"
    
    # Create symbolic link
    if ! ln -sf "${INSTALL_DIR}/openvpn-manager" "${INSTALL_DIR}/ovpn"; then
        handle_error "Failed to create symbolic link"
    fi
    print_success "Created symbolic link 'ovpn'"
}

# Function to create systemd service
create_service() {
    print_header "Creating SystemD Service"
    
    cat > "${SYSTEMD_DIR}/openvpn-manager.service" << EOF
[Unit]
Description=OpenVPN Static IP Manager Service
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/openvpn-manager
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "${SYSTEMD_DIR}/openvpn-manager.service"
    systemctl daemon-reload
    print_success "Created systemd service"
}

# Function to verify installation
verify_installation() {
    print_header "Verifying Installation"
    
    # Check if all components are installed
    local components=(
        "${INSTALL_DIR}/openvpn-manager"
        "${INSTALL_DIR}/ovpn"
        "${CONFIG_DIR}/server.conf"
        "${CONFIG_DIR}/client-template.txt"
        "${UTILS_DIR}/colors.sh"
    )
    
    for component in "${components[@]}"; do
        if [ ! -e "$component" ]; then
            handle_error "Component not found: $component"
        fi
    done
    
    print_success "All components verified"
}

# Main installation process
main() {
    trap 'handle_error "Installation interrupted"' INT TERM
    
    clear
    print_banner
    
    check_root
    
    if ! check_requirements; then
        print_info "Installing missing dependencies..."
        install_dependencies
    fi
    
    setup_directories
    copy_configurations
    install_manager
    create_service
    verify_installation
    
    print_header "Installation Complete!"
    echo -e "\nYou can now use the OpenVPN manager by running:"
    echo -e "${GREEN}openvpn-manager${NC} or ${GREEN}ovpn${NC}"
    echo -e "\nFor more information, please visit:"
    echo -e "${BLUE}https://github.com/mranv/openvpn-sc${NC}"
}

# Execute main installation
main