#!/bin/bash
# stage 30-pacstrap — install the base system into /mnt.
#
# Package set includes:
#   base linux linux-firmware
#   base-devel
#   networkmanager sudo
#   neovim vim zsh
#   git
#   sbctl efibootmgr
#   zram-generator
#   ${ucode}   (amd-ucode | intel-ucode — detected from /proc/cpuinfo)
#   btrfs-progs   (if FILESYSTEM=btrfs)
#   tpm2-tools tpm2-tss   (if INSTALL_MODE=C)
#
# Skipped in full for scheme D — user is expected to have pacstrapped already.
# (We still pacman -Sy inside the chroot for anything missing.)

set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=../lib/config.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/config.sh"

detect_ucode() {
    # TODO: grep -q GenuineIntel /proc/cpuinfo && echo intel-ucode || echo amd-ucode
    :
}

main() {
    cfg_load

    local target="/mnt"
    [[ "${INSTALL_MODE}" == "D" ]] && target="${MANUAL_MOUNT}"

    local ucode
    ucode="$(detect_ucode)"

    local pkgs=(
        base linux linux-firmware base-devel
        networkmanager sudo
        neovim vim zsh git
        sbctl efibootmgr
        zram-generator
        "${ucode}"
    )
    [[ "${FILESYSTEM}" == "btrfs" ]] && pkgs+=(btrfs-progs)
    [[ "${INSTALL_MODE}" == "C" ]]   && pkgs+=(tpm2-tools tpm2-tss)

    # TODO: pacstrap -K "$target" "${pkgs[@]}"
    # TODO: genfstab -U "$target" >> "$target/etc/fstab"
    :
}

main "$@"
