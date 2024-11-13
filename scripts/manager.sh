#!/bin/bash

# Modern OpenVPN Static IP Manager
# Created with ❤️ by @mranv
# Version: 2.0.0

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/colors.sh"

# Configuration
CONFIG_DIR="/etc/openvpn"
CLIENTS_DIR="${CONFIG_DIR}/clients"
CCD_DIR="${CONFIG_DIR}/ccd"
SERVER_DIR="${CONFIG_DIR}/server"
EASYRSA_DIR="${CONFIG_DIR}/easy-rsa"
LOG_DIR="/var/log/openvpn"
BACKUP_DIR="/root/openvpn-backups"

# ASCII Art Banner
print_banner() {
    echo -e "${BLUE}"
    echo '    ____                  _    ______  _   __   ___  ___'
    echo '   / __ \____  ___  ____| |  / / __ \/ | / /  |__ \|__ \'
    echo '  / / / / __ \/ _ \/ __ \ | / / /_/ /  |/ /   __/ /__/ /'
    echo ' / /_/ / /_/ /  __/ / / / |/ / ____/ /|  /   / __// __/'
    echo ' \____/ .___/\___/_/ /_/|___/_/   /_/ |_/   /____/____/'
    echo '     /_/    Static IP Manager'
    echo -e "${NC}"
    echo -e "${YELLOW}Created with ❤️  by @mranv${NC}\n"
}

# Progress spinner with message
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

# Error handler
handle_error() {
    local error_message=$1
    log_error "$error_message"
    echo -e "${RED}An error occurred. Check the log file for details.${NC}"
    exit 1
}

# Validate IP address
validate_ip() {
    local ip=$1
    if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 1
    fi
    for octet in $(echo "$ip" | tr '.' ' '); do
        if [[ $octet -lt 0 || $octet -gt 255 ]]; then
            return 1
        fi
    done
    return 0
}

# Function to check if client name exists
client_exists() {
    local client_name=$1
    [[ -f "${CCD_DIR}/${client_name}" ]]
}

# Enhanced client management
function addClient() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        log_error "Usage: addClient client_name static_ip"
        return 1
    fi
    
    local CLIENT=$1
    local STATIC_IP=$2

    # Validate client name
    if [[ ! $CLIENT =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid client name. Use only letters, numbers, underscore and hyphen."
        return 1
    }

    # Validate IP address
    if ! validate_ip "$STATIC_IP"; then
        log_error "Invalid IP address format"
        return 1
    }

    # Check if client already exists
    if client_exists "$CLIENT"; then
        log_error "Client $CLIENT already exists"
        return 1
    }
    
    log_info "Generating certificates for $CLIENT..."
    
    # Create certificates
    cd "$EASYRSA_DIR" || handle_error "Failed to access EasyRSA directory"
    {
        ./easyrsa gen-req "$CLIENT" nopass &> /dev/null && \
        echo -ne '\n' | ./easyrsa sign-req client "$CLIENT" &> /dev/null
    } & spinner $! "Generating certificates..."

    # Create static IP configuration with validation
    if [[ $STATIC_IP =~ ^10\.8\.0\. ]]; then
        echo "ifconfig-push $STATIC_IP 255.255.255.0" > "${CCD_DIR}/$CLIENT"
    else
        log_error "IP address must be in the 10.8.0.0/24 range"
        return 1
    fi
    
    # Generate client configuration with error checking
    mkdir -p "${CLIENTS_DIR}/$CLIENT"
    if ! cp "${CONFIG_DIR}/client-template.txt" "${CLIENTS_DIR}/$CLIENT/$CLIENT.ovpn"; then
        handle_error "Failed to create client configuration"
    fi
    
    # Add certificates to client config with verification
    {
        echo "<ca>"
        cat "${SERVER_DIR}/ca.crt"
        echo "</ca>"
        echo "<cert>"
        cat "${EASYRSA_DIR}/pki/issued/$CLIENT.crt"
        echo "</cert>"
        echo "<key>"
        cat "${EASYRSA_DIR}/pki/private/$CLIENT.key"
        echo "</key>"
        echo "<tls-crypt>"
        cat "${SERVER_DIR}/ta.key"
        echo "</tls-crypt>"
    } >> "${CLIENTS_DIR}/$CLIENT/$CLIENT.ovpn"
    
    # Set secure permissions
    chmod 644 "${CCD_DIR}/$CLIENT"
    chmod -R 644 "${CLIENTS_DIR}/$CLIENT/$CLIENT.ovpn"
    
    log_success "Client $CLIENT added successfully"
    log_info "Configuration saved to: ${CLIENTS_DIR}/$CLIENT/$CLIENT.ovpn"

    # Create QR code for mobile devices
    if command -v qrencode &> /dev/null; then
        qrencode -t ansiutf8 < "${CLIENTS_DIR}/$CLIENT/$CLIENT.ovpn"
        log_info "Scan the QR code above with your OpenVPN mobile app"
    fi
}

