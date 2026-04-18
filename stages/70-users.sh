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

    # Create the user. -c (GECOS) is only passed when USER_FULLNAME is set.
    local gecos_args=()
    [[ -n "${USER_FULLNAME:-}" ]] && gecos_args=(-c "${USER_FULLNAME}")
    useradd -m -G wheel -s "${USER_SHELL:-/usr/bin/zsh}" "${gecos_args[@]}" "$USERNAME"

    # Set hashed user password — never log the hash.
    run_quiet bash -c 'printf "%s:%s\n" "$1" "$2" | chpasswd -e' \
        _ "$USERNAME" "$USER_PASSWORD_HASH"

    # Set root password or lock root login.
    if [[ -n "${ROOT_PASSWORD_HASH:-}" ]]; then
        run_quiet bash -c 'printf "root:%s\n" "$1" | chpasswd -e' _ "$ROOT_PASSWORD_HASH"
    else
        run passwd -l root
    fi

    # Install NOPASSWD sudoers dropin for unattended AUR stage.
    printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$USERNAME" \
        > /etc/sudoers.d/00-installer
    chmod 0440 /etc/sudoers.d/00-installer

    # Verify the resulting sudoers configuration is syntactically valid.
    visudo -c || die "sudoers syntax check failed"

    log_info "user '${USERNAME}' created successfully"
}

main "$@"
