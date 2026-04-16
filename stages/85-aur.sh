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

    # Build yay as the user in a temp build dir
    local build_dir="/home/${USERNAME}/.cache/installer-build"
    run mkdir -p "$build_dir"
    run chown "${USERNAME}:${USERNAME}" "$build_dir"

    log_info "building yay as ${USERNAME}"
    run sudo -u "$USERNAME" bash -c "
        set -Eeuo pipefail
        cd '${build_dir}'
        rm -rf yay
        git clone https://aur.archlinux.org/yay.git
        cd yay
        makepkg -si --noconfirm
    "
    log_info "yay installed successfully"

    # Parse AUR package list
    local pkgs=()
    while IFS= read -r line; do
        line="${line%%#*}"
        line="${line//[[:space:]]/}"
        [[ -z "$line" ]] && continue
        pkgs+=("$line")
    done < "${list}"

    if (( ${#pkgs[@]} > 0 )); then
        log_info "installing ${#pkgs[@]} AUR packages as ${USERNAME}"
        run sudo -u "$USERNAME" yay -S \
            --noconfirm --needed \
            --answerclean N --answerdiff N --answeredit N \
            --removemake --cleanafter \
            -- "${pkgs[@]}"
        log_info "AUR package installation complete"
    else
        log_info "AUR package list is empty — nothing to install"
    fi

    # Clean up build directory
    rm -rf "$build_dir"
    log_info "cleaned up build directory"
}

main "$@"
