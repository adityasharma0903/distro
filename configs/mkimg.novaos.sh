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
    kernel_cmdline="unionfs_size=1024M console=tty0 quiet splash"
    
    # Use our custom apkovl generator instead of the default dhcp one
    apkovl="genapkovl-novaos.sh"
    
    # ------------------ Package Selection ------------------
    # Dynamically load packages from external list files copied to aports/scripts/
    local script_dir
    script_dir=$(cd "$(dirname "$0")" && pwd)
    
    local core_list="$script_dir/novaos-packages-core.list"
    local gui_list="$script_dir/novaos-packages-gui.list"
    
    if [ -f "$core_list" ]; then
        local core_apks
        core_apks=$(grep -v '^#' "$core_list" | xargs)
        apks="$apks $core_apks"
    fi
    
    if [ -f "$gui_list" ]; then
        local gui_apks
        gui_apks=$(grep -v '^#' "$gui_list" | xargs)
        apks="$apks $gui_apks"
    fi
}
