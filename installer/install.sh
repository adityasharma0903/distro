#!/bin/env bash

# install.sh - NovaOS Disk Installer Script
# Installs NovaOS from the Live RAM environment onto a selected persistent hard disk.
# Must be executed with root privileges inside the Live ISO.

set -euo pipefail

# Visual styling colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0;37m'

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

# 1. Require root execution
if [ "$EUID" -ne 0 ]; then
    error "This installer must be run as root. Try: sudo bash $0"
fi

echo -e "${GREEN}"
echo "   _  __               ____  _____   ___           __     ____"
echo "  / |/ /__ _  __ ___ _/ __ \/ ___/  / _ \___  ___ / /_   /  _/__  ___ ___ _ _ __"
echo " /    / _ \ |/ // _ \/ /_/ /\__ \  / ___/ _ \(_-</ __/  _/ // _ \(_-</ _ \/ / /"
echo "/_/|__/\___/___/\_,_/\____/____/  /_/   \___/___/\__/  /___/_//_/___/ .__/_/_/"
echo "                                                                   /_/"
echo -e "${NC}"
echo "================================================================================"
echo "                   NovaOS Persistent Installation Wizard"
echo "================================================================================"
echo "This installer will partition and format your selected hard drive and install"
echo "a persistent instance of NovaOS. WARNING: ALL DATA ON THE DISK WILL BE WIPED!"
echo "================================================================================"
echo ""

# 2. Detect Boot Mode (UEFI vs Legacy BIOS)
UEFI=false
if [ -d /sys/firmware/efi ]; then
    UEFI=true
    info "Detected Boot Mode: UEFI"
else
    info "Detected Boot Mode: Legacy BIOS"
fi

# 3. Detect available disks
info "Scanning for available hard drives..."
DISKS=$(find /dev -maxdepth 1 -regex '.*\/[sv]d[a-z]\|.*\/nvme[0-9]n[0-9]' | sort)

if [ -z "$DISKS" ]; then
    error "No installable hard drives found. Please attach a virtual disk in VMware/VirtualBox."
fi

echo "Available Disks:"
echo "----------------"
for d in $DISKS; do
    # Get disk details using sysfs
    d_name=$(basename "$d")
    d_size=$(cat "/sys/block/$d_name/size")
    # convert sectors to GB (size * 512 / 1024^3)
    d_gb=$(echo "$d_size" | awk '{printf "%.2f", $1 * 512 / 1024 / 1024 / 1024}')
    
    # Try to read model name
    d_model="Unknown Model"
    if [ -f "/sys/block/$d_name/device/model" ]; then
        d_model=$(cat "/sys/block/$d_name/device/model" | xargs)
    fi
    
    echo "  * $d - $d_gb GB ($d_model)"
done
echo ""

# Prompt user to select drive
read -p "Select target disk for NovaOS installation (e.g., /dev/sda): " TARGET_DRIVE

# Validate choice
if [[ ! " $DISKS " =~ " $TARGET_DRIVE " ]]; then
    error "Invalid disk selection. Please run the script again and select a drive from the list."
fi

# Final warning and confirmation
warn "You selected target disk: $TARGET_DRIVE"
warn "ALL partitions and files on $TARGET_DRIVE will be PERMANENTLY ERASED."
read -p "Are you sure you want to proceed? Type 'YES' to confirm: " CONFIRMATION

if [ "$CONFIRMATION" != "YES" ]; then
    info "Installation cancelled by user."
    exit 0
fi

info "Starting partition and formatting on $TARGET_DRIVE..."

# Determine partition suffix (p for nvme, empty for sd/vd)
PART_SUFFIX=""
if [[ "$TARGET_DRIVE" =~ "nvme" ]]; then
    PART_SUFFIX="p"
fi

# 4. Partition the target drive
# We wipe partition tables first
dd if=/dev/zero of="$TARGET_DRIVE" bs=512 count=100 conv=notrunc >/dev/null 2>&1
sync

if [ "$UEFI" = true ]; then
    # GPT Partition Layout:
    # Part 1: EFI System Partition (512MB)
    # Part 2: Linux Root (Remaining Space)
    info "Creating GPT partitions..."
    echo "label: gpt
    size=512M, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
    , type=0FC63DAF-8483-4772-8E79-3D69D8477DE4" | sfdisk "$TARGET_DRIVE"
    
    EFI_PART="${TARGET_DRIVE}${PART_SUFFIX}1"
    ROOT_PART="${TARGET_DRIVE}${PART_SUFFIX}2"
    
    # Format filesystems
    info "Formatting EFI partition ($EFI_PART) as FAT32..."
    mkfs.vfat -F32 "$EFI_PART"
    
    info "Formatting Root partition ($ROOT_PART) as EXT4..."
    mkfs.ext4 -F "$ROOT_PART"
    
    # Mount filesystems
    info "Mounting filesystems under /mnt..."
    mkdir -p /mnt
    mount "$ROOT_PART" /mnt
    mkdir -p /mnt/boot/efi
    mount "$EFI_PART" /mnt/boot/efi
