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

# Default values
PORT="1194"
PROTOCOL="udp"
DNS="1" # Default to current system resolvers
COMPRESSION_ENABLED="n"
CUSTOMIZE_ENC="n"

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

# Function to check if running as root
function isRoot() {
    if [ "$EUID" -ne 0 ]; then
        return 1
    fi
}

# Function to check TUN/TAP device
function tunAvailable() {
    if [ ! -e /dev/net/tun ]; then
        return 1
    fi
}

# Operating System detection
function checkOS() {
    if [[ -e /etc/debian_version ]]; then
        OS="debian"
        source /etc/os-release

        if [[ $ID == "debian" || $ID == "raspbian" ]]; then
            if [[ $VERSION_ID -lt 9 ]]; then
                log_error "⚠️ Your version of Debian is not supported."
                echo ""
                echo "However, if you're using Debian >= 9 or unstable/testing then you can continue, at your own risk."
                echo ""
                until [[ $CONTINUE =~ (y|n) ]]; do
                    read -rp "Continue? [y/n]: " -e CONTINUE
                done
                if [[ $CONTINUE == "n" ]]; then
                    exit 1
                fi
            fi
        elif [[ $ID == "ubuntu" ]]; then
            OS="ubuntu"
            MAJOR_UBUNTU_VERSION=$(echo "$VERSION_ID" | cut -d '.' -f1)
            if [[ $MAJOR_UBUNTU_VERSION -lt 16 ]]; then
                log_error "⚠️ Your version of Ubuntu is not supported."
                echo ""
                echo "However, if you're using Ubuntu >= 16.04 or beta, then you can continue, at your own risk."
                echo ""
                until [[ $CONTINUE =~ (y|n) ]]; do
                    read -rp "Continue? [y/n]: " -e CONTINUE
                done
                if [[ $CONTINUE == "n" ]]; then
                    exit 1
                fi
            fi
        fi
    elif [[ -e /etc/system-release ]]; then
        source /etc/os-release
        if [[ $ID == "fedora" || $ID_LIKE == "fedora" ]]; then
            OS="fedora"
        fi
        if [[ $ID == "centos" || $ID == "rocky" || $ID == "almalinux" ]]; then
            OS="centos"
            if [[ ${VERSION_ID%.*} -lt 7 ]]; then
                log_error "⚠️ Your version of CentOS is not supported."
                echo ""
                echo "The script only supports CentOS 7 and CentOS 8."
                echo ""
                exit 1
            fi
        fi
        if [[ $ID == "ol" ]]; then
            OS="oracle"
            if [[ ! $VERSION_ID =~ (8) ]]; then
                log_error "Your version of Oracle Linux is not supported."
                echo ""
                echo "The script only supports Oracle Linux 8."
                exit 1
            fi
        fi
        if [[ $ID == "amzn" ]]; then
            OS="amzn"
            if [[ $VERSION_ID != "2" ]]; then
                log_error "⚠️ Your version of Amazon Linux is not supported."
                echo ""
                echo "The script only supports Amazon Linux 2."
                echo ""
                exit 1
            fi
        fi
    elif [[ -e /etc/arch-release ]]; then
        OS=arch
    else
        log_error "Looks like you aren't running this installer on a supported system"
        exit 1
    fi
    log_success "Operating system check passed: $OS"
}

# Initial system checks
function initialCheck() {
    if ! isRoot; then
        log_error "Sorry, you need to run this as root"
        exit 1
    fi
    if ! tunAvailable; then
        log_error "TUN is not available"
        exit 1
    fi
    checkOS
}

# Install required dependencies
function installDependencies() {
    log_info "Installing required packages..."
    
    if [[ $OS =~ (debian|ubuntu) ]]; then
        apt-get update &> /dev/null &
        spinner $! "Updating package lists..."
        apt-get install -y openvpn easy-rsa curl wget ca-certificates gnupg &> /dev/null &
        spinner $! "Installing OpenVPN and dependencies..."
    elif [[ $OS =~ (centos|amzn|oracle) ]]; then
        yum install -y epel-release &> /dev/null &
        spinner $! "Adding EPEL repository..."
        yum install -y openvpn easy-rsa curl wget ca-certificates &> /dev/null &
        spinner $! "Installing OpenVPN and dependencies..."
    elif [[ $OS == "fedora" ]]; then
        dnf install -y openvpn easy-rsa curl wget ca-certificates &> /dev/null &
        spinner $! "Installing OpenVPN and dependencies..."
    elif [[ $OS == "arch" ]]; then
        pacman -Syu --noconfirm openvpn easy-rsa curl wget ca-certificates &> /dev/null &
        spinner $! "Installing OpenVPN and dependencies..."
    fi
    
    log_success "Dependencies installed successfully"
}

