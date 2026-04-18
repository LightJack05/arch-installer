#!/bin/bash
# lib/swap.sh — zram-generator config + swapfile creation.
#
# zRAM is configured (not activated here — activates at first boot of the
# installed system). Swapfile is created on the mounted root at /mnt/swap/swapfile.
# Hibernation is not supported; resume_offset is not computed.
#
# Functions:
#   swap_write_zram_conf <target>          — writes <target>/etc/systemd/zram-generator.conf
#   swap_create_swapfile_ext4 <size> <path>
#   swap_create_swapfile_btrfs <size> <path>
#   swap_append_fstab <target> <path>      — append to <target>/etc/fstab with pri=10

set -Eeuo pipefail

# Path to the swapfile inside the installed system (mounted at /mnt during install).
readonly SWAPFILE_RELPATH="/swap/swapfile"

swap_write_zram_conf() {
    local target="$1"
    mkdir -p "${target}/etc/systemd"
    cat > "${target}/etc/systemd/zram-generator.conf" << EOF
[zram0]
zram-size = ${ZRAM_SIZE_MIB}M
compression-algorithm = zstd
swap-priority = 100
EOF
}

swap_create_swapfile_ext4() {
    local size_mib="$1" path="$2"
    run install -dm700 "$(dirname "$path")"
    run fallocate -l "${size_mib}M" "$path"
    run chmod 600 "$path"
    run mkswap "$path"
}

swap_create_swapfile_btrfs() {
    local size_mib="$1" path="$2"
    run install -dm700 "$(dirname "$path")"
    run btrfs filesystem mkswapfile --size "${size_mib}M" "$path"
}

swap_append_fstab() {
    local target="$1" path_in_root="$2"
    printf '%s none swap defaults,pri=10 0 0\n' "$path_in_root" >> "${target}/etc/fstab"
}
