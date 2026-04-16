#!/bin/bash
# lib/swap.sh — zram-generator config + swapfile creation + resume_offset.
#
# zRAM is configured (not activated here — activates at first boot of the
# installed system). Swapfile is created on the mounted root at /mnt/swap/swapfile.
#
# Functions:
#   swap_write_zram_conf <target>          — writes <target>/etc/systemd/zram-generator.conf
#   swap_create_swapfile_ext4 <size> <path>
#   swap_create_swapfile_btrfs <size> <path>
#   swap_resume_offset_ext4 <path>         — echo resume_offset
#   swap_resume_offset_btrfs <path>        — echo resume_offset
#   swap_append_fstab <target> <path>      — append to <target>/etc/fstab with pri=10

set -Eeuo pipefail

# Path to the swapfile inside the installed system (mounted at /mnt during install).
readonly SWAPFILE_RELPATH="/swap/swapfile"

swap_write_zram_conf() {
    local target="$1"
    # TODO: mkdir -p "$target/etc/systemd"
    # TODO: write:
    #   [zram0]
    #   zram-size = min(ram / 2, 8192)
    #   compression-algorithm = zstd
    #   swap-priority = 100
    :
}

swap_create_swapfile_ext4() {
    local size_mib="$1" path="$2"
    # TODO:
    #   install -dm700 "$(dirname "$path")"
    #   fallocate -l "${size_mib}M" "$path"
    #   chmod 600 "$path"
    #   mkswap "$path"
    :
}

swap_create_swapfile_btrfs() {
    local size_mib="$1" path="$2"
    # TODO:
    #   install -dm700 "$(dirname "$path")"
    #   btrfs filesystem mkswapfile --size "${size_mib}M" "$path"
    # `mkswapfile` handles NOCOW, preallocation, and mkswap.
    :
}

swap_resume_offset_ext4() {
    local path="$1"
    # TODO: filefrag -v "$path" | awk 'NR==4 {gsub(/\./,"",$4); print $4; exit}'
    :
}

swap_resume_offset_btrfs() {
    local path="$1"
    # TODO: btrfs inspect-internal map-swapfile -r "$path"
    :
}

swap_append_fstab() {
    local target="$1" path_in_root="$2"
    # TODO: printf '%s none swap defaults,pri=10 0 0\n' "$path_in_root" >> "$target/etc/fstab"
    :
}
