#!/bin/bash

# ==============================================================================
#  3azmeo Post-Install Script
#  Version: 4.0 (Full English)
#
#  This script prepares a minimal Linux server by:
#  - Interactively asking to install common/security packages.
#  - Managing users (deleting 'admini', creating/configuring '3azmeo').
#  - Setting up SSH key-based authentication and disabling password/root login.
#  - Installing and configuring Zsh, Oh My Zsh, and Powerlevel10k.
#  - Optionally installing Docker and configuring NFS mounts.
#  - Updating the system and rebooting.
# ==============================================================================

# --- Global Variables & Helper Functions ---

# Colors for better output
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_BLUE='\033[0;34m'
C_YELLOW='\033[0;33m'

# User and SSH keys configuration
TARGET_USER="3azmeo"
DEL_USER="admini"
SSH_KEYS=(
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEVvU56TuxNQSV9mGwn0MyFJhs3cnEKMSdMxfQ9N7GTR 3azmeo-PC"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIECGEeiWmm+MCOL+9HanQ8vvIE8q+n6dkhpRKPI3PcGp EMERGENCY-BREAK-GLASS-KEY"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKAYh8HFwsLi5xR4wo2xrRTD17zJiKsS7lTiZ9NaYASN 3azmeo"
)

# Helper functions for logging
log_info() { echo -e "${C_BLUE}[INFO] $1${C_RESET}"; }
log_success() { echo -e "${C_GREEN}[SUCCESS] $1${C_RESET}"; }
log_error() { echo -e "${C_RED}[ERROR] $1${C_RESET}"; }
log_action() { echo -e "${C_YELLOW}[ACTION] $1${C_RESET}"; }

# Function to ask Yes/No questions (Enter defaults to Yes)
ask_yes_no() {
    while true; do
        read -p "$(echo -e "${C_YELLOW}[?] $1 [Y/n]: ${C_RESET}")" yn
        case $yn in
            [Yy]*|"" ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer with 'y' or 'n'.";;
        esac
    done
}

# --- Script Header ---
print_header() {
    clear
    echo -e "${C_BLUE}=============================================${C_RESET}"
    echo -e "${C_BLUE}     3azmeo Post-Install Script v4.0       ${C_RESET}"
    echo -e "${C_BLUE}=============================================${C_RESET}"
    echo
}

# --- Package Management ---
detect_package_manager() {
    if command -v apt &> /dev/null; then
        PKG_MANAGER="apt"
        INSTALL_CMD="apt install -y"
        UPDATE_CMD="apt update"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        INSTALL_CMD="dnf install -y"
        UPDATE_CMD=""
    elif command -v pacman &> /dev/null; then
        PKG_MANAGER="pacman"
        INSTALL_CMD="pacman -S --noconfirm"
        UPDATE_CMD="pacman -Sy"
    else
        log_error "Could not detect a known package manager (apt, dnf, pacman). Exiting."
        exit 1
    fi
}

