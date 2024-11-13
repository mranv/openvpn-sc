#!/bin/bash
# Color definitions for the OpenVPN Static IP Manager
# Created with ❤️ by @mranv

# Regular Colors
export BLACK='\033[0;30m'
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export WHITE='\033[0;37m'

# Bold Colors
export BOLD_BLACK='\033[1;30m'
export BOLD_RED='\033[1;31m'
export BOLD_GREEN='\033[1;32m'
export BOLD_YELLOW='\033[1;33m'
export BOLD_BLUE='\033[1;34m'
export BOLD_PURPLE='\033[1;35m'
export BOLD_CYAN='\033[1;36m'
export BOLD_WHITE='\033[1;37m'

# Background Colors
export BG_BLACK='\033[40m'
export BG_RED='\033[41m'
export BG_GREEN='\033[42m'
export BG_YELLOW='\033[43m'
export BG_BLUE='\033[44m'
export BG_PURPLE='\033[45m'
export BG_CYAN='\033[46m'
export BG_WHITE='\033[47m'

# Special
export BOLD='\033[1m'
export DIM='\033[2m'
export UNDERLINE='\033[4m'
export BLINK='\033[5m'
export REVERSE='\033[7m'
export HIDDEN='\033[8m'

# Reset
export NC='\033[0m' # No Color

# Function to print colored text
print_color() {
    local color=$1
    local text=$2
    echo -e "${color}${text}${NC}"
}

# Function to print success message
print_success() {
    print_color "$GREEN" "✔ $1"
}

# Function to print error message
print_error() {
    print_color "$RED" "✖ $1"
}

# Function to print warning message
print_warning() {
    print_color "$YELLOW" "⚠ $1"
}

# Function to print info message
print_info() {
    print_color "$BLUE" "ℹ $1"
}

# Function to print header
print_header() {
    echo -e "\n${BOLD_BLUE}=== $1 ===${NC}\n"
}

# Function to print section
print_section() {
    echo -e "\n${BOLD_CYAN}--- $1 ---${NC}\n"
}