else
    # MBR/Legacy Partition Layout:
    # Part 1: Bootable Linux Root (100% space)
    info "Creating MBR partitions..."
    echo "label: dos
    , , *, -" | sfdisk "$TARGET_DRIVE"
    
    ROOT_PART="${TARGET_DRIVE}${PART_SUFFIX}1"
    
    # Format root filesystem
    info "Formatting Root partition ($ROOT_PART) as EXT4..."
    mkfs.ext4 -F "$ROOT_PART"
    
    # Mount filesystem
    info "Mounting root filesystem under /mnt..."
    mkdir -p /mnt
    mount "$ROOT_PART" /mnt
fi

# 5. Bootstrap packages using apk
# We extract the currently installed live packages from the live environment's world file.
info "Detecting packages to bootstrap..."
LIVE_PACKAGES=$(cat /etc/apk/world | xargs)

# Append kernel, base firmware, and bootloader tools
TARGET_PACKAGES="$LIVE_PACKAGES linux-lts grub"
if [ "$UEFI" = true ]; then
    TARGET_PACKAGES="$TARGET_PACKAGES grub-efi efibootmgr"
else
    TARGET_PACKAGES="$TARGET_PACKAGES grub-bios"
fi

info "Bootstrapping NovaOS packages onto target disk..."
# Initialize package databases and copy mirrors
mkdir -p /mnt/etc/apk
cp -r /etc/apk/keys /mnt/etc/apk/
cp /etc/apk/repositories /mnt/etc/apk/

# Install the packages to /mnt
apk add --root /mnt --initdb --no-cache $TARGET_PACKAGES

success "OS package bootstrapping complete."

# 6. Copy Configurations and Overlays
info "Cloning Live configurations and user states to disk..."
# Copy configurations, networks, users, and lightdm profiles
for dir in etc home root; do
    if [ -d "/$dir" ]; then
        cp -a "/$dir"/* "/mnt/$dir/"
    fi
done

# Ensure custom wallpaper is copied
mkdir -p /mnt/usr/share/backgrounds/novaos
if [ -d "/usr/share/backgrounds/novaos" ]; then
    cp -a /usr/share/backgrounds/novaos/* /mnt/usr/share/backgrounds/novaos/ 2>/dev/null || true
fi

# Clean up any cached live configurations on disk
rm -f /mnt/etc/network/interfaces.live 2>/dev/null || true

# 7. Generate fstab
info "Generating persistent file systems fstab..."
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
cat > /mnt/etc/fstab <<EOF
# NovaOS fstab
UUID=$ROOT_UUID / ext4 noatime,nodiratime 1 1
tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0
EOF

if [ "$UEFI" = true ]; then
    EFI_UUID=$(blkid -s UUID -o value "$EFI_PART")
    cat >> /mnt/etc/fstab <<EOF
UUID=$EFI_UUID /boot/efi vfat defaults 0 2
EOF
fi

# 8. Mount virtual filesystems for chroot GRUB setup
info "Preparing chroot context..."
mount -t proc none /mnt/proc
mount --bind /dev /mnt/dev
mount --bind /sys /mnt/sys

# 9. Install and configure GRUB bootloader inside the chroot
info "Installing GRUB bootloader..."
if [ "$UEFI" = true ]; then
    chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=NovaOS --recheck
else
    chroot /mnt grub-install --target=i386-pc "$TARGET_DRIVE" --recheck
fi

info "Generating GRUB bootloader configuration menu..."
# Configure default boot options in grub
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=".*"/GRUB_CMDLINE_LINUX_DEFAULT="unionfs_size=1024M quiet splash"/' /mnt/etc/default/grub || true
chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# 10. Clean up and unmount
info "Finalizing installations and cleaning up mounts..."
sync

umount /mnt/proc
umount /mnt/dev
umount /mnt/sys

if [ "$UEFI" = true ]; then
    umount /mnt/boot/efi
fi
umount /mnt

success "NovaOS has been successfully installed on $TARGET_DRIVE!"
echo "================================================================================"
echo "Installation complete. You can now reboot your virtual machine."
echo "Remember to disconnect/unmount the Live ISO image before starting up again."
echo "================================================================================"
read -p "Reboot now? (y/n): " REBOOT_CHOICE
if [ "$REBOOT_CHOICE" = "y" ] || [ "$REBOOT_CHOICE" = "Y" ]; then
    info "Rebooting system..."
    reboot
fi