# Validate IP address
function validate_ip() {
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
function client_exists() {
    local client_name=$1
    [[ -f "${CCD_DIR}/${client_name}" ]]
}

# Setup IPv6 support
function setupIPv6() {
    log_info "Checking IPv6 connectivity..."
    
    if type ping6 >/dev/null 2>&1; then
        PING6="ping6 -c3 ipv6.google.com > /dev/null 2>&1"
    else
        PING6="ping -6 -c3 ipv6.google.com > /dev/null 2>&1"
    fi
    
    if eval "$PING6"; then
        log_success "IPv6 connectivity detected"
        IPV6_SUPPORT="y"
    else
        log_warning "No IPv6 connectivity detected"
        IPV6_SUPPORT="n"
    fi
}

# Resolve Public IP
function resolvePublicIP() {
    # IP version flags, we'll use as default the IPv4
    CURL_IP_VERSION_FLAG="-4"
    DIG_IP_VERSION_FLAG="-4"

    # Set IPv6 flags if IPv6 is supported
    if [[ $IPV6_SUPPORT == "y" ]]; then
        CURL_IP_VERSION_FLAG=""
        DIG_IP_VERSION_FLAG="-6"
    fi

    # Try multiple services to get public IP
    if [[ -z $PUBLIC_IP ]]; then
        PUBLIC_IP=$(curl -f -m 5 -sS --retry 2 --retry-connrefused "$CURL_IP_VERSION_FLAG" https://api.seeip.org 2>/dev/null)
    fi

    if [[ -z $PUBLIC_IP ]]; then
        PUBLIC_IP=$(curl -f -m 5 -sS --retry 2 --retry-connrefused "$CURL_IP_VERSION_FLAG" https://ifconfig.me 2>/dev/null)
    fi

    if [[ -z $PUBLIC_IP ]]; then
        PUBLIC_IP=$(curl -f -m 5 -sS --retry 2 --retry-connrefused "$CURL_IP_VERSION_FLAG" https://api.ipify.org 2>/dev/null)
    fi

    if [[ -z $PUBLIC_IP ]]; then
        PUBLIC_IP=$(dig $DIG_IP_VERSION_FLAG TXT +short o-o.myaddr.l.google.com @ns1.google.com | tr -d '"')
    fi

    if [[ -z $PUBLIC_IP ]]; then
        log_error "Couldn't resolve public IP address"
        exit 1
    fi

    echo "$PUBLIC_IP"
}

# Setup EasyRSA
function setupEasyRSA() {
    log_info "Setting up PKI infrastructure..."
    
    # Install EasyRSA
    mkdir -p "$EASYRSA_DIR"
    local version="3.1.2"
    wget -O ~/easy-rsa.tgz "https://github.com/OpenVPN/easy-rsa/releases/download/v${version}/EasyRSA-${version}.tgz" &> /dev/null &
    spinner $! "Downloading EasyRSA..."
    
    tar xzf ~/easy-rsa.tgz --strip-components=1 --directory "$EASYRSA_DIR"
    rm -f ~/easy-rsa.tgz
    
    cd "$EASYRSA_DIR" || handle_error "Failed to access EasyRSA directory"
    
    # Setup vars
    cat > vars << EOF
set_var EASYRSA_ALGO "ec"
set_var EASYRSA_CURVE "prime256v1"
set_var EASYRSA_KEY_SIZE "4096"
set_var EASYRSA_DIGEST "sha384"
set_var EASYRSA_CA_EXPIRE "3650"
set_var EASYRSA_CERT_EXPIRE "1080"
EOF
    
    # Initialize PKI
    ./easyrsa init-pki &> /dev/null &
    spinner $! "Initializing PKI..."
    
    # Build CA
    echo -ne '\n' | ./easyrsa build-ca nopass &> /dev/null &
    spinner $! "Building CA..."
    
    # Generate server certificates
    ./easyrsa build-server-full server nopass &> /dev/null &
    spinner $! "Generating server certificates..."
    
    # Generate DH parameters
    ./easyrsa gen-dh &> /dev/null &
    spinner $! "Generating DH parameters..."
    
    # Generate TLS key
    openvpn --genkey --secret ta.key &> /dev/null &
    spinner $! "Generating TLS key..."
    
    # Copy certificates
    cp pki/ca.crt pki/issued/server.crt pki/private/server.key pki/dh.pem ta.key "$SERVER_DIR/"
    
    log_success "PKI setup completed"
}

# Setup server configuration
function setupServer() {
    log_info "Setting up OpenVPN server..."
    
    # Create required directories
    mkdir -p "$SERVER_DIR" "$CCD_DIR" "$CLIENTS_DIR" "$LOG_DIR"
    
    # Generate server configuration
    cat > "${CONFIG_DIR}/server.conf" << EOF
# OpenVPN Server Configuration
# Generated by Modern OpenVPN Static IP Manager
# Created with ❤️ by @mranv

# Network Settings
port $PORT
proto $PROTOCOL
dev tun

# Certificates
ca $SERVER_DIR/ca.crt
cert $SERVER_DIR/server.crt
key $SERVER_DIR/server.key
dh $SERVER_DIR/dh.pem

# Network Configuration
topology subnet
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt

# Static IP Configurations
client-config-dir $CCD_DIR

# Security Settings
cipher AES-256-GCM
auth SHA384
tls-crypt $SERVER_DIR/ta.key
tls-version-min 1.2
ncp-ciphers AES-256-GCM:AES-128-GCM

# Performance Settings
keepalive 10 120
persist-key
persist-tun
user nobody
group nogroup

# Logging
status $LOG_DIR/status.log
log-append $LOG_DIR/openvpn.log
verb 3

# Push Settings
push "redirect-gateway def1 bypass-dhcp"
EOF

    # Add DNS configuration based on choice
    case $DNS in
        1) # Current system resolvers
            if grep -q "127.0.0.53" "/etc/resolv.conf"; then
                RESOLVCONF='/run/systemd/resolve/resolv.conf'
            else
                RESOLVCONF='/etc/resolv.conf'
            fi
            sed -ne 's/^nameserver[[:space:]]\+\([^[:space:]]\+\).*$/\1/p' $RESOLVCONF | while read -r line; do
                if [[ $line =~ ^[0-9.]*$ ]] || [[ $IPV6_SUPPORT == 'y' ]]; then
                    echo "push \"dhcp-option DNS $line\"" >> "${CONFIG_DIR}/server.conf"
                fi
            done
            ;;
        2) # Self-hosted DNS (Unbound)
            echo 'push "dhcp-option DNS 10.8.0.1"' >> "${CONFIG_DIR}/server.conf"
            if [[ $IPV6_SUPPORT == 'y' ]]; then
                echo 'push "dhcp-option DNS fd42:42:42:42::1"' >> "${CONFIG_DIR}/server.conf"
            fi
            ;;
        3) # Cloudflare
            echo 'push "dhcp-option DNS 1.1.1.1"' >> "${CONFIG_DIR}/server.conf"
            echo 'push "dhcp-option DNS 1.0.0.1"' >> "${CONFIG_DIR}/server.conf"
            ;;
        4) # Google
            echo 'push "dhcp-option DNS 8.8.8.8"' >> "${CONFIG_DIR}/server.conf"
            echo 'push "dhcp-option DNS 8.8.4.4"' >> "${CONFIG_DIR}/server.conf"
            ;;
    esac

    # Add IPv6 support if enabled
    if [[ $IPV6_SUPPORT == 'y' ]]; then
        echo "server-ipv6 fd42:42:42:42::/112
tun-ipv6
push tun-ipv6
push \"route-ipv6 2000::/3\"
push \"redirect-gateway ipv6\"" >> "${CONFIG_DIR}/server.conf"
    fi

    # Enable compression if requested
    if [[ $COMPRESSION_ENABLED == "y" ]]; then
        echo "compress lz4-v2" >> "${CONFIG_DIR}/server.conf"
    fi
    
    log_success "Server configuration completed"
}

