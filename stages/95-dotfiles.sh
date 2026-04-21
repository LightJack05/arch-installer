#!/bin/bash
# stage 95-dotfiles — clone the user's dotfiles and run the setup script.
#
# Opt-out (DOTFILES_ENABLED=0 to skip). Uses the gh token captured in stage 10
# (now at /root/.installer-ghtoken, mode 0600). Token is used once, then shredded
# by stage 99.
#
# Config keys (set in stage 10 / defaults.env):
#   DOTFILES_REPO         — git repository URL to clone
#   DOTFILES_SETUP_SCRIPT — setup script path relative to the clone directory

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

    cfg_require DOTFILES_REPO DOTFILES_SETUP_SCRIPT

    local token_file="/root/.installer-ghtoken"
    local home="/home/${USERNAME}"
    local clone_dir
    clone_dir="$(basename "${DOTFILES_REPO}" .git)"

    if [[ -s "$token_file" ]]; then
        # Auth gh as the user. Feed the token file directly to avoid it appearing
        # on any process command line.
        run sudo -u "$USERNAME" bash -c "
            set -Eeuo pipefail
            mkdir -p ~/.config/gh
            gh auth login --with-token
            gh auth setup-git
        " < "$token_file"
        log_info "gh authenticated for ${USERNAME}"

        # Clone dotfiles
        run sudo -u "$USERNAME" git clone \
            "${DOTFILES_REPO}" \
            --recursive \
            "${home}/${clone_dir}"
        log_info "dotfiles cloned to ${home}/${clone_dir}"

        # Run setup script
        run sudo -u "$USERNAME" "${home}/${clone_dir}/${DOTFILES_SETUP_SCRIPT}"
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
