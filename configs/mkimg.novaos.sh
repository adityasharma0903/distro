# mkimg.novaos.sh - NovaOS Build Profile
# This file is loaded by Alpine's mkimage.sh tool during ISO creation.

profile_novaos() {
    # Inherit from the standard base profile
    profile_standard
    
    # OS Metadata
    profile_abbrev="novaos"
    title="NovaOS"
    desc="NovaOS Live Desktop Edition"
    image_name="novaos"
    
    # Boot command line options
    # - unionfs_size=512M: Sets RAM disk size for changes
    # - quiet: Mutes standard boot logs for a cleaner look
    # - splash: Prepares frame buffer graphics splash (future milestone)
    kernel_cmdline="unionfs_size=1024M console=tty0 quiet splash"
    
    # Use our custom apkovl generator instead of the default dhcp one
    apkovl="genapkovl-novaos.sh"
    
    # ------------------ Package Selection ------------------
    
    # 1. Development Tools
    apks="$apks bash sudo git nano vim"
    
    # 2. Xorg & Graphics Drivers (supporting VMware, VirtualBox, and standard hardware)
    apks="$apks xorg-server xf86-video-vesa xf86-video-vmware xf86-video-modesetting xf86-input-libinput"
    
    # 3. LightDM Display Manager
    apks="$apks lightdm lightdm-gtk-greeter"
    
    # 4. LXQt Desktop Environment
    apks="$apks lxqt-desktop pcmanfm-qt lxqt-powermanagement lxmenu-data"
    
    # 5. Core GUI Applications & Utilities
    apks="$apks xfce4-terminal firefox"
    
    # 6. Network Management (NetworkManager for friendly GUI/CLI network toggle)
    apks="$apks networkmanager networkmanager-cli networkmanager-wifi wpa_supplicant wireless-tools"
    
    # 7. Hardware & Bluetooth Support
    apks="$apks eudev bluez bluez-openrc pciutils usbutils"
    
    # 8. Audio Subsystem (Pipewire for modern audio routing)
    apks="$apks alsa-utils pipewire pipewire-pulse pipewire-alsa wireplumber"
    
    # 9. Additional Custom Filesystems
    apks="$apks dosfstools ntfs-3g exfat-utils"
    
    # 10. Themes & Icons
    apks="$apks arc-theme papirus-icon-theme"
}
