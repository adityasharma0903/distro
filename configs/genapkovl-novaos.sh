#!/bin/sh -e

# genapkovl-novaos.sh - NovaOS Live Overlay Generator
# This script generates the .apkovl.tar.gz file which configures the running live environment at boot.

HOSTNAME="$1"
if [ -z "$HOSTNAME" ]; then
    echo "usage: $0 hostname"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# The project root is three levels up: build/aports/scripts/ -> project root
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

cleanup() {
    rm -rf "$tmp"
}

# Helper to write files with specific owner and permissions
makefile() {
    OWNER="$1"
    PERMS="$2"
    FILENAME="$3"

    mkdir -p "$(dirname "$FILENAME")"

    cat > "$FILENAME"
    chown "$OWNER" "$FILENAME"
    chmod "$PERMS" "$FILENAME"
}

# Helper to enable OpenRC services in the live image
rc_add() {
    mkdir -p "$tmp"/etc/runlevels/"$2"
    ln -sf /etc/init.d/"$1" "$tmp"/etc/runlevels/"$2"/"$1"
}

tmp="$(mktemp -d)"
trap cleanup EXIT

# 1. Base configuration directories
mkdir -p "$tmp"/etc
mkdir -p "$tmp"/etc/apk
mkdir -p "$tmp"/etc/network
mkdir -p "$tmp"/etc/doas.d
mkdir -p "$tmp"/etc/lightdm
mkdir -p "$tmp"/home/nova/Desktop
mkdir -p "$tmp"/root
mkdir -p "$tmp"/usr/share/backgrounds/novaos
mkdir -p "$tmp"/usr/sbin
mkdir -p "$tmp"/usr/lib/firefox/distribution
mkdir -p "$tmp"/etc/firefox
mkdir -p "$tmp"/etc/xdg/lxqt
mkdir -p "$tmp"/etc/xdg/pcmanfm-qt/lxqt
mkdir -p "$tmp"/home/nova/.config/xfce4/terminal
mkdir -p "$tmp"/etc/gtk-3.0
mkdir -p "$tmp"/etc/gtk-2.0
mkdir -p "$tmp"/etc/polkit-1/rules.d

# 2. Set Hostname (check workspace first)
if [ -f "$PROJECT_ROOT/branding/hostname" ]; then
    cp "$PROJECT_ROOT/branding/hostname" "$tmp"/etc/hostname
    chown root:root "$tmp"/etc/hostname
    chmod 0644 "$tmp"/etc/hostname
else
    makefile root:root 0644 "$tmp"/etc/hostname <<EOF
$HOSTNAME
EOF
fi

# 3. Network Interfaces (Loopback only, physical interfaces managed by NetworkManager)
makefile root:root 0644 "$tmp"/etc/network/interfaces <<EOF
auto lo
iface lo inet loopback
EOF

# 4. APK Repository list to configure during live run
# Dynamically configured based on the running build host's version (retrieved via resolv/alpine-release)
ALPINE_VER=$(cat /etc/alpine-release 2>/dev/null | cut -d'.' -f1-2 || echo "3.24")
case "$ALPINE_VER" in
    [0-9]*.[0-9]*) ;;
    *) ALPINE_VER="3.24" ;;
esac

makefile root:root 0644 "$tmp"/etc/apk/repositories <<EOF
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VER}/main
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VER}/community
EOF

# 5. APK World file (defines the core pack list we expect to run)
# Registered dependencies mirroring the compose package list system
makefile root:root 0644 "$tmp"/etc/apk/world <<EOF
alpine-base
alpine-conf
bash
doas
eudev
dbus
pciutils
usbutils
util-linux
iproute2
acpid
elogind
elogind-openrc
xorg-server
xf86-video-vesa
xf86-video-vmware
xf86-video-modesetting
xf86-input-libinput
lxqt-desktop
lxqt-session
openbox
lightdm
lightdm-gtk-greeter
pcmanfm-qt
qterminal
xfce4-terminal
firefox
papirus-icon-theme
networkmanager
networkmanager-cli
networkmanager-wifi
networkmanager-openrc
wpa_supplicant
wireless-tools
bluez
bluez-openrc
alsa-utils
pipewire
pipewire-pulse
pipewire-alsa
wireplumber
blueman
nano
git
dosfstools
ntfs-3g
exfat-utils
EOF

# 6. Dynamic User initialization & elevation setup (runs once on boot)
makefile root:root 0755 "$tmp"/etc/local.d/novaos-setup.start <<EOF
#!/bin/sh

