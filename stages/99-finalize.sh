#!/bin/bash
# stage 99-finalize — remove the NOPASSWD dropin, shred secrets, print reboot prompt.
#
# Runs cleanup FIRST so a failure in the message printing can't leave
# NOPASSWD sudoers on the installed system.

set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=../lib/config.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/config.sh"

main() {
    cfg_load

    # 1. Remove NOPASSWD dropin unconditionally.
    rm -f /etc/sudoers.d/00-installer || true

    # 2. Shred secrets from env + token files (both sides of the chroot).
    cfg_shred

    # 3. Optional flourish: figlet/lolcat "Done!" if present (do not fail if missing).
    # TODO: command -v figlet >/dev/null && command -v lolcat >/dev/null \
    #         && figlet 'Done!' | lolcat

    log_info "installation complete — reboot when ready"
}

main "$@"
