#!/bin/bash

# ==============================================================================
#  3azmeo Post-Install Script
#  Version: 7.0 (Safe One-Liner + Auto Rainbow Theme)
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
    echo -e "${C_BLUE}     3azmeo Post-Install Script v7.0       ${C_RESET}"
    echo -e "${C_BLUE}=============================================${C_RESET}"
    echo
}

# --- Package Management ---
detect_package_manager() {
    if command -v apt &> /dev/null; then PKG_MANAGER="apt"; INSTALL_CMD="apt install -y"; UPDATE_CMD="apt update"; elif command -v dnf &> /dev/null; then PKG_MANAGER="dnf"; INSTALL_CMD="dnf install -y"; UPDATE_CMD=""; elif command -v pacman &> /dev/null; then PKG_MANAGER="pacman"; INSTALL_CMD="pacman -S --noconfirm"; UPDATE_CMD="pacman -Sy"; else log_error "Could not detect a known package manager. Exiting."; exit 1; fi
}

install_packages() {
    log_info "Checking and installing packages..."
    PACKAGES_TO_INSTALL=(); BASE_PACKAGES=("curl" "nano" "sudo" "git" "wget" "fontconfig")
    for pkg in "${BASE_PACKAGES[@]}"; do if ! command -v "$pkg" &> /dev/null; then PACKAGES_TO_INSTALL+=("$pkg"); fi; done
    if ask_yes_no "Install 'htop'?"; then PACKAGES_TO_INSTALL+=("htop"); fi
    if ask_yes_no "Install 'ufw'?"; then PACKAGES_TO_INSTALL+=("ufw"); fi
    if ask_yes_no "Install 'nfs-common'?"; then if [ "$PKG_MANAGER" == "apt" ]; then PACKAGES_TO_INSTALL+=("nfs-common"); else PACKAGES_TO_INSTALL+=("nfs-utils"); fi; fi
    if ask_yes_no "Install 'unzip'?"; then PACKAGES_TO_INSTALL+=("unzip"); fi
    if [ ${#PACKAGES_TO_INSTALL[@]} -gt 0 ]; then
        log_action "Installing: ${PACKAGES_TO_INSTALL[*]}"; if [ -n "$UPDATE_CMD" ]; then $UPDATE_CMD; fi; $INSTALL_CMD "${PACKAGES_TO_INSTALL[@]}"; log_success "Packages installed."
    else log_info "No new packages to install."; fi
}

# --- Security, Users, SSH, Docker, NFS (unchanged)---
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
install_docker() { if ! command -v docker &> /dev/null; then if ask_yes_no "Install Docker?"; then log_info "Installing Docker..."; curl -fsSL https://get.docker.com | sh; usermod -aG docker "$TARGET_USER"; fi; fi; }
configure_nfs_mounts() { if ask_yes_no "Setup NFS shares?"; then if ! command -v mount.nfs &> /dev/null; then log_error "'mount.nfs' not found."; return 1; fi; while ask_yes_no "Add a new NFS share?"; do read -p "Remote path: " remote_share; read -p "Local dir name: " local_dir_name; if [ -n "$remote_share" ] && [ -n "$local_dir_name" ]; then local_mount_path="/home/${TARGET_USER}/${local_dir_name}"; fstab_entry="${remote_share} ${local_mount_path} nfs defaults,nofail,_netdev,bg 0 0"; mkdir -p "$local_mount_path"; chown "${TARGET_USER}:${TARGET_USER}" "$local_mount_path"; echo "$fstab_entry" >> /etc/fstab; fi; done; mount -a; fi; }

# --- UPDATED: Oh My Zsh + Powerlevel10k (Auto Rainbow Theme) ---
setup_zsh_p10k() {
    if ask_yes_no "Install Oh-My-Zsh + Powerlevel10k theme for '$TARGET_USER'? ✨"; then
        log_info "Installing Zsh and Powerlevel10k..."
        if ! command -v zsh &> /dev/null; then log_action "Installing zsh..."; $INSTALL_CMD zsh; fi
        
        log_action "Installing MesloLGS NF fonts on the server..."; FONT_DIR="/usr/local/share/fonts/meslolgs_nf"; mkdir -p "$FONT_DIR"
        curl -L https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf -o "$FONT_DIR/MesloLGS NF Regular.ttf"
        curl -L https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf -o "$FONT_DIR/MesloLGS NF Bold.ttf"
        curl -L https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf -o "$FONT_DIR/MesloLGS NF Italic.ttf"
        curl -L https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf -o "$FONT_DIR/MesloLGS NF Bold Italic.ttf"
        log_info "Updating server font cache..."; fc-cache -f -v
        
        log_action "Changing default shell for '$TARGET_USER' to Zsh."; chsh -s "$(which zsh)" "$TARGET_USER"
        
        log_action "Installing Oh My Zsh for '$TARGET_USER'..."; sudo -u "$TARGET_USER" sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh) -s -- --unattended"
        log_action "Installing Powerlevel10k theme..."; p10k_path="/home/$TARGET_USER/.oh-my-zsh/custom/themes/powerlevel10k"; sudo -u "$TARGET_USER" git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_path"
        sudo -u "$TARGET_USER" sed -i 's/^ZSH_THEME=".*"/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "/home/$TARGET_USER/.zshrc"

        log_action "Automatically configuring Powerlevel10k with 'Rainbow' style..."
        P10K_CONFIG_PATH="/home/$TARGET_USER/.p10k.zsh"
        # Download the default config file from the official repo
        sudo -u "$TARGET_USER" curl -L -o "$P10K_CONFIG_PATH" "https://github.com/romkatv/powerlevel10k/raw/master/.p10k.zsh"
        # Automatically set the RAINBOW style
        sudo -u "$TARGET_USER" sed -i "s/typeset -g POWERLEVEL9K_STYLE='.*'/typeset -g POWERLEVEL9K_STYLE='RAINBOW'/" "$P10K_CONFIG_PATH"
        # Ensure the .zshrc sources the new .p10k.zsh file
        echo '[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh' | sudo -u "$TARGET_USER" tee -a "/home/$TARGET_USER/.zshrc" > /dev/null
        log_success "Powerlevel10k 'Rainbow' theme has been set automatically."
        
        echo; log_action "!!! 🚨 FINAL INSTRUCTIONS - VERY IMPORTANT 🚨 !!!"
        echo -e "${C_YELLOW}1. You MUST install the 'MesloLGS NF' font on your OWN PC to see icons correctly."
        echo -e "${C_YELLOW}   Download: ${C_GREEN}https://github.com/romkatv/powerlevel10k#meslo-nerd-font-patched-for-powerlevel10k"
        echo -e "${C_YELLOW}2. After installing the font, set it in your terminal application (Windows Terminal, iTerm2, etc)."
        echo
    fi
}

# --- System Finalization ---
update_and_clean_system() { if ask_yes_no "Update system now?"; then log_info "Updating system..."; case $PKG_MANAGER in "apt") apt update && apt upgrade -y && apt dist-upgrade -y && apt autoremove -y && apt clean -y;; "dnf") dnf upgrade -y && dnf autoremove -y;; "pacman") pacman -Syu --noconfirm;; esac; log_success "Update complete."; fi; }
final_reboot() { log_info "All tasks complete."; if ask_yes_no "Reboot now?"; then log_action "!!! REBOOTING in 5 seconds... !!!"; sleep 5; reboot; fi; }

# --- Main Execution ---
main() {
    print_header; detect_package_manager; install_packages; setup_security_tool; manage_users
    setup_ssh_keys; harden_ssh_server; install_docker; configure_nfs_mounts; setup_zsh_p10k
    update_and_clean_system; final_reboot
    echo -e "\n${C_GREEN}================== Script Finished ==================${C_RESET}"
}

main
