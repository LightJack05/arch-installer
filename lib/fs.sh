#!/bin/bash
# lib/fs.sh — filesystem creation + mount for /efi and /.
#
# ext4: mkfs.ext4 → mount at target.
# btrfs: mkfs.btrfs, then subvols @ @home @log @pkg @swap, mounted with
# noatime,compress=zstd,space_cache=v2 (except @swap which is NOCOW +
# no-compression so the swapfile works).
#
# Functions:
#   fs_mkfs_esp <part>
#   fs_mkfs_root_ext4 <dev>
#   fs_mkfs_root_btrfs <dev>
#   fs_create_btrfs_subvols <dev>
#   fs_mount_ext4 <dev> <target>
#   fs_mount_btrfs <dev> <target>
#   fs_mount_esp <esp_part> <target>
#   fs_unmount_all <target>

set -Eeuo pipefail

# Guard against double-sourcing.
if [[ "${__INSTALLER_FS_SOURCED:-0}" == "1" ]]; then
    return 0
fi
readonly __INSTALLER_FS_SOURCED=1

# Source common.sh if not already loaded.
_FS_DIR="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${__INSTALLER_COMMON_SOURCED:-0}" != "1" ]]; then
    # shellcheck source=common.sh
    source "${_FS_DIR}/common.sh"
fi

# fs_mkfs_esp <part>
# Format the EFI System Partition as FAT32.
fs_mkfs_esp() {
    local part="$1"
    run mkfs.vfat -F32 -n ESP "${part}"
}

# fs_mkfs_root_ext4 <dev>
# Format the root device as ext4.
fs_mkfs_root_ext4() {
    local dev="$1"
    run mkfs.ext4 -F -L arch "${dev}"
}

# fs_mkfs_root_btrfs <dev>
# Format the root device as btrfs.
fs_mkfs_root_btrfs() {
    local dev="$1"
    run mkfs.btrfs -f -L arch "${dev}"
}

# fs_create_btrfs_subvols <dev>
# Mount the btrfs device to a temp dir, create the standard subvolume layout,
# then unmount. The subvols created are:
#   @      — root (/)
#   @home  — /home
#   @log   — /var/log
#   @pkg   — /var/cache/pacman/pkg
#   @swap  — /swap  (NOCOW; holds swapfile; no compression at mount time)
fs_create_btrfs_subvols() {
    local dev="$1"
    local tmp
    tmp=$(mktemp -d)
    run mount "${dev}" "${tmp}"
    run btrfs subvolume create "${tmp}/@"
    run btrfs subvolume create "${tmp}/@home"
    run btrfs subvolume create "${tmp}/@log"
    run btrfs subvolume create "${tmp}/@pkg"
    run btrfs subvolume create "${tmp}/@swap"
    run umount "${tmp}"
    rmdir "${tmp}"
}

# fs_mount_ext4 <dev> <target>
# Mount an ext4 root filesystem and create the swap directory.
fs_mount_ext4() {
    local dev="$1" target="$2"
    run mkdir -p "${target}"
    run mount "${dev}" "${target}"
    run mkdir -p "${target}/swap"
}

# fs_mount_btrfs <dev> <target>
# Mount all btrfs subvolumes at the appropriate paths under <target>.
# @swap is mounted without compression (NOCOW is set via chattr).
fs_mount_btrfs() {
    local dev="$1" target="$2"
    local opts="noatime,compress=zstd,space_cache=v2"

    run mkdir -p "${target}"
    run mount -o "subvol=@,${opts}" "${dev}" "${target}"

    run mkdir -p "${target}/home"
    run mkdir -p "${target}/var/log"
    run mkdir -p "${target}/var/cache/pacman/pkg"
    run mkdir -p "${target}/swap"

    run mount -o "subvol=@home,${opts}"  "${dev}" "${target}/home"
    run mount -o "subvol=@log,${opts}"   "${dev}" "${target}/var/log"
    run mount -o "subvol=@pkg,${opts}"   "${dev}" "${target}/var/cache/pacman/pkg"
    # @swap: NOCOW, no compression — swapfile requires it.
    run mount -o "subvol=@swap,noatime"  "${dev}" "${target}/swap"
    # Mark the swap directory NOCOW so the kernel honours it for the swapfile.
    run chattr +C "${target}/swap" 2>/dev/null || true
}

# fs_mount_esp <esp_part> <target>
# Mount the EFI System Partition at <target>/efi.
fs_mount_esp() {
    local esp_part="$1" target="$2"
    run mkdir -p "${target}/efi"
    run mount "${esp_part}" "${target}/efi"
}

# fs_unmount_all <target>
# Deactivate all swap and recursively unmount everything under <target>.
fs_unmount_all() {
    local target="${1:-/mnt}"
    swapoff -a 2>/dev/null || true
    umount -R "${target}" 2>/dev/null || true
}
