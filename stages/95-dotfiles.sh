#!/bin/bash
# stage 95-dotfiles — clone the user's dotfiles and run the setup script.
#
# Opt-out (DOTFILES_ENABLED=0 to skip). Uses the gh token captured in stage 10
# (now at /root/.installer-ghtoken, mode 0600). Token is used once, then shredded
# by stage 99.

set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=../lib/config.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/config.sh"

main() {
    cfg_load
    cfg_require USERNAME

    if [[ "${DOTFILES_ENABLED:-1}" != "1" ]]; then
        log_info "dotfiles disabled — skipping"
        return 0
    fi

    local token_file="/root/.installer-ghtoken"
    local home="/home/${USERNAME}"

    if [[ -s "$token_file" ]]; then
        local token
        token=$(cat "$token_file")

        # Auth gh as the user
        run sudo -u "$USERNAME" bash -c "
            set -Eeuo pipefail
            mkdir -p ~/.config/gh
            printf '%s' '${token}' | gh auth login --with-token
            gh auth setup-git
        "
        log_info "gh authenticated for ${USERNAME}"

        # Clone dotfiles
        run sudo -u "$USERNAME" git clone \
            https://github.com/LightJack05/dotfiles \
            --recursive \
            "${home}/dotfiles"
        log_info "dotfiles cloned to ${home}/dotfiles"

        # Run setup script
        run sudo -u "$USERNAME" "${home}/dotfiles/setup-complete.sh"
        log_info "dotfiles setup script completed"

        # Shred the token from the chroot side
        shred -u "$token_file" 2>/dev/null || rm -f "$token_file"
        log_info "GH token shredded"
    else
        log_warn "no gh token found at ${token_file} — skipping dotfiles"
    fi

    log_info "dotfiles stage complete"
}

main "$@"
