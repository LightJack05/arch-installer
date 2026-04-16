#!/bin/bash
# lib/common.sh — shared helpers sourced by every stage and lib.
#
# Provides:
#   log_info / log_warn / log_error   — colored, timestamped logging to stderr + log file
#   die <msg>                         — log error and exit 1
#   run <cmd...>                      — log the command, execute, propagate exit
#   run_quiet <cmd...>                — execute without logging the command (for secrets)
#   confirm <prompt>                  — yes/no (used only by stage 10 and ONE pre-destructive confirmation)
#   require_root                      — abort unless EUID=0
#   on_error                          — ERR trap body; prints stage+line+cmd+log path
#
# Always sourced — never executed directly.

if [[ "${__INSTALLER_COMMON_SOURCED:-0}" == "1" ]]; then
    return 0
fi
readonly __INSTALLER_COMMON_SOURCED=1

# --- Colors (disabled if stdout is not a tty) -------------------------------
if [[ -t 2 ]]; then
    readonly C_RESET=$'\033[0m'
    readonly C_DIM=$'\033[2m'
    readonly C_RED=$'\033[31m'
    readonly C_GREEN=$'\033[32m'
    readonly C_YELLOW=$'\033[33m'
    readonly C_BLUE=$'\033[34m'
    readonly C_BOLD=$'\033[1m'
else
    readonly C_RESET= C_DIM= C_RED= C_GREEN= C_YELLOW= C_BLUE= C_BOLD=
fi

# --- Log file --------------------------------------------------------------
# Live ISO: /var/log/installer.log. Once /mnt/var/log exists, stage 40 will
# copy/symlink the log so chroot stages continue writing to the same file.
INSTALLER_LOG="${INSTALLER_LOG:-/var/log/installer.log}"

_log() {
    local level="$1" color="$2"
    shift 2
    local ts
    ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf '%s%s %-5s%s %s\n' "${color}" "${ts}" "${level}" "${C_RESET}" "$*" >&2
    printf '%s %-5s %s\n' "${ts}" "${level}" "$*" >> "${INSTALLER_LOG}" 2>/dev/null || true
}

log_info()  { _log INFO  "${C_BLUE}"   "$@"; }
log_warn()  { _log WARN  "${C_YELLOW}" "$@"; }
log_error() { _log ERROR "${C_RED}"    "$@"; }

die() {
    log_error "$*"
    exit 1
}

# run <cmd> [args...] — logs the full command, then executes.
# Use run_quiet for anything that takes a secret on stdin or as an arg.
run() {
    log_info "\$ $*"
    "$@"
}

run_quiet() {
    "$@"
}

confirm() {
    # confirm <prompt> — returns 0 on yes, 1 on no. Plain read; not for use
    # inside the TUI layer (tui.sh has its own confirm wrapper).
    local prompt="${1:-Continue?}"
    local ans
    read -rp "${prompt} [y/N] " ans </dev/tty
    [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

require_root() {
    [[ "${EUID}" -eq 0 ]] || die "must run as root"
}

# ERR trap — installed by every script that sources common.sh via setup_traps.
on_error() {
    local exit_code=$?
    local line="${1:-?}"
    local cmd="${BASH_COMMAND:-?}"
    log_error "failed: line ${line}: ${cmd} (exit ${exit_code})"
    log_error "log: ${INSTALLER_LOG}"
    exit "${exit_code}"
}

setup_traps() {
    trap 'on_error "${LINENO}"' ERR
}

# Auto-wire the trap for any script that sources this file.
setup_traps

# Honor INSTALLER_DEBUG=1 for xtrace.
if [[ "${INSTALLER_DEBUG:-0}" == "1" ]]; then
    set -x
fi

# --- ISO bootstrap stub ----------------------------------------------------
# Pull extra TUI tools into the live ISO. Kept in common.sh so install.sh can
# call it before sourcing anything else.
# TODO: honor the RAM budget check in 00-precheck before pulling extras.
iso_bootstrap_install_deps() {
    [[ "${INSTALLER_IN_CHROOT:-0}" == "1" ]] && return 0
    log_info "bootstrapping ISO tooling (gum, figlet, lolcat)"
    # TODO: pacman -Sy --noconfirm --needed gum figlet lolcat   (budget-aware)
    :
}