install_packages() {
    log_info "Checking and installing packages..."
    PACKAGES_TO_INSTALL=()
    BASE_PACKAGES=("curl" "nano" "sudo" "git" "wget")
    for pkg in "${BASE_PACKAGES[@]}"; do
        if ! command -v "$pkg" &> /dev/null; then PACKAGES_TO_INSTALL+=("$pkg"); fi
    done
    if ask_yes_no "Install 'htop' (interactive process viewer)?"; then PACKAGES_TO_INSTALL+=("htop"); fi
    if ask_yes_no "Install 'ufw' (uncomplicated firewall)?"; then PACKAGES_TO_INSTALL+=("ufw"); fi
    if ask_yes_no "Install 'nfs-common' (for NFS shares)?"; then
        if [ "$PKG_MANAGER" == "apt" ]; then PACKAGES_TO_INSTALL+=("nfs-common"); else PACKAGES_TO_INSTALL+=("nfs-utils"); fi
    fi
    if ask_yes_no "Install 'unzip'?"; then PACKAGES_TO_INSTALL+=("unzip"); fi
    
    if [ ${#PACKAGES_TO_INSTALL[@]} -gt 0 ]; then
        log_action "The following packages will be installed: ${PACKAGES_TO_INSTALL[*]}"
        if [ -n "$UPDATE_CMD" ]; then $UPDATE_CMD; fi
        $INSTALL_CMD "${PACKAGES_TO_INSTALL[@]}"
        log_success "Required packages have been installed."
    else
        log_info "No new packages to install."
    fi
}

setup_security_tool() {
    log_info "Setting up Intrusion Protection..."
    echo -e "Choose a tool:"
    echo -e "  ${C_YELLOW}1)${C_RESET} CrowdSec (Modern, community-based, recommended)"
    echo -e "  ${C_YELLOW}2)${C_RESET} Fail2Ban (Traditional, simpler)"
    echo -e "  ${C_YELLOW}3)${C_RESET} None (Skip this step)"
    read -p "$(echo -e "${C_YELLOW}[?] Enter your choice [1-3]: ${C_RESET}")" choice
    case $choice in
        1)
            log_action "Installing CrowdSec..."
            curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | bash
            apt install crowdsec -y
            if ask_yes_no "Install CrowdSec Firewall Bouncer? (Recommended to actually block attacks)"; then
                apt install crowdsec-firewall-bouncer-iptables -y
            fi
            systemctl enable --now crowdsec
            log_success "CrowdSec installed and enabled."
            ;;
        2)
            log_action "Installing and configuring Fail2Ban..."
            apt install fail2ban -y
            echo -e "[sshd]\nenabled = true" > /etc/fail2ban/jail.d/sshd.local
            systemctl enable --now fail2ban
            log_success "Fail2Ban installed and enabled for SSH protection."
            ;;
        *) log_info "Skipping intrusion protection setup." ;;
    esac
}

# --- User Management & SSH ---
manage_users() {
    log_info "Managing user accounts..."
    if id "$DEL_USER" &>/dev/null; then
        log_action "User '$DEL_USER' found. Deleting..."
        userdel -r "$DEL_USER" &>/dev/null
    fi
    if ! id "$TARGET_USER" &>/dev/null; then
        log_action "User '$TARGET_USER' not found. Creating..."
        adduser "$TARGET_USER" --force-badname --gecos ""
    fi
    log_info "Granting sudo privileges to '$TARGET_USER'..."
    SUDO_GROUP="sudo"
    if ! getent group "$SUDO_GROUP" &>/dev/null; then SUDO_GROUP="wheel"; fi
    usermod -aG "$SUDO_GROUP" "$TARGET_USER"
}
setup_ssh_keys() {
    log_info "Setting up SSH keys for user '$TARGET_USER'..."
    local user_home; user_home=$(eval echo "~$TARGET_USER")
    local ssh_dir="$user_home/.ssh"
    mkdir -p "$ssh_dir"
    cat << EOF > "$ssh_dir/authorized_keys"
${SSH_KEYS[0]}
${SSH_KEYS[1]}
${SSH_KEYS[2]}
EOF
    chmod 700 "$ssh_dir"; chmod 600 "$ssh_dir/authorized_keys"
    chown -R "${TARGET_USER}:${TARGET_USER}" "$ssh_dir"
    log_success "SSH keys configured."
}
harden_ssh_server() {
    log_info "Hardening SSH server configuration..."
    sed -i -E 's/^#?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i -E 's/^#?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    log_success "Disabled root login and password authentication."
    systemctl restart sshd || systemctl restart ssh
}

