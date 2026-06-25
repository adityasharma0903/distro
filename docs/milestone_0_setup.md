# NovaOS - Milestone 0: Development Environment Setup Guide

This guide is designed for the NovaOS development team. It provides a complete, step-by-step walkthrough to set up a unified Alpine Linux virtual machine (VM) in VMware or VirtualBox, establish developer workspaces, configure services, and prepare the environment for building the custom NovaOS ISO.

---

## 📖 Part 1: Under the Hood - Alpine Linux Internals

Before installing, it is vital to understand the architectural differences between Alpine Linux and traditional distributions like Ubuntu or Debian.

### 1. `musl libc` vs `glibc`
* **Why?**: The standard library is the foundation of the Linux userland, providing interfaces for memory management, system calls, and basic string operations. While most distros use the GNU C Library (`glibc`), Alpine uses `musl libc`.
* **Impact**: `musl` is written from scratch to be extremely lightweight, secure, and standards-compliant. However, it is not binary-compatible with `glibc`.
* **Developer Warning**: Precompiled binaries (like third-party drivers or proprietary software) compiled for glibc will not run on Alpine out of the box. They must be compiled from source on Alpine or run using compatibility layers like `gcompat`.

### 2. BusyBox Userland
* **Why?**: Standard Linux utilities (like `ls`, `grep`, `cp`, `tar`) are typically separate, large packages from GNU Coreutils. Alpine replaces these with a single executable called **BusyBox**.
* **Impact**: BusyBox compiles miniature versions of over 300 common commands into a single executable, saving disk space and memory. Almost all commands in `/bin` and `/sbin` are symlinks to `/bin/busybox`.
* **Developer Warning**: BusyBox utilities only support standard POSIX flags. Advanced or non-standard GNU-specific command-line arguments may fail. Keep your automation scripts POSIX-compliant!

### 3. OpenRC Init System
* **Why?**: The init system is the first process launched by the kernel (PID 1) and is responsible for starting/stopping services. Most Linux distros use `systemd`. Alpine uses **OpenRC**.
* **Impact**: `systemd` is massive, complex, and manages everything from networking to logs. OpenRC is a lightweight, modular, shell-script-based init system. It is simple to understand, writes scripts in standard shell syntax, and boots much faster.
* **Service Control**:
  * Check service status: `rc-service <name> status`
  * Start/Stop/Restart: `rc-service <name> start|stop|restart`
  * Enable service at boot: `rc-update add <name> <runlevel>`
  * Runlevels are typically:
    * `sysinit`: Core hardware setup and early mounting.
    * `boot`: Mounting filesystems and loading drivers.
    * `default`: Standard multi-user services (network, SSH, display managers).
    * `shutdown`: Graceful shutdown sequence.

### 4. APK Package Manager
* **Why?**: APK (Alpine Package Keeper) is the tool used to install and manage software packages (`.apk` files).
* **Impact**: Unlike `apt` or `dnf`, APK is written in pure C and is extremely fast. It operates on database index files. The local cache is located at `/var/cache/apk`.

---

## 💻 Part 2: VMware Virtual Machine Setup

To run our build environment, we need to create an Alpine Linux VM on our host machine.

### Recommended VM Configuration
* **Guest OS Type**: Select **Other Linux 5.x kernel 64-bit** (or **Alpine Linux** if available in your VMware version).
* **CPU Core Allocation**: **2 vCPUs (minimum)**. 
  * *Why*: Building the ISO and compiling source files uses multithreaded compilation. Multiple cores will drastically reduce build times.
* **RAM Allocation**: **2 GB (minimum) / 4 GB (recommended)**.
  * *Why*: While running Alpine takes under 50 MB, building an ISO involves generating a compressed filesystem in memory (`tmpfs` / RAM disk). If the VM runs out of RAM, compilation will crash with Out Of Memory (OOM) errors.
* **Disk Size**: **20 GB**.
  * *Why*: The base system is ~1 GB, but compiling packages, caching downloaded package repositories (`/var/cache/apk`), and outputting multiple ISO releases requires ample scratch space.
* **Virtual Disk Controller**: **SATA** or **SCSI (LSI Logic)**.
  * *Why*: These controllers have native driver support in the Alpine installation kernel, ensuring the installer can detect the virtual drive without custom configurations. Do not use NVMe controllers on older hypervisors as they can cause boot recognition issues.
* **Network Settings**: **NAT (Network Address Translation)**.
  * *Why*: NAT creates a private network segment behind your host machine. The host shares its internet connection with the VM. This is the most secure and reliable setting, avoiding issues with corporate or university network routers blocking multiple MAC addresses.

---

## 📀 Part 3: Alpine Linux Installation Steps

We will install the **Alpine Standard** ISO (do not use the "Virtual" flavor, as it lacks many drivers and development dependencies needed for the host environment).

1. **Download the ISO**: Get the latest **Alpine Standard** 64-bit ISO (e.g., version 3.20.x) from the official website.
2. **Boot the VM**: Mount the ISO to the virtual CD/DVD drive and power on the VM.
3. **Login**: At the login prompt, type `root` (no password is set for the live media).
4. **Launch Installer**: Run the interactive installer script:
   ```bash
   setup-alpine
   ```
