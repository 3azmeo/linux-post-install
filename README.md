# linux-post-install
script to use on fresh linux install



# what is it 
# Universal Linux Post-Install Script

An intelligent, environment-aware script for the initial setup and hardening of Linux servers, with special safety precautions for Proxmox VE hosts. This script is designed to be interactive and modular, allowing you to choose which components to install and configure.

## Key Features

-   **Interactive & Modular**: Asks before acting. You only install what you need.
-   **Environment-Aware**: Customizes its behavior for Standard Servers vs. Proxmox hosts to ensure system stability.
-   **Security Hardening**: Configures SSH, sets up intrusion detection (CrowdSec/Fail2Ban), and can install UFW.
-   **User Management**: Automates the creation of a new `sudo` user, deletion of an old user, and deployment of SSH public keys.
-   **System Tools**: Installs common and useful utilities like `htop`, `git`, `ufw`, etc.
-   **Docker & NFS Setup**: Provides options to install Docker and configure NFS client mounts (safely disabled on Proxmox hosts).

## How It Works: The "Intelligent" Setup

The script's primary feature is its ability to adapt to the system it's running on. At startup, it will ask you to identify the environment:

1.  **Standard Linux Server**: (e.g., a Debian or Ubuntu VM)
    -   In this mode, all modules are available for you to choose from.
    -   You will be prompted to install Docker, configure NFS mounts in `/etc/fstab`, and run a full system upgrade.

2.  **Proxmox VE Host**:
    -   In this mode, potentially dangerous modules that could conflict with the hypervisor are **automatically disabled** to protect its stability.
    -   **Disabled Modules on Proxmox**:
        -   **Docker Installation**: Skipped because Docker can interfere with Proxmox's networking (vmbr) and storage. The correct approach is to use LXC containers or VMs.
        -   **NFS Client Mounts**: Skipped because storage on Proxmox should be added via the Web UI (`Datacenter -> Storage`) to make it available for VMs and backups.
        -   **Full System Upgrade**: Skipped because Proxmox updates should be managed carefully through its own repositories (`pveupgrade`) to avoid package conflicts.
    -   All other safe modules, such as installing security tools (`CrowdSec`, `Fail2Ban`) and utilities (`htop`), remain available.

## Available Modules

The script provides interactive prompts for the following tasks:

#### 1. System & Package Installation
-   Installs a base set of tools (`curl`, `git`, `wget`, `nano`).
-   Optionally installs `htop`, `ufw` (firewall), and `unzip`.

#### 2. Security Configuration
-   **Intrusion Protection**: Gives you the choice to install and configure **CrowdSec** (recommended) or **Fail2Ban**.
-   **SSH Hardening**: Optionally disables root login over SSH (`PermitRootLogin no`) and password-based authentication, enforcing key-based login.

#### 3. User Management
-   **Creates a new user** with `sudo` privileges (defaults to `3azmeo`).
-   **Deletes a specified user** and their home directory (defaults to `admini`).
-   **Deploys SSH public keys** to the new user's `authorized_keys` file for immediate passwordless access.

#### 4. System & Services (Standard Server Mode Only)
-   **Docker**: Installs the latest version of Docker Engine and adds the new user to the `docker` group.
-   **NFS Client**: Configures NFS client mounts by adding entries to `/etc/fstab`.
-   **System Upgrade**: Performs a full system update and upgrade (`apt upgrade && apt dist-upgrade`).

#### 5. Finalization
-   Prompts for a system reboot to ensure all changes are applied correctly.

## Usage

This script is interactive and must be run with root privileges.


# how to install 
run command
bash -c "$(curl -fsSL https://raw.githubusercontent.com/3azmeo/linux-post-install/main/post-install.sh)"
or
bash -c "$(curl -fsSL https://raw.githubusercontent.com/3azmeo/linux-post-install/refs/heads/main/post-install.sh)"


# docker install

chmod +x install_docker.sh && ./install_docker.sh

# ps
Username (3azmeo): In the "Add User to Docker Group" step, 3azmeo is used as the username as you provided. If your desired username is different, you must manually edit the script to change 3azmeo to the correct username

