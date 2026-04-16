#!/bin/bash
# lib/config.sh — answer persistence for /tmp/installer.env.
#
# Stage 10 writes every answer via cfg_set; stages ≥20 read via cfg_get.
# Plaintext passwords never touch this file — they're hashed by stage 10
# (openssl passwd -6) and only the hash is persisted.
#
# Always sourced; never executed.

if [[ "${__INSTALLER_CONFIG_SOURCED:-0}" == "1" ]]; then
    return 0
fi
readonly __INSTALLER_CONFIG_SOURCED=1

INSTALLER_ENV="${INSTALLER_ENV:-/tmp/installer.env}"
INSTALLER_GH_TOKEN_FILE="${INSTALLER_GH_TOKEN_FILE:-/tmp/installer.ghtoken}"

cfg_init() {
    # Create the env file with mode 0600 if it doesn't exist.
    if [[ ! -e "${INSTALLER_ENV}" ]]; then
        umask 077
        : > "${INSTALLER_ENV}"
    fi
    # Also load defaults into the current shell (overridden by subsequent cfg_set).
    [[ -r "${INSTALLER_ROOT}/config/defaults.env" ]] && \
        source "${INSTALLER_ROOT}/config/defaults.env"
}

cfg_load() {
    # Source the persisted answers into the current shell.
    [[ -r "${INSTALLER_ENV}" ]] && source "${INSTALLER_ENV}"
}

cfg_set() {
    # cfg_set KEY VALUE — persist a single answer.
    # Values are single-quoted; embedded single quotes are escaped.
    local key="$1" value="${2-}"
    local escaped="${value//\'/\'\\\'\'}"
    # Remove prior occurrence (exact key match at line start).
    if [[ -f "${INSTALLER_ENV}" ]]; then
        sed -i "/^${key}=/d" "${INSTALLER_ENV}"
    fi
    printf "%s='%s'\n" "${key}" "${escaped}" >> "${INSTALLER_ENV}"
    # Also export in current shell.
    export "${key}=${value}"
}

cfg_get() {
    # cfg_get KEY [DEFAULT] — print the value of KEY, or DEFAULT if unset.
    local key="$1" default="${2-}"
    cfg_load
    local val
    val="$(eval printf '%s' "\"\${${key}:-}\"")"
    printf '%s' "${val:-${default}}"
}

cfg_require() {
    # cfg_require KEY [KEY...] — die if any of the listed keys is empty/unset.
    cfg_load
    local missing=()
    local key
    for key in "$@"; do
        local val
        val="$(eval printf '%s' "\"\${${key}:-}\"")"
        [[ -z "${val}" ]] && missing+=("${key}")
    done
    if (( ${#missing[@]} > 0 )); then
        die "missing required config: ${missing[*]}"
    fi
}

cfg_shred() {
    # Shred all files holding secrets. Called by stage 99.
    local f
    for f in "${INSTALLER_ENV}" "${INSTALLER_GH_TOKEN_FILE}" \
             /mnt/root/.installer-ghtoken /root/.installer-ghtoken; do
        [[ -e "${f}" ]] || continue
        shred -u "${f}" 2>/dev/null || rm -f "${f}"
    done
}
