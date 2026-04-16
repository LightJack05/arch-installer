#!/bin/bash
# stage 50-system — base system configuration (runs inside the chroot).
#
#   - timezone symlink + hwclock
#   - locale.gen + locale-gen + /etc/locale.conf
#   - /etc/vconsole.conf keymap
#   - /etc/hostname
#   - /etc/sudoers: enable %wheel ALL=(ALL:ALL) ALL
#   - pacman.conf: enable [multilib]; Color; ParallelDownloads=10; VerbosePkgLists

set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=../lib/config.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/config.sh"

main() {
    cfg_load
    cfg_require TIMEZONE LOCALE KEYMAP HOSTNAME

    # TODO: ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
    # TODO: hwclock --systohc

    # TODO: printf '%s UTF-8\n' "${LOCALE}" > /etc/locale.gen
    # TODO: locale-gen
    # TODO: printf 'LANG=%s\n' "${LOCALE}" > /etc/locale.conf
    # TODO: printf 'KEYMAP=%s\n' "${KEYMAP}" > /etc/vconsole.conf

    # TODO: printf '%s\n' "${HOSTNAME}" > /etc/hostname

    # TODO: sed -i 's/^#\s*\(%wheel\s\+ALL=(ALL:ALL)\s\+ALL\)/\1/' /etc/sudoers

    # TODO: enable [multilib] in /etc/pacman.conf (idempotent — check before appending)
    # TODO: enable Color, ParallelDownloads=10, VerbosePkgLists

    # TODO: pacman -Sy
    :
}

main "$@"