# --- Oh My Zsh + Powerlevel10k ---
setup_zsh_p10k() {
    if ask_yes_no "Install Oh-My-Zsh + Powerlevel10k theme for user '$TARGET_USER'? ✨"; then
        log_info "Installing Zsh and Powerlevel10k..."
        
        if ! command -v zsh &> /dev/null; then
            log_action "Zsh not found. Installing..."
            $INSTALL_CMD zsh
        fi

        log_action "Changing default shell for '$TARGET_USER' to Zsh."
        chsh -s "$(which zsh)" "$TARGET_USER"

        log_action "Installing Oh My Zsh for '$TARGET_USER'..."
        sudo -u "$TARGET_USER" sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh) -s -- --unattended"
        
        log_action "Installing Powerlevel10k theme..."
        p10k_path="/home/$TARGET_USER/.oh-my-zsh/custom/themes/powerlevel10k"
        sudo -u "$TARGET_USER" git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_path"
        
        zshrc_path="/home/$TARGET_USER/.zshrc"
        sudo -u "$TARGET_USER" sed -i 's/^ZSH_THEME=".*"/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$zshrc_path"
        log_success "Zsh, Oh My Zsh, and Powerlevel10k have been installed and activated."
        
        echo
        log_action "!!! 🚨 IMPORTANT: MANUAL ACTION REQUIRED FOR FONTS 🚨 !!!"
        echo -e "${C_YELLOW}To display the theme correctly, you MUST install a 'Nerd Font' on your **local computer**."
        echo -e "${C_YELLOW}This script CANNOT install fonts on your personal machine. This is a manual step."
        echo -e "${C_YELLOW}   - Recommended Font: MesloLGS NF. Download and instructions are here:"
        echo -e "     ${C_GREEN}https://github.com/romkatv/powerlevel10k#meslo-nerd-font-patched-for-powerlevel10k${C_RESET}"
        echo -e "${C_YELLOW}After installing the font on your PC, set your terminal (Windows Terminal, iTerm2, etc.) to use it."
        echo -e "${C_YELLOW}The Powerlevel10k configuration wizard will start automatically the next time you log in."
        echo -e "${C_YELLOW}To re-run the wizard later, type: ${C_GREEN}p10k configure${C_RESET}"
        echo
    fi
}

# --- Optional Components ---
install_docker() {
    if ! command -v docker &> /dev/null; then
        if ask_yes_no "Docker not found. Install it now?"; then
            log_info "Installing Docker..."; curl -fsSL https://get.docker.com | sh
            usermod -aG docker "$TARGET_USER"
            log_success "Docker installed. You may need to log out and back in for group changes to apply."
        fi
    fi
}
configure_nfs_mounts() {
    if ask_yes_no "Setup and mount NFS shares?"; then
        if ! command -v mount.nfs &> /dev/null; then
            log_error "'mount.nfs' command not found. Please ensure you agreed to install 'nfs-common' earlier."
            return 1
        fi
        while ask_yes_no "Add a new NFS share to mount?"; do
            read -p "Enter remote share path (e.g., 10.0.0.4:/data): " remote_share
            read -p "Enter local directory name (inside /home/${TARGET_USER}/): " local_dir_name
            if [ -n "$remote_share" ] && [ -n "$local_dir_name" ]; then
                local_mount_path="/home/${TARGET_USER}/${local_dir_name}"
                fstab_entry="${remote_share} ${local_mount_path} nfs defaults,nofail,_netdev,bg 0 0"
                mkdir -p "$local_mount_path"
                chown "${TARGET_USER}:${TARGET_USER}" "$local_mount_path"
                log_info "Adding the following entry to /etc/fstab: ${fstab_entry}"
                echo "$fstab_entry" >> /etc/fstab
            fi
        done
        log_info "Attempting to mount all shares..."; mount -a
    fi
}

# --- System Finalization ---
update_and_clean_system() {
    if ask_yes_no "Update the entire system now?"; then
        log_info "Starting full system update and cleanup..."
        case $PKG_MANAGER in
            "apt") apt update && apt upgrade -y && apt dist-upgrade -y && apt autoremove -y && apt clean -y ;;
            "dnf") dnf upgrade -y && dnf autoremove -y ;;
            "pacman") pacman -Syu --noconfirm ;;
        esac
        log_success "System update complete."
    fi
}
final_reboot() {
    log_info "All tasks are complete."
    if ask_yes_no "Reboot the system now to apply all changes?"; then
        log_action "!!! REBOOTING in 5 seconds... !!!"
        sleep 5; reboot
    fi
}

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
    setup_zsh_p10k
    update_and_clean_system
    final_reboot
    echo -e "\n${C_GREEN}================== Script Finished ==================${C_RESET}"
}

main
