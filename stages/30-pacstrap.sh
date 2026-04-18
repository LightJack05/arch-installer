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
#   tpm2-tools tpm2-tss   (if INSTALL_MODE=C or D)
#
# Skipped in full for scheme Z — user is expected to have pacstrapped already.
# (We still pacman -Sy inside the chroot for anything missing.)

set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=../lib/config.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/config.sh"

main() {
    cfg_load
    cfg_require INSTALL_MODE FILESYSTEM

    local target="/mnt"
    [[ "${INSTALL_MODE}" == "Z" ]] && target="${MANUAL_MOUNT}"

    # Detect microcode
    local ucode
    if grep -q 'GenuineIntel' /proc/cpuinfo; then
        ucode=intel-ucode
    else
        ucode=amd-ucode
    fi
    log_info "detected microcode package: ${ucode}"

    local pkgs=(
        base linux linux-firmware base-devel
        networkmanager sudo
        neovim vim zsh git
        sbctl efibootmgr
        zram-generator
        "$ucode"
    )
    [[ "$FILESYSTEM" == "btrfs" ]] && pkgs+=(btrfs-progs)
    [[ "${INSTALL_MODE}" == "C" || "${INSTALL_MODE}" == "D" ]] && pkgs+=(tpm2-tools tpm2-tss)

    log_info "pacstrapping into ${target} with packages: ${pkgs[*]}"
    run pacstrap -K "$target" "${pkgs[@]}"

    log_info "generating fstab"
    run bash -c "genfstab -U '${target}' >> '${target}/etc/fstab'"
    log_info "fstab contents:"
    cat "${target}/etc/fstab" >&2

    log_info "pacstrap complete"
}

main "$@"
