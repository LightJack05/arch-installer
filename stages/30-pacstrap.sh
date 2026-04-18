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
# For scheme Z (custom mounts) FILESYSTEM is not set by the TUI; the filesystem
# type is detected from the live mount instead.

set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=../lib/config.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/config.sh"

main() {
    cfg_load
    cfg_require INSTALL_MODE

    local target="/mnt"
    [[ "${INSTALL_MODE}" == "Z" ]] && target="${MANUAL_MOUNT}"

    # FILESYSTEM is set by the TUI for modes A-D. For mode Z the TUI skips the
    # filesystem prompt, so detect it from the live mount.
    local filesystem="${FILESYSTEM:-}"
    if [[ -z "${filesystem}" ]]; then
        filesystem="$(findmnt -no FSTYPE "${target}" 2>/dev/null || true)"
        [[ -z "${filesystem}" ]] && filesystem="ext4"
        log_info "mode Z: detected filesystem '${filesystem}' from ${target}"
    fi

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
    [[ "${filesystem}" == "btrfs" ]] && pkgs+=(btrfs-progs)
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
