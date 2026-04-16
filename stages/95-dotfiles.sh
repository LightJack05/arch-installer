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
        log_info "dotfiles disabled in TUI — skipping"
        return 0
    fi

    local token_file="/root/.installer-ghtoken"
    local home="/home/${USERNAME}"

    # TODO: ensure gh + git installed (they should be, via packages.txt)
    # TODO: if [[ -s "$token_file" ]]; then
    #         install -Dm 0600 -o "$USERNAME" -g "$USERNAME" \
    #             "$token_file" "$home/.config/installer-ghtoken"
    #         sudo -u "$USERNAME" bash -c '
    #             set -Eeuo pipefail
    #             export GH_TOKEN=$(cat ~/.config/installer-ghtoken)
    #             gh auth status || gh auth login --with-token <<<"$GH_TOKEN"
    #             gh auth setup-git
    #             git clone https://github.com/LightJack05/dotfiles --recursive ~/dotfiles
    #             ~/dotfiles/setup-complete.sh
    #             shred -u ~/.config/installer-ghtoken
    #         '
    #       fi
    :
}

main "$@"