# Setup firewall rules
function setupFirewall() {
    log_info "Setting up firewall rules..."

    # Get the "public" interface from the default route
    NIC=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    if [[ -z $NIC ]] && [[ $IPV6_SUPPORT == 'y' ]]; then
        NIC=$(ip -6 route show default | sed -ne 's/^default .* dev \([^ ]*\) .*$/\1/p')
    fi

    # Create iptables directory
    mkdir -p /etc/iptables

    # Create the script to add rules
    cat > /etc/iptables/add-openvpn-rules.sh << EOF
#!/bin/sh
iptables -t nat -I POSTROUTING 1 -s 10.8.0.0/24 -o $NIC -j MASQUERADE
iptables -I INPUT 1 -i tun0 -j ACCEPT
iptables -I FORWARD 1 -i $NIC -o tun0 -j ACCEPT
iptables -I FORWARD 1 -i tun0 -o $NIC -j ACCEPT
iptables -I INPUT 1 -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT
EOF

    # Add IPv6 rules if enabled
    if [[ $IPV6_SUPPORT == 'y' ]]; then
        cat >> /etc/iptables/add-openvpn-rules.sh << EOF
ip6tables -t nat -I POSTROUTING 1 -s fd42:42:42:42::/112 -o $NIC -j MASQUERADE
ip6tables -I INPUT 1 -i tun0 -j ACCEPT
ip6tables -I FORWARD 1 -i $NIC -o tun0 -j ACCEPT
ip6tables -I FORWARD 1 -i tun0 -o $NIC -j ACCEPT
ip6tables -I INPUT 1 -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT
EOF
    fi

    # Create the script to remove rules
    cat > /etc/iptables/rm-openvpn-rules.sh << EOF
#!/bin/sh
iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -o $NIC -j MASQUERADE
iptables -D INPUT -i tun0 -j ACCEPT
iptables -D FORWARD -i $NIC -o tun0 -j ACCEPT
iptables -D FORWARD -i tun0 -o $NIC -j ACCEPT
iptables -D INPUT -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT
EOF

    # Add IPv6 removal rules if enabled
    if [[ $IPV6_SUPPORT == 'y' ]]; then
        cat >> /etc/iptables/rm-openvpn-rules.sh << EOF
ip6tables -t nat -D POSTROUTING -s fd42:42:42:42::/112 -o $NIC -j MASQUERADE
ip6tables -D INPUT -i tun0 -j ACCEPT
ip6tables -D FORWARD -i $NIC -o tun0 -j ACCEPT
ip6tables -D FORWARD -i tun0 -o $NIC -j ACCEPT
ip6tables -D INPUT -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT
EOF
    fi

    chmod +x /etc/iptables/add-openvpn-rules.sh
    chmod +x /etc/iptables/rm-openvpn-rules.sh

    # Create systemd service for iptables
    cat > /etc/systemd/system/iptables-openvpn.service << EOF
[Unit]
Description=iptables rules for OpenVPN
Before=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/etc/iptables/add-openvpn-rules.sh
ExecStop=/etc/iptables/rm-openvpn-rules.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # Enable and start the service
    systemctl daemon-reload
    systemctl enable iptables-openvpn &> /dev/null
    systemctl start iptables-openvpn &> /dev/null

    log_success "Firewall rules configured"

    # Handle SELinux if enabled
    if hash sestatus 2>/dev/null; then
        if sestatus | grep "Current mode" | grep -qs "enforcing"; then
            if [[ $PORT != '1194' ]]; then
                semanage port -a -t openvpn_port_t -p "$PROTOCOL" "$PORT"
            fi
        fi
    fi
}