5. **Step-by-Step Installation Prompt Choices**:
   * **Keyboard Layout**: Select your preferred layout (usually `us` and variant `us`).
   * **Hostname**: Type a descriptive host name (e.g., `novaos-build-box`).
   * **Network Configuration**: Select `eth0` and choose `dhcp`. DHCP dynamically requests IP address, gateway, and DNS servers from VMware's virtual DHCP server.
   * **Root Password**: Enter a secure password for the system administrator (`root`).
   * **Timezone**: Set to your local timezone (or `UTC`).
   * **HTTP/FTP Proxy**: Select `none` (unless your network requires a proxy).
   * **NTP Client**: Select `chrony`.
     * *Why*: Keeps system clock synchronized via Network Time Protocol. Essential for HTTPS connections, signature verifications, and git commit timestamps.
   * **APK Mirror**: Choose `f` to run a speed test and automatically select the fastest local mirror, or type `1` for the main Alpine mirror.
   * **SSH Daemon**: Choose `openssh` (do not choose `dropbear`).
     * *Why*: OpenSSH is standard, secure, and has full support for remote SFTP file synchronization and IDE integrations (like VS Code Remote-SSH).
   * **SSH Configuration**: Add the ssh daemon to default runlevel so it boots automatically:
     * *(The installer handles this automatically when selecting openssh).*
   * **Disk Setup**: The installer will scan for disks (e.g., `sda`).
     * Enter the disk name: `sda`
     * Choose disk usage: **`sys`**
       * *Why*: Alpine has three modes:
         1. *diskless (run-from-RAM)*: Boots from read-only media and saves configs on external storage.
         2. *data*: Mounts `/var` on disk, root system runs from RAM.
         3. *sys*: Normal hard disk installation where `/`, `/boot`, `/home` are fully formatted and persistent on disk. We must use `sys` for our build VM.
     * Erase disk confirmation: Type `y` to format the disk with standard `ext4` partition layout and install the `syslinux` bootloader.
6. **Reboot**: Once completed, remove the ISO from the CD/DVD virtual drive and reboot:
   ```bash
   reboot
   ```

---

## 🛠️ Part 4: Post-Installation & Developer User Setup

Log in to the VM as `root` using the password you set. Now, we must configure a non-root developer user. **This is critical: you cannot build Alpine packages or configure abuild keys as root!**

### 1. Enable Community Repositories
Edit the APK repositories configuration:
```bash
vi /etc/apk/repositories
```
Ensure the `community` repository line is uncommented (remove the `#` symbol if present). For example, it should look like:
```text
http://dl-cdn.alpinelinux.org/alpine/v3.20/main
http://dl-cdn.alpinelinux.org/alpine/v3.20/community
```
Save and close vi (`:wq`). Then update the database:
```bash
apk update
```

### 2. Install Sudo
```bash
apk add sudo
```

### 3. Create Developer User
Create a user named `dev` (or your preferred username):
```bash
adduser -g "NovaOS Developer" dev
```
Enter a secure password for this user when prompted.

### 4. Configure Sudo Privileges
Allow users in the `wheel` group to run commands with sudo:
```bash
visudo
```
Uncomment the line:
```text
%wheel ALL=(ALL:ALL) ALL
```
Add the developer user to the `wheel` group:
```bash
addgroup dev wheel
```

---

## 📦 Part 5: Configuring the Build SDK (`abuild`)

To construct NovaOS, we will need to compile custom packages and use ISO creation utilities. This requires the Alpine Software Development Kit (`abuild` and `alpine-sdk`).

### 1. Install Alpine SDK
```bash
apk add alpine-sdk
```

### 2. Add Developer to `abuild` Group
The `abuild` group has permissions to compile and sign packages.
```bash
addgroup dev abuild
```

### 3. Generate abuild Signing Keys
Log out of `root` and log back in as your developer user (`dev`):
```bash
exit
```
*Now, logged in as `dev`:*
Generate private/public cryptographic keys used to sign packages.
```bash
abuild-keygen -a -i
```
* **What this does**: It generates a 2048-bit RSA key pair.
* **Why it's needed**: Alpine's security model dictates that the system will never install packages that aren't signed by a trusted key. The `-a` flag sets this up in `~/.abuild/`, and `-i` installs the public key to `/etc/apk/keys/` using sudo, so the local package manager trusts packages built by this machine.

---

## 🚀 Part 6: Development Workflow & Git Integration

Each developer needs to access the project repository and synchronize changes with the Alpine VM.

### 1. SSH Server Configuration
To allow convenient development from VS Code, ensure SSH is running and configured.
Verify OpenRC service status:
```bash
sudo rc-service sshd status
```
Get the VM's local IP address:
```bash
ip addr show eth0
```

### 2. Connecting with VS Code Remote-SSH (Recommended Workflow)
1. On your Windows/macOS host machine, install **VS Code** and the **Remote - SSH** extension.
2. Open VS Code, press `Ctrl+Shift+P` (or `Cmd+Shift+P`), type `Remote-SSH: Connect to Host...`, and type:
   ```text
   dev@<VM_IP_ADDRESS>
   ```
3. Enter the developer user's password. VS Code will install its server components in the VM.
4. You can now open the code directories inside the VM, edit scripts directly, and open terminals running natively on Alpine!

### 3. Repository Setup
Clone the NovaOS repository inside the VM developer home directory:
```bash
cd ~
git clone <your-git-repository-url> novaos
```
Configure your Git global configuration inside the VM:
```bash
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

---

## ⚡ Part 7: Automated Setup Script

We have provided an automated dependency setup script in the repository: [setup_dev_env.sh](file:///c:/Users/adity/OneDrive/Desktop/distro/scripts/setup_dev_env.sh). 

Once you clone the repository onto your VM, you can execute this script with `sudo bash scripts/setup_dev_env.sh` to install all necessary compilers, ISO generation packages (`xorriso`, `squashfs-tools`, `grub-efi`, `syslinux`), and automatically configure groups.
