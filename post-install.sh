#!/bin/bash

# ==============================================================================
#  3azmeo Post-Install Script
#  Version: 5.1 (Syntax Fix + Safe Execution)
# ==============================================================================

# --- Global Variables & Helper Functions ---
C_RESET='\033[0m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_BLUE='\033[0;34m'; C_YELLOW='\033[0;33m'
TARGET_USER="3azmeo"; DEL_USER="admini"
SSH_KEYS=(
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEVvU56TuxNQSV9mGwn0MyFJhs3cnEKMSdMxfQ9N7GTR 3azmeo-PC"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIECGEeiWmm+MCOL+9HanQ8vvIE8q+n6dkhpRKPI3PcGp EMERGENCY-BREAK-GLASS-KEY"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKAYh8HFwsLi5xR4wo2xrRTD17zJiKsS7lTiZ9NaYASN 3azmeo"
)
log_info() { echo -e "${C_BLUE}[INFO] $1${C_RESET}"; }
log_success() { echo -e "${C_GREEN}[SUCCESS] $1${C_RESET}"; }
log_error() { echo -e "${C_RED}[ERROR] $1${C_RESET}"; }
log_action() { echo -e "${C_YELLOW}[ACTION] $1${C_RESET}"; }
ask_yes_no() { while true; do read -p "$(echo -e "${C_YELLOW}[?] $1 [Y/n]: ${C_RESET}")" yn; case $yn in [Yy]*|"") return 0;; [Nn]*) return 1;; *) echo "Please answer with 'y' or 'n'.";; esac; done; }

# --- Script Header ---
print_header() {
    clear
    echo -e "${C_BLUE}=============================================${C_RESET}"
    echo -e "${C_BLUE}     3azmeo Post-Install Script v5.1       ${C_RESET}"
    echo -e "${C_BLUE}=============================================${C_RESET}"
    echo
}

# --- Package Management ---
detect_package_manager() {
    if command -v apt &> /dev/null; then PKG_MANAGER="apt"; INSTALL_CMD="apt install -y"; UPDATE_CMD="apt update"
    elif command -v dnf &> /dev/null; then PKG_MANAGER="dnf"; INSTALL_CMD="dnf install -y"; UPDATE_CMD=""
    elif command -v pacman &> /dev/null; then PKG_MANAGER="pacman"; INSTALL_CMD="pacman -S --noconfirm"; UPDATE_CMD="pacman -Sy"
    else log_error "Could not detect a known package manager. Exiting."; exit 1; fi
}

install_packages() {
    log_info "Checking and installing packages..."
    PACKAGES_TO_INSTALL=()
    BASE_PACKAGES=("curl" "nano" "sudo" "git" "wget" "fontconfig")
    for pkg in "${BASE_PACKAGES[@]}"; do if ! command -v "$pkg" &> /dev/null; then PACKAGES_TO_INSTALL+=("$pkg"); fi; done
    if ask_yes_no "Install 'htop' (interactive process viewer)?"; then PACKAGES_TO_INSTALL+=("htop"); fi
    if ask_yes_no "Install 'ufw' (uncomplicated firewall)?"; then PACKAGES_TO_INSTALL+=("ufw"); fi
    if ask_yes_no "Install 'nfs-common' (for NFS shares)?"; then if [ "$PKG_MANAGER" == "apt" ]; then PACKAGES_TO_INSTALL+=("nfs-common"); else PACKAGES_TO_INSTALL+=("nfs-utils"); fi; fi
    if ask_yes_no "Install 'unzip'?"; then PACKAGES_TO_INSTALL+=("unzip"); fi
    if [ ${#PACKAGES_TO_INSTALL[@]} -gt 0 ]; then
        log_action "The following packages will be installed: ${PACKAGES_TO_INSTALL[*]}"; if [ -n "$UPDATE_CMD" ]; then $UPDATE_CMD; fi; $INSTALL_CMD "${PACKAGES_TO_INSTALL[@]}"; log_success "Required packages have been installed."
    else log_info "No new packages to install."; fi
}

# --- Security Tools ---
setup_security_tool() {
    log_info "Setting up Intrusion Protection..."
    echo -e "Choose a tool:\n  1) CrowdSec (Modern)\n  2) Fail2Ban (Traditional)\n  3) None"
    read -p "$(echo -e "${C_YELLOW}[?] Enter your choice [1-3]: ${C_RESET}")" choice
    case $choice in
        1)
            log_action "Installing CrowdSec..."; curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | bash; apt install -y crowdsec
            if ask_yes_no "Install CrowdSec Firewall Bouncer?"; then apt install -y crowdsec-firewall-bouncer-iptables; fi
            systemctl enable --now crowdsec; log_success "CrowdSec installed."
            ;;
        2)
            log_action "Installing Fail2Ban..."; apt install -y fail2ban
            echo -e "[sshd]\nenabled = true" > /etc/fail2ban/jail.d/sshd.local
            systemctl enable --now fail2ban; log_success "Fail2Ban installed."
            ;;
        *) log_info "Skipping intrusion protection setup.";;
    esac
}

# --- User Management & SSH ---
manage_users() {
    log_info "Managing user accounts..."
