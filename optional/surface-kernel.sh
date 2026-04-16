#!/bin/bash
# optional/surface-kernel.sh — replace stock kernel with linux-surface.
#
# Rewritten for UKI (the old script called grub-mkconfig which is wrong here).
#
# Steps:
#   1. add the linux-surface pacman-key and trust it
#   2. add the [linux-surface] repository to /etc/pacman.conf
#   3. pacman -Syu linux-surface linux-surface-headers iptsd
#   4. write a linux-surface.preset mirroring our linux.preset (UKI output)
#   5. mkinitcpio -p linux-surface   (UKI rebuild)
#   6. if SECURE_BOOT=1: sign the new UKIs

set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

readonly SURFACE_KEY_FPR='56C464BAAC421453'
readonly SURFACE_KEY_URL='https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc'
readonly SURFACE_REPO_URL='https://pkg.surfacelinux.com/arch/'

main() {
    log_info "adding linux-surface signing key"
    run curl -fsSL "${SURFACE_KEY_URL}" | pacman-key --add -
    run pacman-key --finger "${SURFACE_KEY_FPR}"
    run pacman-key --lsign-key "${SURFACE_KEY_FPR}"

    log_info "adding [linux-surface] repository to pacman.conf"
    if ! grep -q '^\[linux-surface\]' /etc/pacman.conf; then
        printf '\n[linux-surface]\nServer = %s\n' "${SURFACE_REPO_URL}" \
            >> /etc/pacman.conf
    fi

    log_info "installing linux-surface packages"
    run pacman -Syu --noconfirm linux-surface linux-surface-headers iptsd

    log_info "writing linux-surface mkinitcpio preset"
    mkdir -p /efi/EFI/Linux
    cat > /etc/mkinitcpio.d/linux-surface.preset << 'EOF'
# mkinitcpio preset file for the 'linux-surface' package

ALL_kver="/boot/vmlinuz-linux-surface"
ALL_microcode=(/boot/*-ucode.img)

PRESETS=('default' 'fallback')

default_uki="/efi/EFI/Linux/arch-linux-surface.efi"
default_options="--cmdline /etc/kernel/cmdline"

fallback_uki="/efi/EFI/Linux/arch-linux-surface-fallback.efi"
fallback_options="-S autodetect"
EOF

    log_info "building linux-surface UKI"
    run mkinitcpio -p linux-surface

    if [[ "${SECURE_BOOT:-0}" == "1" ]]; then
        log_info "signing linux-surface UKIs for secure boot"
        # shellcheck source=../lib/secureboot.sh
        source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/secureboot.sh"
        run sbctl sign -s /efi/EFI/Linux/arch-linux-surface.efi
        run sbctl sign -s /efi/EFI/Linux/arch-linux-surface-fallback.efi || true
    fi

    log_info "linux-surface kernel installed successfully"
}

main "$@"
