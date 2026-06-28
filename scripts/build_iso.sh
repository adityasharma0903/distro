#!/bin/env bash

# build_iso.sh - NovaOS Live ISO Build Orchestrator
# This script compiles the custom NovaOS ISO. Must be executed as root on the Alpine build VM.

set -euo pipefail

# Color codes for visual styling
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

# 1. Require root execution
if [ "$EUID" -ne 0 ]; then
    error "This script requires root privileges to configure chroots and loop mounts. Please run with sudo (e.g., sudo bash $0)"
fi

# 2. Paths and Directories
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
RELEASES_DIR="$PROJECT_ROOT/releases"
APORTS_DIR="$BUILD_DIR/aports"
MKTEMP_DIR="$BUILD_DIR/tmp"

# Configure build staging to use persistent disk instead of RAM-backed /tmp
export TMPDIR="$MKTEMP_DIR"

info "Initializing NovaOS Live ISO Build..."
info "Project Root: $PROJECT_ROOT"
info "Build Directory: $BUILD_DIR"
info "Releases Directory: $RELEASES_DIR"
info "Staging Directory: $TMPDIR"

# Ensure outputs directory exists
mkdir -p "$RELEASES_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$MKTEMP_DIR"

# Check available space in root partition (15GB minimum)
# Using BusyBox compatible df columns
info "Verifying disk space..."
FREE_MB=$(df -m / | awk '$6 == "/" {print $4}')
if [ -z "$FREE_MB" ] || [[ ! "$FREE_MB" =~ ^[0-9]+$ ]]; then
    # Fallback to last line fourth field if awk exact match failed
    FREE_MB=$(df -m / | tail -n 1 | awk '{print $4}')
fi
FREE_GB=$(( FREE_MB / 1024 ))
if [ "$FREE_GB" -lt 15 ]; then
    error "At least 15GB free disk space required on root partition. Available: ${FREE_GB}GB."
fi

info "Cleaning old staging caches..."
rm -rf "$MKTEMP_DIR"/*
rm -rf /tmp/mkimage*


# 3. Ensure essential build utilities are present
info "Verifying dependencies..."
for dep in git xorriso mksquashfs grub-mkimage abuild; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        error "Required dependency '$dep' is missing. Please run 'sudo bash scripts/setup_dev_env.sh' first."
    fi
done

# 4. Generate root abuild signing keys if missing
# Why: During the ISO construction, mkimage compresses and signs kernel modules (modloop).
# Since mkimage runs as root, it requires root's abuild key to sign the modloop image.
if [ ! -f "/root/.abuild/abuild.conf" ]; then
    info "Root abuild signing keys not found. Generating them now..."
    # Generate keys (-a: system config, -i: install public key into /etc/apk/keys)
    abuild-keygen -a -i
    success "Root abuild keys generated and registered."
else
    info "Root abuild keys found."
fi

# 5. Determine the Alpine stable release branch
# We read /etc/alpine-release and match the branch version (e.g., "3.24")
ALPINEREL=$(cat /etc/alpine-release 2>/dev/null || echo "3.24")
ALPINE_VERSION=$(echo "$ALPINEREL" | cut -d'.' -f1-2)
# Check for edge or customized installs, fallback to master if needed
if [[ "$ALPINE_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
    APORTS_BRANCH="${ALPINE_VERSION}-stable"
else
    APORTS_BRANCH="3.24-stable" # default fallback
fi

# 6. Fetch/Clone aports tree
if [ ! -d "$APORTS_DIR/.git" ]; then
    info "Cloning Alpine aports repository (branch: $APORTS_BRANCH)..."
    git clone --depth=1 --branch "$APORTS_BRANCH" https://gitlab.alpinelinux.org/alpine/aports.git "$APORTS_DIR"
    success "aports repository successfully cloned."
else
    info "aports repository already exists. Updating..."
    cd "$APORTS_DIR"
    git pull --ff-only
    cd "$PROJECT_ROOT"
fi

# 7. Symlink Custom Profiles & Overlays into the aports tree
info "Registering NovaOS profile and overlay script in build tree..."

# Custom profile script
cp -f "$PROJECT_ROOT/configs/mkimg.novaos.sh" "$APORTS_DIR/scripts/mkimg.novaos.sh"
chmod +x "$APORTS_DIR/scripts/mkimg.novaos.sh"

# Copy package lists for the custom profile to read
cp -f "$PROJECT_ROOT/packages/core.list" "$APORTS_DIR/scripts/novaos-packages-core.list"
cp -f "$PROJECT_ROOT/packages/gui.list" "$APORTS_DIR/scripts/novaos-packages-gui.list"

# Custom overlay script
cp -f "$PROJECT_ROOT/configs/genapkovl-novaos.sh" "$APORTS_DIR/scripts/genapkovl-novaos.sh"
chmod +x "$APORTS_DIR/scripts/genapkovl-novaos.sh"

# Patch mkimage.sh to remove --no-chown flag (fixes 'ERROR: --usermode not allowed as root' in newer apk-tools)
info "Patching mkimage.sh to remove --no-chown..."
sed -i 's/--no-chown//g' "$APORTS_DIR/scripts/mkimage.sh"

# 8. Clean up old builds in the staging directory
# Alpine's mkimage caches files under /tmp/mkimage.*. We clean up locally to avoid size mismatches.
info "Cleaning previous build cache..."
rm -rf "$BUILD_DIR/iso_staging"
mkdir -p "$BUILD_DIR/iso_staging"

# 9. Execute the ISO compilation
info "Compiling NovaOS Live ISO (this may take several minutes)..."
cd "$APORTS_DIR/scripts"

# We run mkimage.sh with standard flags:
# - --profile: Use our custom novaos profile
# - --outdir: Place resulting ISOs in our local releases folder
# - --arch: Target architecture (amd64 / x86_64)
# - --tag: Version tag
# - --repository: Target package mirrors
./mkimage.sh \
  --profile novaos \
  --tag "1.0" \
  --outdir "$RELEASES_DIR" \
  --arch x86_64 \
  --repository "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/main" \
  --repository "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/community"

# 10. Verification of output
cd "$PROJECT_ROOT"
ISO_OUTPUT=$(find "$RELEASES_DIR" -name "alpine-novaos-1.0-x86_64.iso" -o -name "novaos-1.0-x86_64.iso" -o -name "*novaos*.iso" | head -n 1)

if [ -n "$ISO_OUTPUT" ] && [ -f "$ISO_OUTPUT" ]; then
    success "NovaOS Live ISO successfully built!"
    info "ISO Path: $ISO_OUTPUT"
    info "ISO Size: $(du -sh "$ISO_OUTPUT" | cut -f1)"
    info "You can now copy this ISO to your host and boot it in VMware/VirtualBox."
else
    error "ISO build completed, but output file could not be verified."
fi
