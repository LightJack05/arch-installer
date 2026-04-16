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
    [[ -r "${list}" ]] || die "package list not found: ${list}"

    # TODO:
    #   local pkgs
    #   mapfile -t pkgs < <(grep -v '^\s*\(#\|$\)' "$list")
    #   pacman -Syu --noconfirm --needed "${pkgs[@]}"
    :
}

main "$@"
