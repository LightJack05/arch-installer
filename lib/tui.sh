#!/bin/bash
# lib/tui.sh — backend-agnostic TUI wrappers.
#
# Selects a backend at source time (gum > whiptail > plain read). Every
# value-returning function stores its result in the global _TUI_RESULT
# variable instead of printing to stdout, to avoid stdout-contamination
# in nested subshells. Callers read _TUI_RESULT after the call returns.
# tui_confirm returns 0/1 exit codes and does not set _TUI_RESULT.
#
# Functions (identical signatures across backends):
#   tui_message      <title> <body>
#   tui_input        <title> <prompt> [default]        — sets _TUI_RESULT
#   tui_password     <title> <prompt>                  — sets _TUI_RESULT; never echoes
#   tui_choose       <title> <prompt> <choice...>      — sets _TUI_RESULT; single-select
#   tui_checklist    <title> <prompt> <label1> <on|off> [...]  — sets _TUI_RESULT; multi-select
#   tui_confirm      <title> <prompt>                  — yes/no (return code only)
#   tui_step         <n> <total> <label>               — renders the step strip
#
# Validation helpers (optional, used by stage 10):
#   tui_input_validated <title> <prompt> <default> <validator_fn>  — sets _TUI_RESULT

set -Eeuo pipefail

# Global result variable — set by every value-returning function.
_TUI_RESULT=""

# Backend detection — override with INSTALLER_TUI=whiptail|read|gum.
tui_detect_backend() {
    if [[ -n "${INSTALLER_TUI:-}" ]]; then
        INSTALLER_TUI_BACKEND="${INSTALLER_TUI}"
        return
    fi
    if command -v gum >/dev/null 2>&1; then
        INSTALLER_TUI_BACKEND='gum'
    elif command -v whiptail >/dev/null 2>&1; then
        INSTALLER_TUI_BACKEND='whiptail'
    else
        INSTALLER_TUI_BACKEND='read'
    fi
}

tui_detect_backend
export INSTALLER_TUI_BACKEND

# ==============================================================================
# tui_message <title> <body>
# Display an informational message the user must dismiss.
# ==============================================================================
tui_message() {
    local title="$1"
    local body="$2"

    case "${INSTALLER_TUI_BACKEND}" in
        gum)
            gum style \
                --border rounded \
                --padding "1 2" \
                --margin "1" \
                "${title}" "${body}" >&2
            # gum style just prints; read a keypress to let the user dismiss
            read -rsp "(press enter to continue)" </dev/tty
            printf '\n' >&2
            ;;
        whiptail)
            whiptail --title "${title}" --msgbox "${body}" 20 70
            ;;
        read|*)
            printf '\n=== %s ===\n%s\n' "${title}" "${body}" >&2
            read -rp "(press enter)" </dev/tty
            ;;
    esac
}

# ==============================================================================
# tui_input <title> <prompt> [default]
# Prompt for a text value. Write selected value to stdout.
# ==============================================================================
tui_input() {
    local title="$1"
    local prompt="$2"
    local default="${3:-}"

    _TUI_RESULT=""

    case "${INSTALLER_TUI_BACKEND}" in
        gum)
            _TUI_RESULT=$(gum input \
                --header="${title}" \
                --prompt="${prompt}: " \
                --value="${default}" \
                --placeholder="${default}")
            ;;
        whiptail)
            _TUI_RESULT=$(whiptail --title "${title}" \
                --inputbox "${prompt}" 10 60 "${default}" \
                3>&1 1>&2 2>&3)
            ;;
        read|*)
            printf '%s\n%s [%s]: ' "${title}" "${prompt}" "${default}" >&2
            local val
            read -r val </dev/tty
            _TUI_RESULT="${val:-${default}}"
            ;;
    esac
}

# ==============================================================================
# tui_password <title> <prompt>
# Prompt for a password (not echoed). Write to stdout.
# ==============================================================================
tui_password() {
    local title="$1"
    local prompt="$2"

    _TUI_RESULT=""

    case "${INSTALLER_TUI_BACKEND}" in
        gum)
            _TUI_RESULT=$(gum input \
                --header="${title}" \
                --prompt="${prompt}: " \
                --password)
            ;;
        whiptail)
            _TUI_RESULT=$(whiptail --title "${title}" \
                --passwordbox "${prompt}" 10 60 \
                3>&1 1>&2 2>&3)
            ;;
        read|*)
            local val
            read -rsp "${prompt}: " val </dev/tty
            printf '\n' >&2
            _TUI_RESULT="${val}"
            ;;
    esac
}

