#!/bin/bash
# lib/tui.sh — gum-based TUI wrappers.
#
# Requires gum (charmbracelet/gum) — installed on the live ISO by iso-bootstrap.
# Every value-returning function stores its result in the global _TUI_RESULT
# variable instead of printing to stdout, to avoid stdout-contamination
# in nested subshells. Callers read _TUI_RESULT after the call returns.
# tui_confirm returns 0/1 exit codes and does not set _TUI_RESULT.
#
# Functions:
#   tui_message      <title> <body>
#   tui_input        <title> <prompt> [default]        — sets _TUI_RESULT
#   tui_password     <title> <prompt>                  — sets _TUI_RESULT; never echoes
#   tui_choose       <title> <prompt> <choice...>      — sets _TUI_RESULT; single-select
#   tui_checklist    <title> <prompt> <label1> <on|off> [...]  — sets _TUI_RESULT; multi-select
#   tui_confirm      <title> <prompt> [default]        — yes/no (return code only)
#   tui_step         <n> <total> <label>               — renders the step strip
#
# Validation helpers:
#   tui_input_validated <title> <prompt> <default> <validator_fn>  — sets _TUI_RESULT

set -Eeuo pipefail

# Global result variable — set by every value-returning function.
_TUI_RESULT=""

# ==============================================================================
# tui_message <title> <body>
# Display an informational message the user must dismiss.
# ==============================================================================
tui_message() {
    local title="$1"
    local body="$2"

    gum style \
        --border rounded \
        --padding "1 2" \
        --margin "1" \
        "${title}" "$(printf '%b' "${body}")" >&2
    read -rsp "(press enter to continue)" </dev/tty
    printf '\n' >&2
}

# ==============================================================================
# tui_input <title> <prompt> [default]
# Prompt for a text value. Stores result in _TUI_RESULT.
# ==============================================================================
tui_input() {
    local title="$1"
    local prompt="$2"
    local default="${3:-}"

    _TUI_RESULT=$(gum input \
        --header="${title}" \
        --prompt="${prompt}: " \
        --value="${default}" \
        --placeholder="${default}")
}

# ==============================================================================
# tui_password <title> <prompt>
# Prompt for a password (not echoed). Stores result in _TUI_RESULT.
# ==============================================================================
tui_password() {
    local title="$1"
    local prompt="$2"

    _TUI_RESULT=$(gum input \
        --header="${title}" \
        --prompt="${prompt}: " \
        --password)
}

# ==============================================================================
# tui_choose <title> <prompt> <choice...>
# Single-select from choices. Stores result in _TUI_RESULT.
# ==============================================================================
tui_choose() {
    local title="$1"
    local prompt="$2"
    shift 2

    _TUI_RESULT=$(gum choose --header="${title}" "$@")
}

# ==============================================================================
# tui_checklist <title> <prompt> <tag1> <on|off> [<tag2> <on|off> ...]
# Multi-select. Stores newline-separated selected tags in _TUI_RESULT.
# (States are accepted for API compatibility but gum shows all items unselected.)
# ==============================================================================
tui_checklist() {
    local title="$1"
    local prompt="$2"
    shift 2

    local tags=()
    while (( $# >= 2 )); do
        tags+=("$1")
        shift 2
    done

    _TUI_RESULT=$(gum choose --no-limit --header="${title}" "${tags[@]}")
}

# ==============================================================================
# tui_confirm <title> <prompt> [default]
# Yes/No. Return 0 for yes, 1 for no.
# Optional third argument sets the default: "yes" (default) or "no".
# ==============================================================================
tui_confirm() {
    local title="$1"
    local prompt="$2"
    local default="${3:-yes}"

    if [[ "${default}" == "no" ]]; then
        gum confirm --default=false "${prompt}"
    else
        gum confirm "${prompt}"
    fi
}

# ==============================================================================
# tui_step <n> <total> <label>
# Print a step indicator line to stderr.
# ==============================================================================
tui_step() {
    local n="$1"
    local total="$2"
    local label="$3"

    gum style --foreground 212 "$(printf '\n[%s/%s]  %s' "${n}" "${total}" "${label}")" >&2
}

# ==============================================================================
# tui_input_validated <title> <prompt> <default> <validator_fn>
# Loop calling tui_input until validator_fn "$value" returns 0.
# ==============================================================================
tui_input_validated() {
    local title="$1"
    local prompt="$2"
    local default="$3"
    local validator_fn="$4"

    local value
    while true; do
        tui_input "${title}" "${prompt}" "${default}"
        value="${_TUI_RESULT}"
        if "${validator_fn}" "${value}"; then
            _TUI_RESULT="${value}"
            return 0
        else
            tui_message "Invalid Input" "The value '${value}' is not valid. Please try again."
        fi
    done
}
