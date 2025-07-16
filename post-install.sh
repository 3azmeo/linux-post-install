#!/bin/bash

# ==============================================================================
#  3azmeo Universal Post-Install Script
#  Version: 10.0 (The Final One - Fully Interactive One-Liner)
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

# MODIFIED ask_yes_no: This version reads directly from the TTY (keyboard),
# making it interactive even when the script is run via a pipe (curl | bash).
ask_yes_no() {
    while true; do
        read -p "$(echo -e "${C_YELLOW}[?] $1 [Y/n]: ${C_RESET}")" yn < /dev/tty
        case $yn in
            [Yy]*|"") return 0;;
            [Nn]*) return 1;;
            *) echo "Please answer with 'y' or 'n'.";;
        esac
    done
}

# --- Script Header & Environment Detection ---
print_header() {
    clear
    echo -e "${C_BLUE}====================================================${C_RESET}"
    echo -e "${C_BLUE}     3azmeo Universal Post-Install Script v10.0     ${C_RESET}"
    echo -e "${C_BLUE}====================================================${C_RESET}"
    echo
}

detect_environment() {
    log_action "First, please identify the type of system this script is running on:"
    echo "  1. Standard Linux Server (e.g., Debian/Ubuntu VM)"
    echo "  2. Proxmox VE Host"
    local choice
    while true; do
        # Use the modified ask function for environment detection as well
        read -p "$(echo -e "${C_YELLOW}[?] Enter your choice [1-2]: ${C_RESET}")" choice < /dev/tty
        case $choice in
            1) ENV_TYPE="standard"; log_info "Mode set to: Standard Linux Server"; break;;
            2) ENV_TYPE="proxmox"; log_info "Mode set to: Proxmox VE Host. Some options will be disabled for safety."; break;;
            *) log_error "Invalid choice. Please enter 1 or 2.";;
        esac
    done
    echo
}