# Setup client template
function createClientTemplate() {
    log_info "Creating client template..."
    
    # Get public IP
    PUBLIC_IP=$(resolvePublicIP)
    
    # Create client template
    cat > "${CONFIG_DIR}/client-template.txt" << EOF
# OpenVPN Client Configuration
# Generated by Modern OpenVPN Static IP Manager
# Created with ❤️ by @mranv

client
dev tun
proto $PROTOCOL
remote $PUBLIC_IP $PORT
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
auth SHA384
key-direction 1
verb 3
tls-version-min 1.2
EOF

    # Add compression if enabled
    if [[ $COMPRESSION_ENABLED == "y" ]]; then
        echo "compress lz4-v2" >> "${CONFIG_DIR}/client-template.txt"
    fi

    # Add explicit-exit-notify for UDP
    if [[ $PROTOCOL == "udp" ]]; then
        echo "explicit-exit-notify" >> "${CONFIG_DIR}/client-template.txt"
    fi

    log_success "Client template created"
}

# Generate client configuration
function generateClientConfig() {
    local CLIENT=$1
    local STATIC_IP=$2
    
    log_info "Generating configuration for client: $CLIENT"

    # Create client directories
    mkdir -p "${CLIENTS_DIR}/$CLIENT"
    
    # Copy base template
    cp "${CONFIG_DIR}/client-template.txt" "${CLIENTS_DIR}/$CLIENT/$CLIENT.ovpn"
    
    # Add certificates and keys
    {
        echo "<ca>"
        cat "$SERVER_DIR/ca.crt"
        echo "</ca>"
        
        echo "<cert>"
        cat "${EASYRSA_DIR}/pki/issued/$CLIENT.crt"
        echo "</cert>"
        
        echo "<key>"
        cat "${EASYRSA_DIR}/pki/private/$CLIENT.key"
        echo "</key>"
        
        echo "<tls-crypt>"
        cat "$SERVER_DIR/ta.key"
        echo "</tls-crypt>"
    } >> "${CLIENTS_DIR}/$CLIENT/$CLIENT.ovpn"
    
    # Create CCD file for static IP
    echo "ifconfig-push $STATIC_IP 255.255.255.0" > "${CCD_DIR}/$CLIENT"
    
    # Set permissions
    chmod 644 "${CCD_DIR}/$CLIENT"
    chmod 644 "${CLIENTS_DIR}/$CLIENT/$CLIENT.ovpn"
    
    log_success "Client configuration generated: ${CLIENTS_DIR}/$CLIENT/$CLIENT.ovpn"
}

