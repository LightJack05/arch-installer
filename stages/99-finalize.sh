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
    # 1. Remove NOPASSWD dropin unconditionally (first thing, even if other cleanup fails)
    rm -f /etc/sudoers.d/00-installer
    log_info "removed NOPASSWD sudoers dropin"

    # 2. Capture values needed after shred, then shred secrets
    cfg_require USERNAME
    local username="${USERNAME}"
    cfg_shred

    # 3. Clean up build artifacts
    local build_dir="/home/${username}/.cache/installer-build"
    rm -rf "$build_dir" 2>/dev/null || true

    # 4. Optional victory banner
    if command -v figlet >/dev/null 2>&1 && command -v lolcat >/dev/null 2>&1; then
        figlet -f slant "Install Completed! Reboot at your convenience." | lolcat || true
        figlet -f slant "Have a nice day. :)" | lolcat || true
    fi

}

main "$@"
