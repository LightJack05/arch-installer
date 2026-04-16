#!/bin/bash
# stage 40-chroot — hand off to the new system.
#
#   1. copy this installer repo into /mnt/root/arch-installer
#   2. move /tmp/installer.env → /mnt/root/arch-installer/installer.env (0600)
#   3. move /tmp/installer.ghtoken (if present) → /mnt/root/.installer-ghtoken (0600)
#   4. symlink the install log so chroot stages keep writing to the same file
#   5. arch-chroot and re-invoke install.sh with INSTALLER_IN_CHROOT=1

set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=../lib/config.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/config.sh"

main() {
    cfg_load

    local target="/mnt"
    [[ "${INSTALL_MODE}" == "D" ]] && target="${MANUAL_MOUNT}"

    # TODO: mkdir -p "$target/root/arch-installer"
    # TODO: cp -aT "$INSTALLER_ROOT" "$target/root/arch-installer"
    # TODO: install -m 0600 "$INSTALLER_ENV" "$target/root/arch-installer/installer.env"
    # TODO: if [[ -s "$INSTALLER_GH_TOKEN_FILE" ]]; then
    #         install -m 0600 "$INSTALLER_GH_TOKEN_FILE" "$target/root/.installer-ghtoken"
    #       fi
    # TODO: mkdir -p "$target/var/log"; touch "$target/var/log/installer.log"; chmod 600 ...
    # TODO: arch-chroot "$target" /usr/bin/env \
    #         INSTALLER_IN_CHROOT=1 \
    #         INSTALLER_ENV=/root/arch-installer/installer.env \
    #         INSTALLER_LOG=/var/log/installer.log \
    #         bash /root/arch-installer/install.sh
    :
}

main "$@"
