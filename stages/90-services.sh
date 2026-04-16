#!/bin/bash
# stage 90-services — enable services listed in config/services.txt.
#
# Each line is a unit name (e.g. NetworkManager.service, ly@tty2.service).
# Missing units are logged as warnings, not errors — a service may depend on
# an optional package the user excluded.

set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

main() {
    local list="${INSTALLER_ROOT}/config/services.txt"
    [[ -r "${list}" ]] || die "services list not found: ${list}"

    # TODO:
    #   while IFS= read -r unit; do
    #     [[ -z "$unit" || "$unit" =~ ^# ]] && continue
    #     if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
    #       systemctl enable "$unit"
    #     else
    #       log_warn "unit not found, skipping: $unit"
    #     fi
    #   done < "$list"
    :
}

main "$@"
