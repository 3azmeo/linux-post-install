#!/bin/bash

# --- Color Definitions for Messages ---
GREEN='\033[0;32m' # Green for success
YELLOW='\033[0;33m' # Yellow for informational/progress messages
RED='\033[0;31m' # Red for errors
BLUE='\033[0;34m' # Blue for section headers
NC='\033[0m' # No Color - Resets terminal color

# --- Function to Display Status Messages ---
log_message() {
    echo -e "${YELLOW}[INFO] ${1}${NC}"
}

log_step() {
    echo -e "${BLUE}[STEP] ${1}${NC}"
}

log_success() {
    echo -e "${GREEN}[DONE] ${1}${NC}"
}

log_error() {
    echo -e "${RED}[ERROR] ${1}${NC}"
}

# --- Script Start Message ---
echo -e "\n${BLUE}--- Starting Docker Installation Script for Linux Systems ---${NC}\n"

# --- 1. Detect Operating System ---
log_step "Detecting Operating System and Distribution..."

OS_ID=""
OS_CODENAME=""

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
    OS_CODENAME=$VERSION_CODENAME
    log_success "Operating system detected: ${ID_LIKE:-$ID} - Codename: $OS_CODENAME"
else
    log_error "Could not find /etc/os-release. Script might not function correctly."
    exit 1
fi

echo ""

# --- 2. Update Package List and Install Essential Prerequisites ---
log_step "Updating APT package list and installing 'ca-certificates', 'curl', and 'gnupg'..."
sudo apt-get update > /dev/null 2>&1
# Not checking exit status here, as it might fail due to the GPG error we are trying to fix.
# The essential packages install below is critical.

# Ensure gnupg is installed as it provides the 'gpg' command
sudo apt-get install -y ca-certificates curl gnupg
if [ $? -eq 0 ]; then
    log_success "'ca-certificates', 'curl', and 'gnupg' installed successfully."
else
    log_error "Failed to install essential packages: 'ca-certificates', 'curl', 'gnupg'."
    exit 1
fi

echo ""

# --- 3. Create GPG Key Directory for APT ---
log_step "Creating '/etc/apt/keyrings' directory and setting permissions..."
sudo install -m 0755 -d /etc/apt/keyrings
if [ $? -eq 0 ]; then
    log_success "Directory '/etc/apt/keyrings' created successfully."
else
    log_error "Failed to create directory '/etc/apt/keyrings'."
    exit 1
fi

echo ""

# --- 4. Add Docker's Official GPG Key ---
log_step "Fetching and adding Docker's official GPG key..."
# IMPORTANT: Modern Docker installations use .gpg extension and require gnupg
GPG_KEY_URL=""
case "$OS_ID" in
    ubuntu)
        log_message "Fetching GPG key for Ubuntu..."
        GPG_KEY_URL="https://download.docker.com/linux/ubuntu/gpg"
        ;;
    debian)
        log_message "Fetching GPG key for Debian..."
        GPG_KEY_URL="https://download.docker.com/linux/debian/gpg"
        ;;
    raspbian)
        # For Raspbian Bookworm and later, Docker recommends using Debian's repository and key.
        if [[ "$OS_CODENAME" == "bookworm" ]]; then
            log_message "Fetching GPG key for Raspbian (Bookworm) - using Debian's key as per Docker docs..."
            GPG_KEY_URL="https://download.docker.com/linux/debian/gpg"
        else
            log_message "Fetching GPG key for Raspbian (older version)..."
            GPG_KEY_URL="https://download.docker.com/linux/raspbian/gpg"
        fi
        ;;
    *)
        log_error "Unsupported distribution for GPG key. Please check manually: $OS_ID"
        exit 1
        ;;
esac

# Common GPG key fetching method for all supported distributions
# Use --dearmor and save as .gpg extension for keyrings
curl -fsSL "$GPG_KEY_URL" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
if [ $? -eq 0 ]; then
    log_success "Docker GPG key fetched and added successfully to /etc/apt/keyrings/docker.gpg."
else
    log_error "Failed to fetch and add Docker GPG key from $GPG_KEY_URL."
    exit 1
fi

# Set read permissions for the GPG key
log_step "Setting read permissions for the Docker GPG key..."
sudo chmod a+r /etc/apt/keyrings/docker.gpg
if [ $? -eq 0 ]; then
    log_success "GPG key read permissions set successfully."
else
    log_error "Failed to set GPG key read permissions."
    exit 1
fi

echo ""

# --- 5. Add Docker Repository to APT Sources ---
log_step "Adding Docker repository to APT sources..."
ARCH=$(dpkg --print-architecture)
REPO_URL=""