# ==============================================================================
# tui_choose <title> <prompt> <choice...>
# Single-select from choices. Write chosen value to stdout.
# ==============================================================================
tui_choose() {
    local title="$1"
    local prompt="$2"
    shift 2
    local choices=("$@")

    _TUI_RESULT=""

    case "${INSTALLER_TUI_BACKEND}" in
        gum)
            _TUI_RESULT=$(gum choose --header="${title}" "${choices[@]}")
            ;;
        whiptail)
            # Build whiptail --menu items: tag item tag item ...
            local menu_items=()
            local i
            for i in "${!choices[@]}"; do
                menu_items+=("$((i+1))" "${choices[$i]}")
            done
            local choice_num
            choice_num=$(whiptail --title "${title}" \
                --menu "${prompt}" 20 70 10 \
                "${menu_items[@]}" \
                3>&1 1>&2 2>&3)
            # Store the actual choice text (1-based index)
            _TUI_RESULT="${choices[$((choice_num-1))]}"
            ;;
        read|*)
            printf '\n%s\n%s\n' "${title}" "${prompt}" >&2
            local i
            for i in "${!choices[@]}"; do
                printf '  %d) %s\n' "$((i+1))" "${choices[$i]}" >&2
            done
            local sel
            while true; do
                read -rp "Select [1-${#choices[@]}]: " sel </dev/tty
                if [[ "${sel}" =~ ^[0-9]+$ ]] && \
                   (( sel >= 1 && sel <= ${#choices[@]} )); then
                    _TUI_RESULT="${choices[$((sel-1))]}"
                    break
                fi
                printf 'Invalid choice, try again.\n' >&2
            done
            ;;
    esac
}

# ==============================================================================
# tui_checklist <title> <prompt> <tag1> <on|off> [<tag2> <on|off> ...]
# Multi-select. Write space-separated selected tags to stdout.
# ==============================================================================
tui_checklist() {
    local title="$1"
    local prompt="$2"
    shift 2
    # Remaining args are pairs: tag on|off

    # Collect tags and initial states
    local tags=()
    local states=()
    while (( $# >= 2 )); do
        tags+=("$1")
        states+=("$2")
        shift 2
    done

    _TUI_RESULT=""

    case "${INSTALLER_TUI_BACKEND}" in
        gum)
            # gum choose --no-limit lets the user select multiple items.
            # We can't pre-check items natively; list all tags so the user picks.
            _TUI_RESULT=$(gum choose --no-limit --header="${title}" "${tags[@]}")
            ;;
        whiptail)
            # Build checklist items: tag description on|off
            local checklist_items=()
            local i
            for i in "${!tags[@]}"; do
                checklist_items+=("${tags[$i]}" "${tags[$i]}" "${states[$i]}")
            done
            local result
            result=$(whiptail --title "${title}" \
                --checklist "${prompt}" 20 70 10 \
                "${checklist_items[@]}" \
                3>&1 1>&2 2>&3)
            # whiptail returns quoted strings; strip quotes
            # shellcheck disable=SC2001
            result=$(printf '%s' "${result}" | sed 's/"//g')
            _TUI_RESULT="${result}"
            ;;
        read|*)
            printf '\n%s\n%s\n' "${title}" "${prompt}" >&2
            printf 'Enter y/n for each item:\n' >&2
            local selected_items=()
            local i
            for i in "${!tags[@]}"; do
                local default_yn="n"
                [[ "${states[$i]}" == "on" ]] && default_yn="y"
                local ans
                read -rp "  ${tags[$i]} [${default_yn}]: " ans </dev/tty
                ans="${ans:-${default_yn}}"
                if [[ "${ans,,}" == "y" ]]; then
                    selected_items+=("${tags[$i]}")
                fi
            done
            _TUI_RESULT="${selected_items[*]}"
            ;;
    esac
}

# ==============================================================================
# tui_confirm <title> <prompt>
# Yes/No. Return 0 for yes, 1 for no.
# ==============================================================================
tui_confirm() {
    local title="$1"
    local prompt="$2"

    case "${INSTALLER_TUI_BACKEND}" in
        gum)
            gum confirm "${prompt}"
            ;;
        whiptail)
            whiptail --title "${title}" --yesno "${prompt}" 10 60
            ;;
        read|*)
            local ans
            while true; do
                read -rp "${prompt} [y/N]: " ans </dev/tty
                case "${ans,,}" in
                    y|yes) return 0 ;;
                    n|no|"") return 1 ;;
                    *) printf 'Please answer y or n.\n' >&2 ;;
                esac
            done
            ;;
    esac
}

# ==============================================================================
# tui_step <n> <total> <label>
# Print a step indicator line to stderr.
# ==============================================================================
tui_step() {
    local n="$1"
    local total="$2"
    local label="$3"

    if [[ "${INSTALLER_TUI_BACKEND}" == "gum" ]] && command -v gum >/dev/null 2>&1; then
        gum style --foreground 212 "$(printf '\n[%s/%s]  %s' "${n}" "${total}" "${label}")" >&2
    else
        printf '\n[%s/%s]  %s\n' "${n}" "${total}" "${label}" >&2
    fi
}

# ==============================================================================
# tui_input_validated <title> <prompt> <default> <validator_fn>
# Loop calling tui_input until validator_fn "$value" returns 0.
# Returns the valid value on stdout.
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