# --- Package Management ---
detect_package_manager() {
    if command -v apt &> /dev/null; then PKG_MANAGER="apt"; INSTALL_CMD="apt install -y"; UPDATE_CMD="apt update"; elif command -v dnf &> /dev/null; then PKG_MANAGER="dnf"; INSTALL_CMD="dnf install -y"; UPDATE_CMD=""; elif command -v pacman &> /dev/null; then PKG_MANAGER="pacman"; INSTALL_CMD="pacman -S --noconfirm"; UPDATE_CMD="pacman -Sy"; else log_error "Could not detect a known package manager. Exiting."; exit 1; fi
}
install_packages() {
    log_info "Checking and installing packages..."; PACKAGES_TO_INSTALL=(); BASE_PACKAGES=("curl" "nano" "sudo" "git" "wget")
    for pkg in "${BASE_PACKAGES[@]}"; do if ! command -v "$pkg" &> /dev/null; then PACKAGES_TO_INSTALL+=("$pkg"); fi; done
    if ask_yes_no "Install 'htop'?"; then PACKAGES_TO_INSTALL+=("htop"); fi
    if ask_yes_no "Install 'ufw'?"; then PACKAGES_TO_INSTALL+=("ufw"); fi
    if ask_yes_no "Install 'unzip'?"; then PACKAGES_TO_INSTALL+=("unzip"); fi
    if [ ${#PACKAGES_TO_INSTALL[@]} -gt 0 ]; then
        log_action "Installing: ${PACKAGES_TO_INSTALL[*]}"; if [ -n "$UPDATE_CMD" ]; then $UPDATE_CMD; fi; $INSTALL_CMD "${PACKAGES_TO_INSTALL[@]}"; log_success "Packages installed."
    else log_info "No new packages to install."; fi
}

# --- All other functions from here are safe to use ---
setup_security_tool() {
    if ask_yes_no "Install an intrusion protection tool (CrowdSec/Fail2Ban)?"; then
        log_info "Setting up Intrusion Protection..."; echo -e "Choose: 1) CrowdSec (Modern) 2) Fail2Ban 3) None"
        local choice
        read -p "$(echo -e "${C_YELLOW}[?] Choice [1-3]: ${C_RESET}")" choice < /dev/tty
        case $choice in
            1) log_action "Installing CrowdSec..."; curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | bash; apt install -y crowdsec; if ask_yes_no "Install Firewall Bouncer?"; then apt install -y crowdsec-firewall-bouncer-iptables; fi; systemctl enable --now crowdsec;;
            2) log_action "Installing Fail2Ban..."; apt install -y fail2ban; echo -e "[sshd]\nenabled = true" > /etc/fail2ban/jail.d/sshd.local; systemctl enable --now fail2ban;;
            *) log_info "Skipping intrusion protection.";;
        esac
    fi
}
manage_users() {
    log_info "Managing users..."; if id "$DEL_USER" &>/dev/null; then log_action "Deleting user '$DEL_USER'..."; userdel -r "$DEL_USER" &>/dev/null; fi
    if ! id "$TARGET_USER" &>/dev/null; then log_action "Creating user '$TARGET_USER'..."; adduser "$TARGET_USER" --force-badname --gecos ""; fi
    log_info "Granting sudo to '$TARGET_USER'..."; SUDO_GROUP="sudo"; if ! getent group "$SUDO_GROUP" &> /dev/null; then SUDO_GROUP="wheel"; fi; usermod -aG "$SUDO_GROUP" "$TARGET_USER"
}
setup_ssh_keys() {
    log_info "Setting up SSH keys for '$TARGET_USER'..."; local user_home; user_home=$(eval echo "~$TARGET_USER"); local ssh_dir="$user_home/.ssh"; mkdir -p "$ssh_dir"
    cat << EOF > "$ssh_dir/authorized_keys"
${SSH_KEYS[0]}
${SSH_KEYS[1]}
${SSH_KEYS[2]}
EOF
    chmod 700 "$ssh_dir"; chmod 600 "$ssh_dir/authorized_keys"; chown -R "${TARGET_USER}:${TARGET_USER}" "$ssh_dir"; log_success "SSH keys configured."
}
harden_ssh_server() {
    if ask_yes_no "Harden SSH server (disable root & password login)?"; then
        log_info "Hardening SSH server..."; sed -i -E 's/^#?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config; sed -i -E 's/^#?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config; systemctl restart sshd || systemctl restart ssh
        log_success "SSH server hardened."
    fi
}
install_docker() {
    if ! command -v docker &> /dev/null; then
        if ask_yes_no "Install Docker?"; then
            log_info "Installing Docker..."; curl -fsSL https://get.docker.com -o get-docker.sh; sh get-docker.sh; rm get-docker.sh
            usermod -aG docker "$TARGET_USER"; log_success "Docker installed."
        fi
    fi
}
configure_nfs_mounts() {
    if ask_yes_no "Setup NFS client mounts in /etc/fstab?"; then
        if ! command -v mount.nfs &> /dev/null; then
            log_action "NFS utilities not found. Installing 'nfs-common'..."; $INSTALL_CMD nfs-common;
        fi
        while ask_yes_no "Add a new NFS share?"; do
            local remote_share; local local_dir_name
            read -p "Enter remote share path: " remote_share < /dev/tty
            read -p "Enter local directory name: " local_dir_name < /dev/tty
            if [ -n "$remote_share" ] && [ -n "$local_dir_name" ]; then local_mount_path="/home/${TARGET_USER}/${local_dir_name}"; fstab_entry="${remote_share} ${local_mount_path} nfs defaults,nofail,_netdev,bg 0 0"; mkdir -p "$local_mount_path"; chown "${TARGET_USER}:${TARGET_USER}" "$local_mount_path"; echo "$fstab_entry" >> /etc/fstab; fi
        done
        log_info "Attempting to mount all shares..."; mount -a
    fi
}
update_and_clean_system() {
    if ask_yes_no "Run a full system update and upgrade now?"; then
        log_info "Starting full system update...";
        case $PKG_MANAGER in
            "apt") apt update && apt upgrade -y && apt dist-upgrade -y && apt autoremove -y && apt clean -y;;
            "dnf") dnf upgrade -y && dnf autoremove -y;;
            "pacman") pacman -Syu --noconfirm;;
        esac
        log_success "System update complete."
    fi
}
final_reboot() {
    log_info "All selected tasks are complete."; if ask_yes_no "Reboot now?"; then log_action "!!! REBOOTING in 5 seconds... !!!"; sleep 5; reboot; fi
}

# --- Main Execution ---
main() {
    print_header
    detect_environment
    detect_package_manager

    install_packages
    setup_security_tool
    manage_users
    setup_ssh_keys
    harden_ssh_server

    if [ "$ENV_TYPE" == "standard" ]; then
        install_docker
        configure_nfs_mounts
        update_and_clean_system
    else
        log_info "Skipping Docker installation on Proxmox VE. Use LXC containers or VMs instead."
        log_info "Skipping /etc/fstab NFS mounts. Add storage via Proxmox Web UI (Datacenter -> Storage)."
        log_info "Skipping full system upgrade. Manage Proxmox updates via the Web UI or 'pveupgrade'."
    fi

    final_reboot
    echo -e "\n${C_GREEN}================== Script Finished ==================${C_RESET}"
}

main
