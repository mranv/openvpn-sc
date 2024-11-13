#!/bin/bash
# OpenVPN Static IP Manager Installer
# Created with ❤️ by @mranv

# Source utility files
source scripts/utils/colors.sh

# Print banner
echo -e "${BLUE}"
echo '    ____                  _    ______  _   __   ___  ___'
echo '   / __ \____  ___  ____| |  / / __ \/ | / /  |__ \|__ \'
echo '  / / / / __ \/ _ \/ __ \ | / / /_/ /  |/ /   __/ /__/ /'
echo ' / /_/ / /_/ /  __/ / / / |/ / ____/ /|  /   / __// __/'
echo ' \____/ .___/\___/_/ /_/|___/_/   /_/ |_/   /____/____/'
echo '     /_/    Static IP Manager'
echo -e "${NC}"
echo -e "${YELLOW}Created with ❤️  by @mranv${NC}\n"

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root"
    exit 1
fi

# Function to check system requirements
check_requirements() {
    print_header "Checking System Requirements"
    
    # Check OS
    if [ -f /etc/debian_version ]; then
        print_success "Debian-based system detected"
    elif [ -f /etc/redhat-release ]; then
        print_success "RedHat-based system detected"
    else
        print_warning "Unsupported operating system"
    fi
    
    # Check dependencies
    local deps=("curl" "wget" "openvpn")
    for dep in "${deps[@]}"; do
        if command -v "$dep" >/dev/null 2>&1; then
            print_success "$dep is installed"
        else
            print_error "$dep is not installed"
            MISSING_DEPS=1
        fi
    done
}

# Function to install dependencies
install_dependencies() {
    print_header "Installing Dependencies"
    
    if [ -f /etc/debian_version ]; then
        apt-get update
        apt-get install -y openvpn easy-rsa curl wget
    elif [ -f /etc/redhat-release ]; then
        yum install -y epel-release
        yum install -y openvpn easy-rsa curl wget
    fi
}

# Function to setup directories
setup_directories() {
    print_header "Setting up Directories"
    
    local dirs=(
        "/etc/openvpn/server"
        "/etc/openvpn/ccd"
        "/etc/openvpn/clients"
        "/var/log/openvpn"
    )
    
    for dir in "${dirs[@]}"; do
        if mkdir -p "$dir" 2>/dev/null; then
            print_success "Created $dir"
        else
            print_error "Failed to create $dir"
            return 1
        fi
    done
}

# Function to copy configuration files
copy_configurations() {
    print_header "Copying Configuration Files"
    
    # Copy server template
    cp config/server.conf.template /etc/openvpn/server.conf
    print_success "Copied server configuration"
    
    # Copy client template
    cp config/client.conf.template /etc/openvpn/client-template.txt
    print_success "Copied client configuration template"
}

# Function to install manager script
install_manager() {
    print_header "Installing OpenVPN Manager"
    
    # Copy manager script to bin
    cp scripts/manager.sh /usr/local/bin/openvpn-manager
    chmod +x /usr/local/bin/openvpn-manager
    print_success "Installed OpenVPN manager script"
    
    # Create symbolic link
    ln -sf /usr/local/bin/openvpn-manager /usr/local/bin/ovpn
    print_success "Created symbolic link 'ovpn'"
}

# Main installation process
main() {
    print_header "Starting Installation"
    
    check_requirements
    if [ "$MISSING_DEPS" == "1" ]; then
        print_info "Installing missing dependencies..."
        install_dependencies
    fi
    
    setup_directories
    copy_configurations
    install_manager
    
    print_header "Installation Complete!"
    echo -e "\nYou can now use the OpenVPN manager by running:"
    echo -e "${GREEN}openvpn-manager${NC} or ${GREEN}ovpn${NC}"
    echo -e "\nFor more information, please visit:"
    echo -e "${BLUE}https://github.com/mranv/openvpn-sc${NC}"
}

# Execute main installation
main