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

    # 1. Timezone
    run ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
    run hwclock --systohc
    log_info "timezone set to ${TIMEZONE}"

    # 2. Locale
    printf '%s UTF-8\n' "$LOCALE" > /etc/locale.gen
    run locale-gen
    printf 'LANG=%s\n' "$LOCALE" > /etc/locale.conf
    log_info "locale set to ${LOCALE}"

    # 3. Console keymap
    printf 'KEYMAP=%s\n' "$KEYMAP" > /etc/vconsole.conf
    log_info "keymap set to ${KEYMAP}"

    # 4. Hostname
    printf '%s\n' "$HOSTNAME" > /etc/hostname
    log_info "hostname set to ${HOSTNAME}"

    # 5. Enable wheel sudo
    sed -i 's/^#[[:space:]]*\(%wheel[[:space:]]\+ALL=(ALL:ALL)[[:space:]]\+ALL\)/\1/' \
        /etc/sudoers
    log_info "wheel sudo enabled"

    # 6. Enable multilib in pacman.conf (idempotent)
    if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
        printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> /etc/pacman.conf
        log_info "multilib repository enabled"
    else
        log_info "multilib already enabled"
    fi

    # 7. Enable useful pacman.conf options
    sed -i 's/^#Color/Color/' /etc/pacman.conf
    sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
    grep -q '^VerbosePkgLists' /etc/pacman.conf || \
        sed -i '/^Color/a VerbosePkgLists' /etc/pacman.conf
    log_info "pacman.conf options configured (Color, ParallelDownloads, VerbosePkgLists)"

    # 8. Refresh pacman database
    run pacman -Sy
    log_info "system configuration complete"
}

main "$@"
