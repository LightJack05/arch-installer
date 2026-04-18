#!/bin/bash
# stage 90-services — enable services listed in config/services.txt.
#
# Each line is a unit name (e.g. NetworkManager.service, ly@tty2.service).
# Failures are logged as warnings and skipped — some units (e.g. getty
# overrides like ly@tty2) have no service file but enable successfully via
# systemctl's template handling, while others may simply be absent.

set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

main() {
    local list="${INSTALLER_ROOT}/config/services.txt"
    [[ -r "${list}" ]] || die "services list not found: ${list}"

    log_info "enabling services from ${list}"

    while IFS= read -r unit; do
        # Strip comments and trim whitespace
        unit="${unit%%#*}"
        unit="${unit//[[:space:]]/}"
        [[ -z "$unit" ]] && continue

        systemctl enable "$unit" || log_warn "failed to enable unit: $unit"
    done < "${list}"

    log_info "service enablement complete"
}

main "$@"
