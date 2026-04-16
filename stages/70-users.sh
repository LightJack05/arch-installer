#!/bin/bash
# stage 70-users — create the primary user, set hashed passwords.
#
# Passwords are already SHA-512 hashed in /tmp/installer.env (openssl passwd -6)
# — this stage never sees plaintext.
#
# Also drops /etc/sudoers.d/00-installer with NOPASSWD for the user so stage 85
# can run yay unattended. Stage 99 removes it.

set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=../lib/config.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/config.sh"

main() {
    cfg_load
    cfg_require USERNAME USER_PASSWORD_HASH

    # TODO: useradd -m -G wheel -s "${USER_SHELL}" -c "${USER_FULLNAME:-}" "${USERNAME}"
    # TODO: printf '%s:%s\n' "${USERNAME}" "${USER_PASSWORD_HASH}" | chpasswd -e

    if [[ -n "${ROOT_PASSWORD_HASH:-}" ]]; then
        # TODO: printf 'root:%s\n' "${ROOT_PASSWORD_HASH}" | chpasswd -e
        :
    else
        # TODO: passwd -l root   (disable root login)
        :
    fi

    # TODO: install -m 0440 /dev/stdin /etc/sudoers.d/00-installer <<< "${USERNAME} ALL=(ALL:ALL) NOPASSWD: ALL"
    :
}

main "$@"