# Install Unbound DNS
function installUnbound() {
    log_info "Installing Unbound DNS resolver..."

    if [[ ! -e /etc/unbound/unbound.conf ]]; then
        case $OS in
            debian|ubuntu)
                apt-get install -y unbound &> /dev/null &
                spinner $! "Installing Unbound..."
                ;;
            centos|amzn|oracle)
                yum install -y unbound &> /dev/null &
                spinner $! "Installing Unbound..."
                ;;
            fedora)
                dnf install -y unbound &> /dev/null &
                spinner $! "Installing Unbound..."
                ;;
            arch)
                pacman -Syu --noconfirm unbound &> /dev/null &
                spinner $! "Installing Unbound..."
                curl -o /etc/unbound/root.hints https://www.internic.net/domain/named.cache
                ;;
        esac

        # Configure Unbound
        cat >> /etc/unbound/unbound.conf << EOF

# OpenVPN DNS Configuration
server:
    interface: 10.8.0.1
    access-control: 10.8.0.1/24 allow
    hide-identity: yes
    hide-version: yes
    use-caps-for-id: yes
    prefetch: yes
    private-address: 10.0.0.0/8
    private-address: fd42:42:42:42::/112
    private-address: 172.16.0.0/12
    private-address: 192.168.0.0/16
    private-address: 169.254.0.0/16
    private-address: fd00::/8
    private-address: fe80::/10
    private-address: 127.0.0.0/8
    private-address: ::ffff:0:0/96
EOF

        if [[ $IPV6_SUPPORT == 'y' ]]; then
            echo "    interface: fd42:42:42:42::1
    access-control: fd42:42:42:42::/112 allow" >> /etc/unbound/unbound.conf
        fi

        systemctl enable unbound &> /dev/null
        systemctl restart unbound &> /dev/null
        log_success "Unbound DNS installed and configured"
    else
        log_warning "Unbound is already installed"
    fi
}

# Enhanced client management functions
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

    # Validate IP address format
    if ! validate_ip "$STATIC_IP"; then
        log_error "Invalid IP address format"
        return 1
    }

    # Validate IP range
    if [[ ! $STATIC_IP =~ ^10\.8\.0\. ]]; then
        log_error "IP address must be in the 10.8.0.0/24 range"
        return 1
    fi

    # Check if client already exists
    if client_exists "$CLIENT"; then
        log_error "Client $CLIENT already exists"
        return 1
    }
    
    log_info "Starting client certificate generation for $CLIENT..."
    
    # Generate client certificates
    cd "$EASYRSA_DIR" || handle_error "Failed to access EasyRSA directory"
    
    # Generate client key and certificate
    {
        ./easyrsa gen-req "$CLIENT" nopass &> /dev/null && \
        echo -ne '\n' | ./easyrsa sign-req client "$CLIENT" &> /dev/null
    } & spinner $! "Generating certificates..."

    # Generate client configuration
    generateClientConfig "$CLIENT" "$STATIC_IP"
    
    # Generate QR code if available
    if command -v qrencode &> /dev/null; then
        log_info "Generating QR code for mobile devices..."
        qrencode -t ansiutf8 < "${CLIENTS_DIR}/$CLIENT/$CLIENT.ovpn"
        log_info "Scan the QR code above with your OpenVPN mobile app"
    fi

    log_success "Client $CLIENT added successfully"
    log_info "Configuration file: ${CLIENTS_DIR}/$CLIENT/$CLIENT.ovpn"
}

