#!/bin/bash
# stage 40-chroot — hand off to the new system.
#
#   1. copy this installer repo into /mnt/root/arch-installer
#   2. move /tmp/installer.env → /mnt/root/arch-installer/installer.env (0600)
#   3. move /tmp/installer.ghtoken (if present) → /mnt/root/.installer-ghtoken (0600)
#   4. copy the install log so chroot stages keep writing to the same file
#   5. arch-chroot and re-invoke install.sh with INSTALLER_IN_CHROOT=1

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

    # 1. Copy the installer repo into the new system
    local dest="${target}/root/arch-installer"
    rm -rf "$dest"
    cp -aT "$INSTALLER_ROOT" "$dest"
    log_info "copied installer repo to ${dest}"

    # 2. Move the env file into the chroot copy
    install -m 0600 "$INSTALLER_ENV" "${dest}/installer.env"
    log_info "installed env file to ${dest}/installer.env"

    # 3. Move the GH token if present
    if [[ -s "$INSTALLER_GH_TOKEN_FILE" ]]; then
        install -m 0600 "$INSTALLER_GH_TOKEN_FILE" "${target}/root/.installer-ghtoken"
        log_info "installed GH token to ${target}/root/.installer-ghtoken"
    fi

    # 4. Set up log file in the target
    mkdir -p "${target}/var/log"
    cp "$INSTALLER_LOG" "${target}/var/log/installer.log" 2>/dev/null || true
    log_info "log file available in chroot at /var/log/installer.log"

    # 5. arch-chroot and re-run install.sh for the in-chroot stages
    run arch-chroot "$target" /usr/bin/env \
        INSTALLER_IN_CHROOT=1 \
        INSTALLER_ROOT=/root/arch-installer \
        INSTALLER_ENV=/root/arch-installer/installer.env \
        INSTALLER_LOG=/var/log/installer.log \
        bash /root/arch-installer/install.sh

    log_info "chroot stage complete"
}

main "$@"