# 1. Create 'nova' group & user dynamically if missing
if ! id -u nova >/dev/null 2>&1; then
    addgroup -g 1000 nova 2>/dev/null || addgroup nova
    adduser -D -u 1000 -g "NovaOS User" -s /bin/bash -G nova nova
    # Set default passwords (nova / root)
    echo "nova:nova" | chpasswd
    echo "root:nova" | chpasswd
fi

# 2. Assign 'nova' user to administrative, media, and input groups
for g in wheel audio video netdev input kvm usb dialout; do
    addgroup -S "\$g" 2>/dev/null || true
    addgroup nova "\$g" 2>/dev/null || true
done

# 3. Ensure proper permissions and ownership across home directories
chown -R 1000:1000 /home/nova

# 4. Set doas configuration security policies
chmod 0640 /etc/doas.d/doas.conf 2>/dev/null || true
chown root:root /etc/doas.d/doas.conf 2>/dev/null || true
EOF

# 7. Doas Configuration for passwordless elevation
# This permits user 'nova' and any other member of 'wheel' to run as root without password
makefile root:root 0640 "$tmp"/etc/doas.d/doas.conf <<EOF
permit nopass root
permit nopass :wheel
EOF

# 8. Copy Custom System & Application Configurations from Workspace
echo "[INFO] Injecting workspace configuration files into overlay..."

# LightDM Autologin & Greeter settings
if [ -f "$PROJECT_ROOT/configs/lightdm-gtk-greeter.conf" ]; then
    cp "$PROJECT_ROOT/configs/lightdm-gtk-greeter.conf" "$tmp"/etc/lightdm/lightdm-gtk-greeter.conf
    chown root:root "$tmp"/etc/lightdm/lightdm-gtk-greeter.conf
    chmod 0644 "$tmp"/etc/lightdm/lightdm-gtk-greeter.conf
fi

makefile root:root 0644 "$tmp"/etc/lightdm/lightdm.conf <<EOF
[Seat:*]
autologin-user=nova
autologin-user-timeout=0
user-session=lxqt
greeter-session=lightdm-gtk-greeter
EOF

# xfce4-terminal style configurations
if [ -f "$PROJECT_ROOT/configs/terminalrc" ]; then
    cp "$PROJECT_ROOT/configs/terminalrc" "$tmp"/home/nova/.config/xfce4/terminal/terminalrc
    chmod 0644 "$tmp"/home/nova/.config/xfce4/terminal/terminalrc
fi

# Firefox policies configuration
if [ -f "$PROJECT_ROOT/configs/policies.json" ]; then
    cp "$PROJECT_ROOT/configs/policies.json" "$tmp"/etc/firefox/policies.json
    chmod 0644 "$tmp"/etc/firefox/policies.json
    cp "$PROJECT_ROOT/configs/policies.json" "$tmp"/usr/lib/firefox/distribution/policies.json
    chmod 0644 "$tmp"/usr/lib/firefox/distribution/policies.json
fi

# LXQt Desktop environment system defaults (/etc/xdg/lxqt/)
if [ -f "$PROJECT_ROOT/configs/lxqt/panel.conf" ]; then
    cp "$PROJECT_ROOT/configs/lxqt/panel.conf" "$tmp"/etc/xdg/lxqt/panel.conf
    chmod 0644 "$tmp"/etc/xdg/lxqt/panel.conf
fi

if [ -f "$PROJECT_ROOT/configs/lxqt/session.conf" ]; then
    cp "$PROJECT_ROOT/configs/lxqt/session.conf" "$tmp"/etc/xdg/lxqt/session.conf
    chmod 0644 "$tmp"/etc/xdg/lxqt/session.conf
fi

if [ -f "$PROJECT_ROOT/configs/lxqt/lxqt-runner.conf" ]; then
    cp "$PROJECT_ROOT/configs/lxqt/lxqt-runner.conf" "$tmp"/etc/xdg/lxqt/lxqt-runner.conf
    chmod 0644 "$tmp"/etc/xdg/lxqt/lxqt-runner.conf
fi

if [ -f "$PROJECT_ROOT/configs/lxqt/pcmanfm-qt-settings.conf" ]; then
    cp "$PROJECT_ROOT/configs/lxqt/pcmanfm-qt-settings.conf" "$tmp"/etc/xdg/pcmanfm-qt/lxqt/settings.conf
    chmod 0644 "$tmp"/etc/xdg/pcmanfm-qt/lxqt/settings.conf
fi

