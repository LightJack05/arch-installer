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
#   5. mkinitcpio -P   (UKI rebuild; sbctl pacman hook signs if SB enabled)
#
# Optional: remove the stock `linux` package if the user wants only Surface
#           (guarded behind SURFACE_REPLACE_STOCK=1). Default: keep both.

set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

readonly SURFACE_KEY_FPR='56C464BAAC421453'
readonly SURFACE_KEY_URL='https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc'
readonly SURFACE_REPO_URL='https://pkg.surfacelinux.com/arch/'

main() {
    # TODO: curl -fsSL "$SURFACE_KEY_URL" | pacman-key --add -
    # TODO: pacman-key --finger "$SURFACE_KEY_FPR"
    # TODO: pacman-key --lsign-key "$SURFACE_KEY_FPR"

    # TODO: if ! grep -q '^\[linux-surface\]' /etc/pacman.conf; then
    #         printf '\n[linux-surface]\nServer = %s\n' "$SURFACE_REPO_URL" >> /etc/pacman.conf
    #       fi
    # TODO: pacman -Syu --noconfirm linux-surface linux-surface-headers iptsd

    # TODO: write /etc/mkinitcpio.d/linux-surface.preset (UKI output at
    #       /efi/EFI/Linux/arch-linux-surface.efi)
    # TODO: mkinitcpio -P
    :
}

main "$@"
