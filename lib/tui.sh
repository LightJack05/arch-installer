#!/bin/bash
# lib/tui.sh — backend-agnostic TUI wrappers.
#
# Selects a backend at source time (gum > whiptail > plain read). Every
# function returns the selected value on stdout and exits 1 on cancel.
#
# Functions (identical signatures across backends):
#   tui_message      <title> <body>
#   tui_input        <title> <prompt> [default]
#   tui_password     <title> <prompt>                  — never echoes
#   tui_choose       <title> <prompt> <choice...>      — single-select
#   tui_checklist    <title> <prompt> <label1> <on|off> [...]  — multi-select
#   tui_confirm      <title> <prompt>                  — yes/no
#   tui_step         <n> <total> <label>               — renders the step strip
#
# Validation helpers (optional, used by stage 10):
#   tui_input_validated <title> <prompt> <default> <validator_fn>

set -Eeuo pipefail

# Backend detection — override with INSTALLER_TUI=whiptail|read|gum.
tui_detect_backend() {
    if [[ -n "${INSTALLER_TUI:-}" ]]; then
        printf '%s' "${INSTALLER_TUI}"
        return
    fi
    if command -v gum >/dev/null 2>&1; then
        printf 'gum'
    elif command -v whiptail >/dev/null 2>&1; then
        printf 'whiptail'
    else
        printf 'read'
    fi
}

INSTALLER_TUI_BACKEND="$(tui_detect_backend)"
export INSTALLER_TUI_BACKEND

# TODO: per-backend implementations for each tui_* function below.
# Each must write the answer to stdout and return non-zero on ESC/cancel.

tui_message()    { : "TODO: $*"; }
tui_input()      { : "TODO: $*"; }
tui_password()   { : "TODO: $*"; }
tui_choose()     { : "TODO: $*"; }
tui_checklist()  { : "TODO: $*"; }
tui_confirm()    { : "TODO: $*"; }
tui_step()       { : "TODO: $*"; }
tui_input_validated() { : "TODO: $*"; }
