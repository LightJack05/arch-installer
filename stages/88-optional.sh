#!/bin/bash
# stage 88-optional — run optional scripts selected in the TUI (stage 10).
#
# OPTIONAL_SCRIPTS holds newline-separated script basenames as produced by
# gum choose --no-limit (e.g. "surface-kernel.sh").  Each script lives under
# ${INSTALLER_ROOT}/optional/ and is executed in the chroot environment.
# Missing or non-executable scripts are warned about but do not abort the run.

set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=../lib/config.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/config.sh"

main() {
    cfg_load

    if [[ -z "${OPTIONAL_SCRIPTS:-}" ]]; then
        log_info "no optional scripts selected — skipping stage 88"
        return 0
    fi

    log_info "running optional scripts"

    local script path
    while IFS= read -r script; do
        # Strip any accidental whitespace / empty lines produced by the TUI.
        script="${script//[[:space:]]/}"
        [[ -z "${script}" ]] && continue

        path="${INSTALLER_ROOT}/optional/${script}"

        if [[ ! -e "${path}" ]]; then
            log_warn "optional script not found, skipping: ${path}"
            continue
        fi

        if [[ ! -x "${path}" ]]; then
            log_warn "optional script is not executable, skipping: ${path}"
            continue
        fi

        log_info "running optional script: ${script}"
        run "${path}"
        log_info "optional script complete: ${script}"
    done <<< "${OPTIONAL_SCRIPTS}"

    log_info "optional scripts complete"
}

main "$@"