# Function to remove a client
function removeClient() {
    if [ -z "$1" ]; then
        log_error "Usage: removeClient client_name"
        return 1
    fi
    
    local CLIENT=$1
    
    # Check if client exists
    if ! client_exists "$CLIENT"; then
        log_error "Client $CLIENT does not exist"
        return 1
    }
    
    log_warning "Removing client $CLIENT..."
    
    # Revoke certificate
    cd "$EASYRSA_DIR" || handle_error "Failed to access EasyRSA directory"
    ./easyrsa revoke "$CLIENT" &> /dev/null &
    spinner $! "Revoking certificate..."
    
    # Generate new CRL
    ./easyrsa gen-crl &> /dev/null &
    spinner $! "Generating new CRL..."
    
    # Update CRL file
    cp -f pki/crl.pem "$SERVER_DIR/crl.pem"
    chmod 644 "$SERVER_DIR/crl.pem"
    
    # Remove client files
    rm -f "${CCD_DIR}/$CLIENT"
    rm -rf "${CLIENTS_DIR}/$CLIENT"
    
    # Restart OpenVPN service
    systemctl restart openvpn@server &> /dev/null &
    spinner $! "Restarting OpenVPN server..."
    
    log_success "Client $CLIENT removed successfully"
}

# Function to list all clients
function listClients() {
    log_info "List of all clients:"
    echo -e "\n${BOLD}Client Name     Static IP       Status${NC}"
    echo "----------------------------------------"
    
    for client in "$CCD_DIR"/*; do
        if [ -f "$client" ]; then
            client_name=$(basename "$client")
            static_ip=$(grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' "$client")
            
            # Check if client is connected
            if grep -q "$client_name" "$LOG_DIR/status.log" 2>/dev/null; then
                status="${GREEN}Connected${NC}"
            else
                status="${YELLOW}Disconnected${NC}"
            fi
            
            printf "%-15s %-15s %s\n" "$client_name" "$static_ip" "$status"
        fi
    done
    echo ""
}

# Function to show client details
function showClientDetails() {
    local CLIENT=$1
    
    if ! client_exists "$CLIENT"; then
        log_error "Client $CLIENT does not exist"
        return 1
    fi
    
    echo -e "\n${BOLD}Client Details for $CLIENT${NC}\n"
    
    # Show static IP
    echo -e "${BOLD}Static IP:${NC}"
    cat "${CCD_DIR}/$CLIENT"
    
    # Show connection status
    echo -e "\n${BOLD}Connection Status:${NC}"
    if grep -q "$CLIENT" "$LOG_DIR/status.log" 2>/dev/null; then
        grep "$CLIENT" "$LOG_DIR/status.log" | \
        while read -r line; do
            local virtual_addr=$(echo "$line" | awk '{print $3}')
            local real_addr=$(echo "$line" | awk '{print $4}')
            local connected_since=$(echo "$line" | awk '{print $6, $7, $8}')
            
            echo "Virtual IP: $virtual_addr"
            echo "Real IP: $real_addr"
            echo "Connected since: $connected_since"
        done
    else
        echo "${YELLOW}Not currently connected${NC}"
    fi
    
    # Show certificate status
    echo -e "\n${BOLD}Certificate Status:${NC}"
    cd "$EASYRSA_DIR" || return
    ./easyrsa show-cert "$CLIENT" 2>/dev/null | grep -E "Serial Number:|Expires|Status:"
}

# Enhanced backup functionality
function backup_configs() {
    local backup_name="openvpn-backup-$(date +%Y%m%d-%H%M%S)"
    local backup_path="${BACKUP_DIR}/${backup_name}"
    local backup_archive="${backup_path}.tar.gz"

    log_info "Creating backup..."
    
    # Create backup directory
    mkdir -p "$backup_path"

    # Copy configurations
    cp -r "${CONFIG_DIR}"/* "$backup_path/" &> /dev/null &
    spinner $! "Copying configuration files..."
    
    # Create compressed archive
    tar -czf "$backup_archive" -C "${BACKUP_DIR}" "$backup_name" &> /dev/null &
    spinner $! "Creating backup archive..."

    # Clean up temporary directory
    rm -rf "$backup_path"

    # Keep only last 5 backups
    ls -t "${BACKUP_DIR}"/*.tar.gz | tail -n +6 | xargs -r rm

    log_success "Backup created at $backup_archive"
    
    # Calculate backup size
    local size=$(du -h "$backup_archive" | cut -f1)
    log_info "Backup size: $size"
}

# Function to restore from backup
function restoreBackup() {
    local backup_file=$1
    
    if [ ! -f "$backup_file" ]; then
        log_error "Backup file does not exist"
        return 1
    fi
    
    log_warning "Restoring from backup will overwrite current configuration"
    read -rp "Continue? [y/n]: " confirm
    
    if [[ $confirm == "y" ]]; then
        # Stop OpenVPN service
        systemctl stop openvpn@server &> /dev/null &
        spinner $! "Stopping OpenVPN service..."
        
        # Create temporary directory
        local temp_dir="/tmp/openvpn-restore"
        mkdir -p "$temp_dir"
        
        # Extract backup
        tar -xzf "$backup_file" -C "$temp_dir" &> /dev/null &
        spinner $! "Extracting backup..."
        
        # Copy files
        cp -r "$temp_dir"/* "$CONFIG_DIR/" &> /dev/null &
        spinner $! "Restoring configuration..."
        
        # Clean up
        rm -rf "$temp_dir"
        
        # Restart service
        systemctl restart openvpn@server &> /dev/null &
        spinner $! "Restarting OpenVPN service..."
        
        log_success "Backup restored successfully"
    else
        log_info "Restore cancelled"
    fi
}

# Function to monitor logs
function monitorLogs() {
    echo -e "${BOLD}OpenVPN Server Logs${NC}"
    echo "Press Ctrl+C to stop monitoring"
    echo "----------------------------------------"
    
    tail -f "$LOG_DIR/openvpn.log" 2>/dev/null || \
        log_error "Log file not found or not accessible"
}

# Interactive installation questions
function installQuestions() {
    echo -e "\n${BOLD}OpenVPN Installation Configuration${NC}"
    
    # Port selection
    echo -e "\n${BLUE}Port Selection${NC}"
    echo "1) Default: 1194"
    echo "2) Custom"
    echo "3) Random [49152-65535]"
    until [[ $PORT_CHOICE =~ ^[1-3]$ ]]; do
        read -rp "Select port option [1-3]: " -e -i 1 PORT_CHOICE
    done
    case $PORT_CHOICE in
        1) PORT="1194" ;;
        2)
            until [[ $PORT =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; do
                read -rp "Custom port [1-65535]: " -e -i 1194 PORT
            done
            ;;
        3)
            PORT=$(shuf -i49152-65535 -n1)
            log_info "Random port selected: $PORT"
            ;;
    esac
    
    # Protocol selection
    echo -e "\n${BLUE}Protocol Selection${NC}"
    echo "1) UDP (Recommended)"
    echo "2) TCP"
    until [[ $PROTOCOL_CHOICE =~ ^[1-2]$ ]]; do
        read -rp "Select protocol [1-2]: " -e -i 1 PROTOCOL_CHOICE
    done
    case $PROTOCOL_CHOICE in
        1) PROTOCOL="udp" ;;
        2) PROTOCOL="tcp" ;;
    esac
}

# Main menu function
function manageMenu() {
    while true; do
        clear
        print_banner
        echo -e "${BOLD}OpenVPN Management Menu${NC}\n"
        echo "1) Client Management"
        echo "   ${DIM}a) Add new client"
        echo "   b) Remove existing client"
        echo "   c) List all clients"
        echo "   d) Show client details${NC}"
        echo ""
        echo "2) Server Management"
        echo "   ${DIM}a) Show server status"
        echo "   b) Restart server"
        echo "   c) Show live connections"
        echo "   d) Change server port"
        echo "   e) Change protocol${NC}"
        echo ""
        echo "3) System Management"
        echo "   ${DIM}a) Create backup"
        echo "   b) Restore backup"
        echo "   c) View logs"
        echo "   d) Show system status${NC}"
        echo ""
        echo "4) Security Management"
        echo "   ${DIM}a) Update certificates"
        echo "   b) Show firewall rules"
        echo "   c) Change encryption settings${NC}"
        echo ""
        echo "5) Exit"
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
                listClients
                ;;
            "1d")
                read -rp "Enter client name: " client_name
                showClientDetails "$client_name"
                ;;
            "2a")
                systemctl status openvpn@server
                ;;
            "2b")
                systemctl restart openvpn@server &
                spinner $! "Restarting OpenVPN server..."
                log_success "Server restarted"
                ;;
            "2c")
                watch -n 1 "cat ${LOG_DIR}/status.log"
                ;;
            "2d")
                read -rp "Enter new port number: " new_port
                if [[ $new_port =~ ^[0-9]+$ ]] && [ "$new_port" -ge 1 ] && [ "$new_port" -le 65535 ]; then
                    sed -i "s/^port .*/port $new_port/" "${CONFIG_DIR}/server.conf"
                    systemctl restart openvpn@server
                    log_success "Port changed to $new_port"
                else
                    log_error "Invalid port number"
                fi
                ;;
            "2e")
                local current_proto=$(grep '^proto ' "${CONFIG_DIR}/server.conf" | cut -d' ' -f2)
                local new_proto=$([ "$current_proto" == "udp" ] && echo "tcp" || echo "udp")
                sed -i "s/^proto .*/proto $new_proto/" "${CONFIG_DIR}/server.conf"
                systemctl restart openvpn@server
                log_success "Protocol changed to $new_proto"
                ;;
            "3a")
                backup_configs
                ;;
            "3b")
                echo -e "${BOLD}Available backups:${NC}"
                select backup in "${BACKUP_DIR}"/*.tar.gz; do
                    if [ -n "$backup" ]; then
                        restoreBackup "$backup"
                        break
                    fi
                done
                ;;
            "3c")
                monitorLogs
                ;;
            "3d")
                echo -e "${BOLD}System Status:${NC}"
                echo "OpenVPN Version: $(openvpn --version | head -n1)"
                echo "System Load: $(uptime | awk -F'load average:' '{ print $2 }')"
                echo "Memory Usage: $(free -h | awk '/^Mem:/ {print $3 "/" $2}')"
                echo "Disk Usage: $(df -h / | awk 'NR==2 {print $3 "/" $2}')"
                ;;
            "4a")
                cd "$EASYRSA_DIR" || exit
                ./easyrsa gen-crl
                cp -f pki/crl.pem "$SERVER_DIR/crl.pem"
                chmod 644 "$SERVER_DIR/crl.pem"
                log_success "Certificates updated"
                ;;
            "4b")
                iptables -L -n -v | grep -E "OpenVPN|1194"
                if [[ $IPV6_SUPPORT == "y" ]]; then
                    ip6tables -L -n -v | grep -E "OpenVPN|1194"
                fi
                ;;
            "4c")
                log_warning "Changing encryption settings requires server restart"
                read -rp "Continue? [y/n]: " confirm
                if [[ $confirm == "y" ]]; then
                    installQuestions
                    setupServer
                    systemctl restart openvpn@server
                    log_success "Encryption settings updated"
                fi
                ;;
            "5")
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

# Main execution
main() {
    # Trap for cleanup
    trap 'handle_error "Script interrupted"' INT TERM

    # Clear screen and show banner
    clear
    print_banner

    # Perform initial checks
    initialCheck

    # Check if OpenVPN is already installed
    if [ ! -f "${CONFIG_DIR}/server.conf" ]; then
        log_info "Starting fresh OpenVPN installation..."
        installQuestions
        installDependencies
        setupServer
        setupEasyRSA
        createClientTemplate
        setupFirewall
        
        # Start OpenVPN service
        systemctl enable openvpn@server &> /dev/null
        systemctl start openvpn@server &> /dev/null
        log_success "Installation completed successfully!"
        sleep 2
    fi

    # Start management menu
    manageMenu
}

# Execute main function
main