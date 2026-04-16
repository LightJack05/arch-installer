#!/bin/bash
# stage 80-packages — install the curated pacman package list.
#
# Reads from ${INSTALLER_ROOT}/config/packages.txt (one package per line,
# '#' comments and blank lines ignored).

set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

main() {
    local list="${INSTALLER_ROOT}/config/packages.txt"
    [[ -r "$list" ]] || die "package list not found: $list"

    # Parse the list (strip comments and blank lines)
    local pkgs=()
    while IFS= read -r line; do
        # Strip comments and trim whitespace
        line="${line%%#*}"
        line="${line//[[:space:]]/}"
        [[ -z "$line" ]] && continue
        pkgs+=("$line")
    done < "$list"

    if (( ${#pkgs[@]} == 0 )); then
        log_warn "package list is empty — nothing to install"
        return 0
    fi

    log_info "installing ${#pkgs[@]} packages from ${list}"
    run pacman -Syu --noconfirm --needed "${pkgs[@]}"
    log_info "package installation complete"
}

main "$@"
