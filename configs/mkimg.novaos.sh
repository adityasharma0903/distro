# mkimg.novaos.sh - NovaOS Build Profile
# This file is loaded by Alpine's mkimage.sh tool during ISO creation.

profile_novaos() {
    # Inherit from the base minimal profile to avoid conflicting legacy packages (like vlan/network-extras)
    profile_base
    
    # OS Metadata
    profile_abbrev="novaos"
    title="NovaOS"
    desc="NovaOS Live Desktop Edition"
    image_name="novaos"
    image_ext="iso"
    output_format="iso"
    arch="x86_64"
    
    # Boot command line options
    kernel_cmdline="unionfs_size=1024M console=tty0 quiet splash"
    
    # Use our custom apkovl generator instead of the default dhcp one
    apkovl="genapkovl-novaos.sh"
    
    # ------------------ Package Selection ------------------
    # Dynamically load packages from external group list files copied by build_iso.sh
    local script_dir
    script_dir=$(cd "$(dirname "$0")" && pwd)
    
    for list_name in core desktop network multimedia developer; do
        local list_file="$script_dir/novaos-packages-${list_name}.list"
        if [ -f "$list_file" ]; then
            local file_apks
            file_apks=$(grep -v '^#' "$list_file" | xargs)
            apks="$apks $file_apks"
        fi
    done
}