case "$OS_ID" in
    ubuntu)
        log_message "Adding Docker repository for Ubuntu..."
        REPO_URL="https://download.docker.com/linux/ubuntu"
        ;;
    debian)
        log_message "Adding Docker repository for Debian..."
        REPO_URL="https://download.docker.com/linux/debian"
        ;;
    raspbian)
        if [[ "$OS_CODENAME" == "bookworm" ]]; then
            log_message "Adding Docker repository for Raspbian (Bookworm) - using Debian's repository as per Docker docs..."
            REPO_URL="https://download.docker.com/linux/debian"
        else
            log_message "Adding Docker repository for Raspbian (older version)..."
            REPO_URL="https://download.docker.com/linux/raspbian"
        fi
        ;;
    *)
        log_error "Unsupported distribution for adding repository. Please check manually: $OS_ID"
        exit 1
        ;;
esac

# Note the change to 'signed-by=/etc/apt/keyrings/docker.gpg'
echo \
  "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] ${REPO_URL} \
  ${OS_CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

if [ $? -eq 0 ]; then
    log_success "Docker repository added successfully."
else
    log_error "Failed to add Docker repository."
    exit 1
fi

echo ""

# --- 6. Update Package List After Adding Repository ---
log_step "Updating APT package list again to fetch Docker packages..."
sudo apt-get update > /dev/null 2>&1
if [ $? -eq 0 ]; then
    log_success "APT package list updated successfully after adding Docker repository."
else
    log_error "Failed to update APT package list after adding Docker repository. This might still be a GPG key issue."
    exit 1 # Exiting here as further steps will fail without successful update
fi

echo ""

# --- 7. Install Docker Packages ---
log_step "Installing Docker packages (docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin, docker-compose-plugin)..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
if [ $? -eq 0 ]; then
    log_success "Docker packages installed successfully."
else
    log_error "Failed to install Docker packages."
    exit 1
fi

echo ""

# --- 8. Verify Installation by Running hello-world Image ---
log_step "Verifying Docker installation by running 'hello-world' image..."
sudo docker run hello-world
if [ $? -eq 0 ]; then
    log_success "Docker installation verified successfully! ('hello-world' ran)."
else
    log_error "Failed to verify Docker installation. ('hello-world' did not run)."
fi

echo ""

# --- 9. Add User to Docker Group ---
# Note: '3azmeo' is used as the username as provided. If your username is different, please modify the next line.
log_step "Adding user '3azmeo' to the 'docker' group to allow running Docker without sudo..."
sudo usermod -aG docker 3azmeo
if [ $? -eq 0 ]; then
    log_success "User '3azmeo' added to 'docker' group successfully."
    log_message "IMPORTANT: You must log out of your current session and then log back in for group changes to apply, or reboot your system."
else
    log_error "Failed to add user '3azmeo' to 'docker' group. Please check manually."
fi

echo ""

# --- 10. Verify Docker Commands Without Sudo (After Re-login) ---
log_step "To verify that you can run Docker commands without sudo, after logging out and logging back in, run the following command manually:"
echo -e "${YELLOW}docker run hello-world${NC}"
echo -e "${YELLOW}This command should work without needing 'sudo'.${NC}"

echo ""

# --- 11. Create Symlink for Docker Compose sudo Compatibility ---
log_step "Fixing 'sudo docker compose' compatibility..."

# Find the path of the docker-compose plugin.
# The 2>/dev/null part hides any "permission denied" errors from find.
# The head -n 1 part ensures we only get the first result if multiple are found.
COMPOSE_PLUGIN_PATH=$(sudo find / -name "docker-compose" 2>/dev/null | head -n 1)

# Check if the find command successfully located the plugin.
if [ -n "$COMPOSE_PLUGIN_PATH" ]; then
    log_message "Found Docker Compose plugin at: $COMPOSE_PLUGIN_PATH"
    log_message "Creating symbolic link at /usr/bin/docker-compose..."
    
    # Create the symbolic link in a standard path that sudo checks.
    sudo ln -s "$COMPOSE_PLUGIN_PATH" /usr/bin/docker-compose
    
    # Check if the link was created successfully.
    if [ $? -eq 0 ]; then
        log_success "Symbolic link for Docker Compose created successfully."
    else
        log_error "Failed to create symbolic link for Docker Compose."
    fi
else
    # This message will show if the plugin was not found anywhere.
    log_message "WARNING: Could not find the 'docker-compose' plugin. Skipping symbolic link creation."
fi

echo ""


# --- Script Final Message ---
echo -e "\n${GREEN}--- Docker Installation Script Completed Successfully! ---${NC}\n"

log_message "For more information, please refer to the official Docker documentation:"
echo "[Docker Official Documentation](https://docs.docker.com/engine/install/)"
echo ""
