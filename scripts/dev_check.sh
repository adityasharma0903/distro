#!/usr/bin/env bash

# dev_check.sh - Quick NovaOS repository sanity checks for fast iteration.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

info() {
    echo "[INFO] $1"
}

ok() {
    echo "[OK] $1"
}

fail() {
    echo "[ERROR] $1" >&2
    exit 1
}

info "Running shell syntax checks..."
for script_path in \
    "$ROOT_DIR/scripts/build_iso.sh" \
    "$ROOT_DIR/scripts/setup_dev_env.sh" \
    "$ROOT_DIR/configs/genapkovl-novaos.sh" \
    "$ROOT_DIR/configs/mkimg.novaos.sh"
do
    [ -f "$script_path" ] || fail "Missing file: $script_path"
    bash -n "$script_path"
    ok "Syntax OK: ${script_path#"$ROOT_DIR/"}"
done

info "Checking desktop session wiring..."
grep -q '^lxqt-session$' "$ROOT_DIR/packages/desktop.list" || fail "packages/desktop.list is missing lxqt-session"
grep -q '^openbox$' "$ROOT_DIR/packages/desktop.list" || fail "packages/desktop.list is missing openbox"
grep -q '^lightdm-gtk-greeter$' "$ROOT_DIR/packages/desktop.list" || fail "packages/desktop.list is missing lightdm-gtk-greeter"
ok "Desktop package list looks consistent"

info "Checking LightDM fallback files..."
grep -q 'exec startlxqt' "$ROOT_DIR/configs/genapkovl-novaos.sh" || fail "genapkovl-novaos.sh does not create an LXQt session fallback"
grep -q 'rc_add local boot' "$ROOT_DIR/configs/genapkovl-novaos.sh" || fail "genapkovl-novaos.sh does not start local service in boot runlevel"
ok "LightDM/LXQt boot path looks wired"

ok "NovaOS quick check completed successfully"