# GTK theme configurations (system-wide defaults)
if [ -f "$PROJECT_ROOT/configs/gtk-3.0-settings.ini" ]; then
    cp "$PROJECT_ROOT/configs/gtk-3.0-settings.ini" "$tmp"/etc/gtk-3.0/settings.ini
    chown root:root "$tmp"/etc/gtk-3.0/settings.ini
    chmod 0644 "$tmp"/etc/gtk-3.0/settings.ini
fi

if [ -f "$PROJECT_ROOT/configs/gtkrc-2.0" ]; then
    cp "$PROJECT_ROOT/configs/gtkrc-2.0" "$tmp"/etc/gtk-2.0/gtkrc
    chown root:root "$tmp"/etc/gtk-2.0/gtkrc
    chmod 0644 "$tmp"/etc/gtk-2.0/gtkrc
    
    # Also write it for user nova's home folder preference
    cp "$PROJECT_ROOT/configs/gtkrc-2.0" "$tmp"/home/nova/.gtkrc-2.0
    chmod 0644 "$tmp"/home/nova/.gtkrc-2.0
fi

# 9. Polkit Rules for NetworkManager changes
makefile root:root 0644 "$tmp"/etc/polkit-1/rules.d/50-org.freedesktop.NetworkManager.rules <<EOF
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.freedesktop.NetworkManager.") == 0 &&
        subject.isInGroup("netdev")) {
        return polkit.Result.YES;
    }
});
EOF

# 10. Copy custom branding OS identification (if in workspace)
if [ -f "$PROJECT_ROOT/branding/os-release" ]; then
    cp "$PROJECT_ROOT/branding/os-release" "$tmp"/etc/os-release
    chown root:root "$tmp"/etc/os-release
    chmod 0644 "$tmp"/etc/os-release
fi

if [ -f "$PROJECT_ROOT/branding/issue" ]; then
    cp "$PROJECT_ROOT/branding/issue" "$tmp"/etc/issue
    chown root:root "$tmp"/etc/issue
    chmod 0644 "$tmp"/etc/issue
fi

# 11. Copy custom wallpaper asset
if [ -f "$PROJECT_ROOT/wallpapers/novaos-default.png" ]; then
    cp "$PROJECT_ROOT/wallpapers/novaos-default.png" "$tmp"/usr/share/backgrounds/novaos/novaos-default.png
    chown root:root "$tmp"/usr/share/backgrounds/novaos/novaos-default.png
    chmod 0644 "$tmp"/usr/share/backgrounds/novaos/novaos-default.png
fi

# 12. Copy custom Installer Utility and create Desktop launcher
if [ -f "$PROJECT_ROOT/installer/install.sh" ]; then
    cp "$PROJECT_ROOT/installer/install.sh" "$tmp"/usr/sbin/novaos-install
    chown root:root "$tmp"/usr/sbin/novaos-install
    chmod 0755 "$tmp"/usr/sbin/novaos-install
fi

# Create user desktop shortcut to trigger the installation script
makefile 1000:1000 0755 "$tmp"/home/nova/Desktop/novaos-install.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Install NovaOS
Comment=Install NovaOS persistently to a hard disk
Exec=xfce4-terminal -e "doas /usr/sbin/novaos-install"
Icon=system-software-install
Terminal=false
Categories=System;Installer;
EOF

# Ensure LightDM and startx both land in a real LXQt session instead of a blank shell
makefile 1000:1000 0755 "$tmp"/home/nova/.xsession <<EOF
#!/bin/sh
exec startlxqt
EOF

makefile 1000:1000 0755 "$tmp"/home/nova/.xinitrc <<EOF
#!/bin/sh
exec startlxqt
EOF

# 13. Ensure home folder ownership is correct
chown -R 1000:1000 "$tmp"/home/nova

# 14. OpenRC Core System Services Setup
rc_add devfs sysinit
rc_add dmesg sysinit
rc_add mdev sysinit
rc_add hwdrivers sysinit
rc_add modloop sysinit

rc_add hwclock boot
rc_add modules boot
rc_add sysctl boot
rc_add hostname boot
rc_add bootmisc boot
rc_add syslog boot

rc_add mount-ro shutdown
rc_add killprocs shutdown
rc_add savecache shutdown

# 15. OpenRC NovaOS Userland Services
rc_add udev sysinit
rc_add udev-trigger sysinit

# Desktop environment, Networking, D-Bus, and Bluetooth
rc_add dbus default
rc_add elogind default
rc_add NetworkManager default
rc_add local boot
rc_add lightdm default
rc_add rfkill default
rc_add bluez default

# 16. Package the overlay into the final tarball
tar -c -C "$tmp" etc home root usr | gzip -9n > "$HOSTNAME".apkovl.tar.gz
