#!/bin/bash

# ==============================================================================
#  3azmeo Post-Install Script
#  Version: 8.0 (Simplified & Stable - Zsh/P10k Removed)
# ==============================================================================

# --- Self-Defense Check ---
# This script requires user interaction and MUST NOT be run via a pipe.
if ! [ -t 0 ]; then
    echo
    echo "[1;31mERROR: This script is interactive and cannot be run via a pipe (curl ... | bash).[0m"
    echo "[1;33mPlease download it first and then run it directly:[0m"
    echo "[1;32m1. curl -L -o setup.sh \"<URL_TO_YOUR_SCRIPT>\"[0m"
    echo "[1;32m2. chmod +x setup.sh[0m"
    echo "[1;32m3. ./setup.sh[0m"
    echo
    exit 1
fi

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
    echo -e "${C_BLUE}     3azmeo Post-Install Script v8.0       ${C_RESET}"
    echo -e "${C_BLUE}=============================================${C_RESET}"
    echo
}

# --- Package Management ---
detect_package_manager() {
    if command -v apt &> /dev/null; then PKG_MANAGER="apt"; INSTALL_CMD="apt install -y"; UPDATE_CMD="apt update"; elif command -v dnf &> /dev/null; then PKG_MANAGER="dnf"; INSTALL_CMD="dnf install -y"; UPDATE_CMD=""; elif command -v pacman &> /dev/null; then PKG_MANAGER="pacman"; INSTALL_CMD="pacman -S --noconfirm"; UPDATE_CMD="pacman -Sy"; else log_error "Could not detect a known package manager. Exiting."; exit 1; fi
}
install_packages() {
    log_info "Checking and installing packages..."
    PACKAGES_TO_INSTALL=(); BASE_PACKAGES=("curl" "nano" "sudo" "git" "wget")
    for pkg in "${BASE_PACKAGES[@]}"; do if ! command -v "$pkg" &> /dev/null; then PACKAGES_TO_INSTALL+=("$pkg"); fi; done
    if ask_yes_no "Install 'htop'?"; then PACKAGES_TO_INSTALL+=("htop"); fi
    if ask_yes_no "Install 'ufw'?"; then PACKAGES_TO_INSTALL+=("ufw"); fi
    if ask_yes_no "Install 'nfs-common' (for NFS shares)?"; then if [ "$PKG_MANAGER" == "apt" ]; then PACKAGES_TO_INSTALL+=("nfs-common"); else PACKAGES_TO_INSTALL+=("nfs-utils"); fi; fi
    if ask_yes_no "Install 'unzip'?"; then PACKAGES_TO_INSTALL+=("unzip"); fi
    if [ ${#PACKAGES_TO_INSTALL[@]} -gt 0 ]; then
        log_action "Installing: ${PACKAGES_TO_INSTALL[*]}"; if [ -n "$UPDATE_CMD" ]; then $UPDATE_CMD; fi; $INSTALL_CMD "${PACKAGES_TO_INSTALL[@]}"; log_success "Packages installed."
    else log_info "No new packages to install."; fi
}

# --- Security, Users, SSH, Docker, NFS ---
setup_security_tool() {
    log_info "Setting up Intrusion Protection..."; echo -e "Choose: 1) CrowdSec (Modern) 2) Fail2Ban 3) None"; read -p "$(echo -e "${C_YELLOW}[?] Choice [1-3]: ${C_RESET}")" choice
    case $choice in
        1) log_action "Installing CrowdSec..."; curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | bash; apt install -y crowdsec; if ask_yes_no "Install Firewall Bouncer?"; then apt install -y crowdsec-firewall-bouncer-iptables; fi; systemctl enable --now crowdsec;;
        2) log_action "Installing Fail2Ban..."; apt install -y fail2ban; echo -e "[sshd]\nenabled = true" > /etc/fail2ban/jail.d/sshd.local; systemctl enable --now fail2ban;;
        *) log_info "Skipping intrusion protection.";;
    esac
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
    log_info "Hardening SSH server..."; sed -i -E 's/^#?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config; sed -i -E 's/^#?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config; systemctl restart sshd || systemctl restart ssh
}
install_docker() {
    if ! command -v docker &> /dev/null; then
        if ask_yes_no "Install Docker?"; then
            log_info "Installing Docker..."; curl -fsSL https://get.docker.com -o get-docker.sh; sh get-docker.sh; rm get-docker.sh
            usermod -aG docker "$TARGET_USER"; log_success "Docker installed."
        fi
    fi
}
configure_nfs_mounts() { if ask_yes_no "Setup NFS shares?"; then if ! command -v mount.nfs &> /dev/null; then log_error "'mount.nfs' not found."; return 1; fi; while ask_yes_no "Add a new NFS share?"; do read -p "Remote path: " remote_share; read -p "Local dir name: " local_dir_name; if [ -n "$remote_share" ] && [ -n "$local_dir_name" ]; then local_mount_path="/home/${TARGET_USER}/${local_dir_name}"; fstab_entry="${remote_share} ${local_mount_path} nfs defaults,nofail,_netdev,bg 0 0"; mkdir -p "$local_mount_path"; chown "${TARGET_USER}:${TARGET_USER}" "$local_mount_path"; echo "$fstab_entry" >> /etc/fstab; fi; done; mount -a; fi; }

# --- System Finalization ---
update_and_clean_system() { if ask_yes_no "Update system now?"; then log_info "Updating system..."; case $PKG_MANAGER in "apt") apt update && apt upgrade -y && apt dist-upgrade -y && apt autoremove -y && apt clean -y;; "dnf") dnf upgrade -y && dnf autoremove -y;; "pacman") pacman -Syu --noconfirm;; esac; log_success "Update complete."; fi; }
final_reboot() { log_info "All tasks complete."; if ask_yes_no "Reboot now?"; then log_action "!!! REBOOTING in 5 seconds... !!!"; sleep 5; reboot; fi; }

# --- Main Execution ---
main() {
    print_header
    detect_package_manager
    install_packages
    setup_security_tool
    manage_users
    setup_ssh_keys
    harden_ssh_server
    install_docker
    configure_nfs_mounts
    update_and_clean_system
    final_reboot
    echo -e "\n${C_GREEN}================== Script Finished ==================${C_RESET}"
}

main
