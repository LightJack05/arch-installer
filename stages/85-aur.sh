#!/bin/bash
# stage 85-aur — build yay as the install user, install AUR packages unattended.
#
# Depends on /etc/sudoers.d/00-installer (created by stage 70) for NOPASSWD.
# Reads ${INSTALLER_ROOT}/config/aur-packages.txt (same format as packages.txt).

set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=../lib/config.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/config.sh"

main() {
    cfg_load
    cfg_require USERNAME

    local list="${INSTALLER_ROOT}/config/aur-packages.txt"
    [[ -r "${list}" ]] || die "AUR package list not found: ${list}"

    # TODO: build yay as the user in /home/$USERNAME/.cache/installer-build
    #   sudo -u "$USERNAME" bash -c '
    #     set -Eeuo pipefail
    #     mkdir -p ~/.cache/installer-build && cd ~/.cache/installer-build
    #     rm -rf yay && git clone https://aur.archlinux.org/yay.git
    #     cd yay && makepkg -si --noconfirm
    #   '

    # TODO: install the AUR list unattended
    #   local pkgs
    #   mapfile -t pkgs < <(grep -v '^\s*\(#\|$\)' "$list")
    #   sudo -u "$USERNAME" yay -S --noconfirm --needed \
    #     --answerclean N --answerdiff N --answeredit N \
    #     --removemake --cleanafter -- "${pkgs[@]}"
    :
}

main "$@"