# Enhanced backup function
function backup_configs() {
    local backup_name="openvpn-backup-$(date +%Y%m%d-%H%M%S)"
    local backup_path="${BACKUP_DIR}/${backup_name}"
    local backup_archive="${backup_path}.tar.gz"

    # Create backup directory
    mkdir -p "$backup_path"

    # Copy configurations
    cp -r "${CONFIG_DIR}"/* "$backup_path/"
    
    # Create compressed archive
    tar -czf "$backup_archive" -C "${BACKUP_DIR}" "$backup_name" &
    spinner $! "Creating backup archive..."

    # Clean up temporary directory
    rm -rf "$backup_path"

    # Keep only last 5 backups
    ls -t "${BACKUP_DIR}"/*.tar.gz | tail -n +6 | xargs -r rm

    log_success "Backup created at $backup_archive"
}

# Enhanced menu with new features
function manageMenu() {
    while true; do
        clear
        print_banner
        echo -e "${BOLD}OpenVPN Management Menu${NC}\n"
        echo "1) Client Management"
        echo "   a) Add new client"
        echo "   b) Remove existing client"
        echo "   c) List all clients"
        echo "   d) Show client details"
        echo "2) Server Management"
        echo "   a) Show server status"
        echo "   b) Restart server"
        echo "   c) Show live connections"
        echo "3) System Management"
        echo "   a) Create backup"
        echo "   b) Restore backup"
        echo "   c) View logs"
        echo "4) Exit"
        echo ""
        read -rp "Select an option: " choice
        echo ""
        
        case $choice in
            "1a")
                read -rp "Enter client name: " client_name
                read -rp "Enter static IP (e.g., 10.8.0.10): " static_ip
                addClient "$client_name" "$static_ip"
                ;;
            "1b")
                read -rp "Enter client name to remove: " client_name
                removeClient "$client_name"
                ;;
            "1c")
                echo -e "${BOLD}All Clients:${NC}\n"
                ls -1 "$CCD_DIR"
                ;;
            "1d")
                read -rp "Enter client name: " client_name
                if client_exists "$client_name"; then
                    echo -e "\n${BOLD}Client Details:${NC}"
                    cat "${CCD_DIR}/$client_name"
                    echo -e "\n${BOLD}Connection Status:${NC}"
                    grep "$client_name" "${LOG_DIR}/status.log"
                else
                    log_error "Client not found"
                fi
                ;;
            "2a")
                systemctl status openvpn@server
                ;;
            "2b")
                systemctl restart openvpn@server &
                spinner $! "Restarting OpenVPN server..."
                ;;
            "2c")
                watch -n 1 "cat ${LOG_DIR}/status.log"
                ;;
            "3a")
                backup_configs
                ;;
            "3b")
                echo -e "${BOLD}Available backups:${NC}"
                select backup in "${BACKUP_DIR}"/*.tar.gz; do
                    if [ -n "$backup" ]; then
                        tar -xzf "$backup" -C "$CONFIG_DIR" &
                        spinner $! "Restoring backup..."
                        systemctl restart openvpn@server
                        break
                    fi
                done
                ;;
            "3c")
                tail -f "${LOG_DIR}/openvpn.log"
                ;;
            "4")
                echo -e "\nThank you for using OpenVPN Static IP Manager!"
                exit 0
                ;;
            *)
                log_error "Invalid option"
                sleep 1
                ;;
        esac
        read -n 1 -s -r -p "Press any key to continue..."
    done
}

# Main script execution
trap 'handle_error "Script interrupted"' INT TERM

clear
print_banner
initialCheck

if [ ! -f "${CONFIG_DIR}/server.conf" ]; then
    log_info "Starting fresh OpenVPN installation..."
    installDependencies
    setupServer
    setupEasyRSA
    createClientTemplate
    systemctl enable openvpn@server &> /dev/null
    systemctl start openvpn@server &> /dev/null
    log_success "Installation completed successfully!"
    sleep 2
fi

manageMenu