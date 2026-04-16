#!/bin/bash
# lib/fs.sh — filesystem creation + mount for /efi and /.
#
# ext4: mkfs.ext4 → mount at /mnt.
# btrfs: mkfs.btrfs, then subvols @ @home @log @pkg @swap, mounted with
# noatime,compress=zstd,space_cache=v2 (except @swap which is NOCOW +
# no-compression so the swapfile works).
#
# Functions:
#   fs_mkfs_esp <part>                    — mkfs.vfat -F32 -n ESP
#   fs_mkfs_root_ext4 <devmapper|part>
#   fs_mkfs_root_btrfs <devmapper|part>
#   fs_mount_scheme_a <root-part> <esp-part>
#   fs_mount_scheme_bc <cryptroot-mapper> <esp-part>
#   fs_mount_btrfs_subvols <device> <target>  — creates + mounts @, @home, etc.
#   fs_unmount_all                        — umount -R /mnt; swapoff if needed

set -Eeuo pipefail

fs_mkfs_esp() {
    local part="$1"
    # TODO: mkfs.vfat -F32 -n ESP "$part"
    :
}

fs_mkfs_root_ext4() {
    local dev="$1"
    # TODO: mkfs.ext4 -F -L arch "$dev"
    :
}

fs_mkfs_root_btrfs() {
    local dev="$1"
    # TODO: mkfs.btrfs -f -L arch "$dev"
    :
}

fs_create_btrfs_subvols() {
    local dev="$1"
    # TODO:
    #   mount "$dev" /mnt
    #   btrfs subvolume create /mnt/@
    #   btrfs subvolume create /mnt/@home
    #   btrfs subvolume create /mnt/@log
    #   btrfs subvolume create /mnt/@pkg
    #   btrfs subvolume create /mnt/@swap
    #   umount /mnt
    :
}

fs_mount_btrfs_subvols() {
    local dev="$1" target="$2"
    # TODO:
    #   local common=noatime,compress=zstd,space_cache=v2
    #   mount -o "subvol=@,${common}" "$dev" "$target"
    #   mkdir -p "$target"/{home,var/log,var/cache/pacman/pkg,swap}
    #   mount -o "subvol=@home,${common}" "$dev" "$target/home"
    #   mount -o "subvol=@log,${common}"  "$dev" "$target/var/log"
    #   mount -o "subvol=@pkg,${common}"  "$dev" "$target/var/cache/pacman/pkg"
    #   mount -o subvol=@swap,noatime     "$dev" "$target/swap"
    :
}

fs_mount_scheme_a() {
    local root_part="$1" esp_part="$2"
    # TODO: mount "$root_part" /mnt (or btrfs subvol mount)
    # TODO: mkdir -p /mnt/efi && mount "$esp_part" /mnt/efi
    :
}

fs_mount_scheme_bc() {
    local crypt_dev="$1" esp_part="$2"
    # TODO: mount /dev/mapper/cryptroot /mnt (or btrfs subvol mount)
    # TODO: mkdir -p /mnt/efi && mount "$esp_part" /mnt/efi
    :
}

fs_unmount_all() {
    # TODO: swapoff -a; umount -R /mnt || true
    :
}
