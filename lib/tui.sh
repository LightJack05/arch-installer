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
                "${title}" "${body}"
            # gum style just prints; read a keypress to let the user dismiss
            read -rsp "(press enter to continue)" </dev/tty
            printf '\n' >&2
            ;;
        whiptail)
            whiptail --title "${title}" --msgbox "${body}" 20 70
            ;;
        read|*)
            printf '\n=== %s ===\n%s\n' "${title}" "${body}"
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

    case "${INSTALLER_TUI_BACKEND}" in
        gum)
            gum input \
                --header="${title}" \
                --prompt="${prompt}: " \
                --value="${default}" \
                --placeholder="${default}"
            ;;
        whiptail)
            whiptail --title "${title}" \
                --inputbox "${prompt}" 10 60 "${default}" \
                3>&1 1>&2 2>&3
            ;;
        read|*)
            printf '%s\n%s [%s]: ' "${title}" "${prompt}" "${default}" >&2
            local val
            read -r val </dev/tty
            printf '%s' "${val:-${default}}"
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

    case "${INSTALLER_TUI_BACKEND}" in
        gum)
            gum input \
                --header="${title}" \
                --prompt="${prompt}: " \
                --password
            ;;
        whiptail)
            whiptail --title "${title}" \
                --passwordbox "${prompt}" 10 60 \
                3>&1 1>&2 2>&3
            ;;
        read|*)
            local val
            read -rsp "${prompt}: " val </dev/tty
            printf '\n' >&2
            printf '%s' "${val}"
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

    case "${INSTALLER_TUI_BACKEND}" in
        gum)
            gum choose --header="${title}" "${choices[@]}"
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
            # Output the actual choice text (1-based index)
            printf '%s' "${choices[$((choice_num-1))]}"
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
                    printf '%s' "${choices[$((sel-1))]}"
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

    case "${INSTALLER_TUI_BACKEND}" in
        gum)
            # gum choose --no-limit lets the user select multiple items.
            # We can't pre-check items natively; list all tags so the user picks.
            gum choose --no-limit --header="${title}" "${tags[@]}"
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
            printf '%s' "${result}"
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
            printf '%s' "${selected_items[*]}"
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
        value=$(tui_input "${title}" "${prompt}" "${default}")
        if "${validator_fn}" "${value}"; then
            printf '%s' "${value}"
            return 0
        else
            tui_message "Invalid Input" "The value '${value}' is not valid. Please try again."
        fi
    done
}
