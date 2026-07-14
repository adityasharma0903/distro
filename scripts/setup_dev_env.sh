#!/bin/env bash

# setup_dev_env.sh - Automated Development Environment Setup Script for NovaOS
# This script is designed to run inside the Alpine Linux VM to configure the system for ISO builds.

set -euo pipefail

# Visual output helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0;37m' # No Color

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# 1. Verify we are running on Alpine Linux
if [ ! -f /etc/alpine-release ]; then
    error "This script must run on Alpine Linux. Detected other system."
fi

# 2. Check if script is run as root (or via sudo)
if [ "$EUID" -ne 0 ]; then
    error "This script installs system packages and must be run as root (e.g., sudo bash $0)"
fi

# Determine original developer user (who ran sudo)
DEV_USER=${SUDO_USER:-}
if [ -z "$DEV_USER" ] || [ "$DEV_USER" = "root" ]; then
    warn "This script is running directly as root. abuild setup will be skipped for non-root users."
fi

info "Starting NovaOS Development Environment setup on Alpine v$(cat /etc/alpine-release)..."

# 3. Ensure community repository is enabled
info "Checking apk repositories..."
REPO_FILE="/etc/apk/repositories"
if grep -q "#.*community" "$REPO_FILE"; then
    info "Enabling the community repository in $REPO_FILE..."
    sed -i 's/#\s*\(.*\/community\)/\1/' "$REPO_FILE"
fi

# Run apk update to reload indices
info "Updating package database..."
apk update

# 4. Install required build dependencies
# - alpine-sdk: Metapackage for build tools (gcc, make, binutils, git, abuild)
# - xorg-server/xinit/lightdm/LXQt stack: lets the dev VM boot into the same desktop path as the ISO
# - xorriso: Multi-format ISO 9660 filesystem creator
# - squashfs-tools: Utilities to create compressed read-only filesystems for live systems
# - syslinux: Bootloader for legacy BIOS boots
# - grub-efi: Bootloader for UEFI boots
# - mtools & dosfstools: Utilities to write MS-DOS FAT filesystems (needed for UEFI boot partitions)
# - bash: Needed for specific upstream mkimage scripts
BUILD_PACKAGES="alpine-sdk xorg-server xinit xauth xrandr mesa-dri-gallium mesa-gl mesa-egl libinput xf86-input-libinput xf86-video-vmware xf86-video-vesa xf86-video-modesetting dbus dbus-x11 elogind elogind-openrc polkit polkit-elogind accountsservice lightdm lightdm-gtk-greeter lxqt-desktop lxqt-session openbox pcmanfm-qt qterminal papirus-icon-theme firefox xorriso squashfs-tools syslinux grub-efi mtools dosfstools bash"

info "Installing build packages: $BUILD_PACKAGES..."
apk add $BUILD_PACKAGES

success "Packages successfully installed."

info "Enabling desktop services in the dev VM..."
rc-update add dbus default 2>/dev/null || true
rc-update add elogind default 2>/dev/null || true
rc-update add lightdm default 2>/dev/null || true

# 5. Configure abuild for the developer user
if [ -n "$DEV_USER" ] && [ "$DEV_USER" != "root" ]; then
    info "Configuring abuild privileges for developer user: $DEV_USER..."
    
    # Add user to abuild group
    addgroup "$DEV_USER" abuild
    success "Added user '$DEV_USER' to group 'abuild'."

    # Set up abuild directories for developer user if they do not exist
    DEV_HOME=$(eval echo "~$DEV_USER")
    
    # Generate signing keys if they don't exist
    if [ ! -f "$DEV_HOME/.abuild/abuild.conf" ]; then
        info "Generating abuild signing keys for user '$DEV_USER'..."
        # Run keygen as the developer user
        su - "$DEV_USER" -c "abuild-keygen -a -i"
        success "abuild cryptographic keys successfully generated and registered."
    else
        info "abuild keys already exist for '$DEV_USER'. Skipping generation."
    fi
else
    warn "Skipping developer user setup (running as root and no original SUDO_USER found)."
fi

info "Validating build tool installations..."
for cmd in abuild xorriso mksquashfs grub-mkimage; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo -e "  - $cmd: ${GREEN}Installed${NC}"
    else
        echo -e "  - $cmd: ${RED}Missing${NC}"
    fi
done

success "Milestone 0 Development Environment Setup Complete!"
info "Please reboot your system or log out and log back in for group changes to take effect."
