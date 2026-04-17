#!/bin/bash
# stage 10-tui — single interactive phase. Every subsequent stage reads
# answers from /tmp/installer.env and never prompts.
#
# Screens (see PLAN.md §4 TUI answer set for defaults):
#   1.  splash
#   2.  live keyboard layout (applied immediately via `loadkeys`)
#   3.  install mode A/B/C/D
#   4.  manual mount dir (D only)
#   5.  target disk (A/B/C)
#   6.  filesystem ext4|btrfs (A/B/C)
#   7.  hostname
#   8.  timezone
#   9.  locale
#  10.  console keymap
#  11.  username
#  12.  user full name (optional)
#  13.  user shell
#  14.  root password (twice, empty allowed → root login disabled)
#  15.  user password (twice, required)
#  16.  LUKS passphrase (twice)                  — B+C
#  17.  TPM2 PIN (twice) + TPM-wipe confirmation — C
#  18.  dotfiles opt-out (default on)
#        └─ if on: run `gh auth login`, capture token → /tmp/installer.ghtoken (0600)
#  19.  secure boot opt-in (warn if not in Setup Mode)
#  20.  surface kernel opt-in
#  21.  additional optional scripts (checklist from optional/)
#  22.  summary recap (go back to any screen)
#  23.  final destructive confirmation (only before scheme A/B/C wipes)
#
# Swapfile and zRAM sizes are auto-computed from RAM and stored without
# prompting; see config/defaults.env and compute_swap_defaults below.
#
# Passwords are hashed via `openssl passwd -6` before cfg_set; plaintext
# never persists. LUKS passphrase and TPM PIN are written in plaintext
# because stage 20 must feed them directly to cryptsetup/tpm2 tooling;
# /tmp/installer.env is mode 0600.
# GH token lives in its own 0600 file, not the env file.

set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=../lib/config.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/config.sh"
# shellcheck source=../lib/tui.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/tui.sh"
# Load defaults into environment
# shellcheck source=../config/defaults.env
source "$(dirname -- "${BASH_SOURCE[0]}")/../config/defaults.env"

readonly TOTAL_STEPS=23

# ==============================================================================
# Helper: compute_swap_defaults
# Reads /proc/meminfo MemTotal, sets SWAPFILE_SIZE_MIB and ZRAM_SIZE_MIB.
# Does not prompt — values go directly to installer.env.
# ==============================================================================
compute_swap_defaults() {
    local ram_kib ram_mib
    ram_kib=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
    ram_mib=$(( ram_kib / 1024 ))

    # ceil(1.5 * RAM_MiB) = (RAM_MiB * 3 + 1) / 2
    SWAPFILE_SIZE_MIB=$(( (ram_mib * 3 + 1) / 2 ))

    # min(RAM_MiB / 2, 8192)
    local zram_candidate=$(( ram_mib / 2 ))
    if (( zram_candidate > 8192 )); then
        ZRAM_SIZE_MIB=8192
    else
        ZRAM_SIZE_MIB=${zram_candidate}
    fi

    export SWAPFILE_SIZE_MIB ZRAM_SIZE_MIB
}

# ==============================================================================
# Helper: hash_password
# Reads plaintext from stdin, writes openssl passwd -6 hash to stdout.
# Using stdin avoids the plaintext appearing in the process argument list.
# ==============================================================================
hash_password() {
    # Plaintext is piped in on stdin to avoid it appearing in the process list.
    openssl passwd -6 -stdin
}

# ==============================================================================
# Helper: prompt_password_twice <title> <prompt> [allow_empty]
# Prompt twice, compare, loop on mismatch. Returns plaintext to stdout.
# allow_empty=1: empty string is accepted if both entries are empty.
# ==============================================================================
prompt_password_twice() {
    local title="$1"
    local prompt="$2"
    local allow_empty="${3:-0}"
    _TUI_RESULT=""

    while true; do
        local pw1 pw2
        tui_password "${title}" "${prompt}"
        pw1="${_TUI_RESULT}"
        tui_password "${title}" "Confirm ${prompt}"
        pw2="${_TUI_RESULT}"

        if [[ "${pw1}" != "${pw2}" ]]; then
            tui_message "Mismatch" "Passwords do not match. Please try again."
            continue
        fi

        if [[ -z "${pw1}" && "${allow_empty}" != "1" ]]; then
            tui_message "Empty" "Password cannot be empty. Please try again."
            continue
        fi

        _TUI_RESULT="${pw1}"
        return 0
    done
}

# ==============================================================================
# main
# ==============================================================================
main() {
    cfg_init
    compute_swap_defaults
    cfg_set SWAPFILE_SIZE_MIB "${SWAPFILE_SIZE_MIB}"
    cfg_set ZRAM_SIZE_MIB "${ZRAM_SIZE_MIB}"
    log_info "starting TUI (backend: ${INSTALLER_TUI_BACKEND})"

    # --------------------------------------------------------------------------
    # Step 1/23: Splash
    # --------------------------------------------------------------------------
    tui_step 1 "${TOTAL_STEPS}" "Welcome"

    if command -v figlet >/dev/null 2>&1 && command -v lolcat >/dev/null 2>&1; then
        figlet "Arch Installer" | lolcat
        tui_message "Arch Installer" "Opinionated Arch Linux installer\nPress Enter at each prompt to accept the default."
    else
        tui_message "Arch Installer" "Opinionated Arch Linux installer\nPress Enter at each prompt to accept the default."
    fi

    # --------------------------------------------------------------------------
    # Step 2/23: Live keyboard layout
    # --------------------------------------------------------------------------
    tui_step 2 "${TOTAL_STEPS}" "Live Keyboard Layout"

    local ans
    tui_input "Keyboard Layout" "Live keyboard layout (loadkeys)" "${KEYMAP:-us}"
    ans="${_TUI_RESULT}"
    loadkeys "${ans}" 2>/dev/null || log_warn "loadkeys failed for '${ans}' — layout may not match"
    cfg_set KEYMAP "${ans}"

    # --------------------------------------------------------------------------
    # Step 3/23: Install mode
    # --------------------------------------------------------------------------
    tui_step 3 "${TOTAL_STEPS}" "Install Mode"

    tui_choose "Install Mode" "Partitioning scheme" \
        "A - Bare (ESP + root)" \
        "B - LUKS passphrase" \
        "C - LUKS + TPM2-PIN" \
        "D - Manual (already mounted)"
    ans="${_TUI_RESULT}"
    local INSTALL_MODE="${ans:0:1}"
    cfg_set INSTALL_MODE "${INSTALL_MODE}"

    # --------------------------------------------------------------------------
    # Step 4/23: Manual mount dir (mode D only)
    # --------------------------------------------------------------------------
    local MANUAL_MOUNT="/mnt"
    if [[ "${INSTALL_MODE}" == "D" ]]; then
        tui_step 4 "${TOTAL_STEPS}" "Manual Mount Directory"
        while true; do
            tui_input "Manual Mode" "Mount root directory" "/mnt"
            ans="${_TUI_RESULT}"
            if [[ -d "${ans}" ]]; then
                MANUAL_MOUNT="${ans}"
                cfg_set MANUAL_MOUNT "${MANUAL_MOUNT}"
                break
            else
                tui_message "Invalid Path" "Directory '${ans}' does not exist. Please enter a valid mount point."
            fi
        done
    else
        cfg_set MANUAL_MOUNT "${MANUAL_MOUNT}"
    fi

    # --------------------------------------------------------------------------
    # Step 5/23: Target disk (modes A/B/C)
    # --------------------------------------------------------------------------
    local TARGET_DISK=""
    if [[ "${INSTALL_MODE}" != "D" ]]; then
        tui_step 5 "${TOTAL_STEPS}" "Target Disk"

        # Build disk list from lsblk: show non-removable first
        local disk_items_fixed=()
        local disk_items_removable=()

        while IFS= read -r line; do
            local name size model type rm
            name=$(printf '%s' "${line}" | awk '{print $1}')
            size=$(printf '%s' "${line}" | awk '{print $2}')
            model=$(printf '%s' "${line}" | awk '{for(i=3;i<=NF-2;i++) printf $i " "; print ""}' | xargs)
            type=$(printf '%s' "${line}" | awk '{print $(NF-1)}')
            rm=$(printf '%s' "${line}" | awk '{print $NF}')

            [[ "${type}" != "disk" ]] && continue

            local label="/dev/${name}  ${size}"
            [[ -n "${model}" ]] && label="${label}  ${model}"
            [[ "${rm}" == "1" ]] && label="${label}  [removable]"

            if [[ "${rm}" == "0" ]]; then
                disk_items_fixed+=("${label}")
            else
                disk_items_removable+=("${label}")
            fi
        done < <(lsblk -ndo NAME,SIZE,MODEL,TYPE,RM)

        # Merge: non-removable first
        local disk_items=()
        disk_items+=("${disk_items_fixed[@]+"${disk_items_fixed[@]}"}")
        disk_items+=("${disk_items_removable[@]+"${disk_items_removable[@]}"}")

        if (( ${#disk_items[@]} == 0 )); then
            die "No disks found. Cannot continue."
        fi

        tui_choose "Target Disk" "Select installation disk" "${disk_items[@]}"
        ans="${_TUI_RESULT}"

        # Extract /dev/NAME from the chosen line
        local disk_dev
        disk_dev=$(printf '%s' "${ans}" | awk '{print $1}')
        TARGET_DISK="${disk_dev}"
        cfg_set TARGET_DISK "${TARGET_DISK}"
    fi

    # --------------------------------------------------------------------------
    # Step 6/23: Filesystem (modes A/B/C)
    # --------------------------------------------------------------------------
    if [[ "${INSTALL_MODE}" != "D" ]]; then
        tui_step 6 "${TOTAL_STEPS}" "Filesystem"
        tui_choose "Filesystem" "Root filesystem" "ext4" "btrfs"
        ans="${_TUI_RESULT}"
        cfg_set FILESYSTEM "${ans}"
    fi

    # --------------------------------------------------------------------------
    # Step 7/23: Hostname
    # --------------------------------------------------------------------------
    tui_step 7 "${TOTAL_STEPS}" "Hostname"

    validate_hostname() { [[ "$1" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]]; }
    tui_input_validated "Hostname" \
        "Hostname (lowercase letters, digits, hyphens; 1-63 chars)" \
        "${HOSTNAME:-archlinux}" \
        validate_hostname
    ans="${_TUI_RESULT}"
    cfg_set HOSTNAME "${ans}"

    # --------------------------------------------------------------------------
    # Step 8/23: Timezone
    # --------------------------------------------------------------------------
    tui_step 8 "${TOTAL_STEPS}" "Timezone"

    validate_tz() { [[ -f "/usr/share/zoneinfo/$1" ]]; }
    tui_input_validated "Timezone" \
        "Timezone (must exist under /usr/share/zoneinfo)" \
        "${TIMEZONE:-Europe/Berlin}" \
        validate_tz
    ans="${_TUI_RESULT}"
    cfg_set TIMEZONE "${ans}"

    # --------------------------------------------------------------------------
    # Step 9/23: Locale
    # --------------------------------------------------------------------------
    tui_step 9 "${TOTAL_STEPS}" "Locale"

    validate_locale() {
        [[ -f "/usr/share/i18n/locales/$1" ]] || \
        grep -q "^$1 " /usr/share/i18n/SUPPORTED 2>/dev/null
    }
    tui_input_validated "Locale" \
        "Locale (e.g. en_US.UTF-8)" \
        "${LOCALE:-en_US.UTF-8}" \
        validate_locale
    ans="${_TUI_RESULT}"
    cfg_set LOCALE "${ans}"

    # --------------------------------------------------------------------------
    # Step 10/23: Console keymap
    # --------------------------------------------------------------------------
    tui_step 10 "${TOTAL_STEPS}" "Console Keymap"

    tui_input "Console Keymap" \
        "Installed system console keymap" \
        "${KEYMAP:-us}"
    ans="${_TUI_RESULT}"
    cfg_set KEYMAP "${ans}"

    # --------------------------------------------------------------------------
    # Step 11/23: Username
    # --------------------------------------------------------------------------
    tui_step 11 "${TOTAL_STEPS}" "Username"

    # Spec: [a-z_][a-z0-9_-]{0,31} (lowercase only; max 32 chars total)
    validate_user() { [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; }
    tui_input_validated "Username" \
        "Primary username (lowercase letters/digits/underscore/hyphen)" \
        "${USERNAME:-lightjack05}" \
        validate_user
    ans="${_TUI_RESULT}"
    local USERNAME="${ans}"
    cfg_set USERNAME "${USERNAME}"

    # --------------------------------------------------------------------------
    # Step 12/23: Full name (optional)
    # --------------------------------------------------------------------------
    tui_step 12 "${TOTAL_STEPS}" "Full Name"

    tui_input "Full Name" \
        "User's full name (optional — press Enter to skip)" \
        "${USER_FULLNAME:-}"
    ans="${_TUI_RESULT}"
    cfg_set USER_FULLNAME "${ans}"

    # --------------------------------------------------------------------------
    # Step 13/23: Shell
    # --------------------------------------------------------------------------
    tui_step 13 "${TOTAL_STEPS}" "User Shell"

    tui_input "Shell" \
        "User shell (full path)" \
        "${USER_SHELL:-/usr/bin/zsh}"
    ans="${_TUI_RESULT}"
    cfg_set USER_SHELL "${ans}"

    # --------------------------------------------------------------------------
    # Step 14/23: Root password (allow empty → disable root)
    # --------------------------------------------------------------------------
    tui_step 14 "${TOTAL_STEPS}" "Root Password"

    tui_message "Root Password" \
        "Leave empty to disable root login (recommended).\nIf set, must be entered twice."
    local pw
    prompt_password_twice "Root Password" "Root password" 1
    pw="${_TUI_RESULT}"
    if [[ -n "${pw}" ]]; then
        local root_hash
        root_hash=$(printf '%s' "${pw}" | hash_password)
        cfg_set ROOT_PASSWORD_HASH "${root_hash}"
        unset root_hash
    fi
    unset pw

    # --------------------------------------------------------------------------
    # Step 15/23: User password (required)
    # --------------------------------------------------------------------------
    tui_step 15 "${TOTAL_STEPS}" "User Password"

    local user_pw
    while true; do
        prompt_password_twice "User Password" "Password for ${USERNAME}" 0
        user_pw="${_TUI_RESULT}"
        [[ -n "${user_pw}" ]] && break
        tui_message "Error" "User password cannot be empty."
    done
    local user_hash
    user_hash=$(printf '%s' "${user_pw}" | hash_password)
    cfg_set USER_PASSWORD_HASH "${user_hash}"
    unset user_pw user_hash

    # --------------------------------------------------------------------------
    # Step 16/23: LUKS passphrase (modes B + C)
    # --------------------------------------------------------------------------
    if [[ "${INSTALL_MODE}" == "B" || "${INSTALL_MODE}" == "C" ]]; then
        tui_step 16 "${TOTAL_STEPS}" "LUKS Passphrase"
        tui_message "LUKS Passphrase" \
            "This passphrase is the disk encryption recovery method.\nStore it safely — losing it means losing all data on the disk."
        local luks_pp
        while true; do
            prompt_password_twice "LUKS Passphrase" "Encryption passphrase" 0
            luks_pp="${_TUI_RESULT}"
            [[ -n "${luks_pp}" ]] && break
            tui_message "Error" "LUKS passphrase cannot be empty."
        done
        cfg_set LUKS_PASSPHRASE "${luks_pp}"
        unset luks_pp
    fi

    # --------------------------------------------------------------------------
    # Step 17/23: TPM2 PIN (mode C only)
    # --------------------------------------------------------------------------
    if [[ "${INSTALL_MODE}" == "C" ]]; then
        tui_step 17 "${TOTAL_STEPS}" "TPM2 PIN"
        tui_message "TPM2 PIN" \
            "The TPM2 chip will be wiped and re-enrolled.\nA PIN is required on every boot (the LUKS passphrase remains as recovery)."
        local tpm_pin
        while true; do
            prompt_password_twice "TPM2 PIN" "TPM2 PIN" 0
            tpm_pin="${_TUI_RESULT}"
            [[ -n "${tpm_pin}" ]] && break
            tui_message "Error" "TPM2 PIN cannot be empty."
        done
        cfg_set TPM_PIN "${tpm_pin}"
        unset tpm_pin
    fi

    # --------------------------------------------------------------------------
    # Step 18/23: Dotfiles (default on)
    # --------------------------------------------------------------------------
    tui_step 18 "${TOTAL_STEPS}" "Dotfiles"

    if tui_confirm "Dotfiles" "Set up dotfiles automatically? (gh auth login will run now — default: yes)"; then
        cfg_set DOTFILES_ENABLED 1
        log_info "running gh auth login..."
        if ! gh auth login </dev/tty >/dev/tty 2>/dev/tty; then
            tui_message "GitHub Auth Failed" \
                "gh auth login did not complete successfully.\nDotfiles setup will be skipped."
            cfg_set DOTFILES_ENABLED 0
        else
            if gh auth token > "${INSTALLER_GH_TOKEN_FILE}" 2>/dev/null; then
                chmod 0600 "${INSTALLER_GH_TOKEN_FILE}"
            else
                tui_message "Token Error" \
                    "Could not retrieve GitHub token. Dotfiles setup will be skipped."
                cfg_set DOTFILES_ENABLED 0
            fi
        fi
    else
        cfg_set DOTFILES_ENABLED 0
    fi

    # --------------------------------------------------------------------------
    # Step 19/23: Secure Boot (default off)
    # --------------------------------------------------------------------------
    tui_step 19 "${TOTAL_STEPS}" "Secure Boot"

    local sbctl_st
    sbctl_st=$(sbctl status 2>&1 || true)
    tui_message "Secure Boot Status" "${sbctl_st}"
    if tui_confirm "Secure Boot" "Enable Secure Boot? (requires firmware in Setup Mode — default: no)"; then
        cfg_set SECURE_BOOT 1
    else
        cfg_set SECURE_BOOT 0
    fi

    # --------------------------------------------------------------------------
    # Step 20/23: Surface kernel (default off)
    # --------------------------------------------------------------------------
    tui_step 20 "${TOTAL_STEPS}" "Surface Kernel"

    if tui_confirm "Surface Kernel" "Install linux-surface kernel? (for Microsoft Surface devices — default: no)"; then
        cfg_set SURFACE_KERNEL 1
    else
        cfg_set SURFACE_KERNEL 0
    fi

    # --------------------------------------------------------------------------
    # Step 21/23: Additional optional scripts
    # --------------------------------------------------------------------------
    tui_step 21 "${TOTAL_STEPS}" "Optional Scripts"

    local optional_dir
    optional_dir="$(dirname -- "${BASH_SOURCE[0]}")/../optional"

    # Collect optional scripts, excluding the ones handled by TUI steps above
    local optional_tags=()
    local optional_states=()
    if [[ -d "${optional_dir}" ]]; then
        while IFS= read -r -d '' script; do
            local basename_script
            basename_script="$(basename "${script}")"
            # Skip scripts already managed by dedicated TUI steps
            if [[ "${basename_script}" == "secure-boot.sh" || \
                  "${basename_script}" == "surface-kernel.sh" ]]; then
                continue
            fi
            optional_tags+=("${basename_script}")
            optional_states+=("off")
        done < <(find "${optional_dir}" -maxdepth 1 -name "*.sh" -print0 | sort -z)
    fi

    if (( ${#optional_tags[@]} > 0 )); then
        local checklist_args=()
        local i
        for i in "${!optional_tags[@]}"; do
            checklist_args+=("${optional_tags[$i]}" "${optional_states[$i]}")
        done
        local selected_opts
        tui_checklist "Optional Scripts" \
            "Select additional optional scripts to run (space to toggle, enter to confirm)" \
            "${checklist_args[@]}"
        selected_opts="${_TUI_RESULT}"
        cfg_set OPTIONAL_SCRIPTS "${selected_opts}"
    else
        cfg_set OPTIONAL_SCRIPTS ""
    fi

    # --------------------------------------------------------------------------
    # Step 22/23: Summary recap
    # --------------------------------------------------------------------------
    tui_step 22 "${TOTAL_STEPS}" "Summary"

    # Reload all persisted values into the current shell
    cfg_load

    # Build a human-readable summary table
    local summary
    summary="$(printf '%-28s %s\n' "Setting" "Value")"
    summary="${summary}"$'\n'"$(printf '%-28s %s\n' "-------" "-----")"

    local key val display_val
    while IFS='=' read -r key val; do
        [[ -z "${key}" || "${key}" =~ ^# ]] && continue
        # Strip surrounding single-quotes added by cfg_set
        val="${val#\'}"
        val="${val%\'}"
        # Mask secrets; never show hashes or passphrases
        case "${key}" in
            ROOT_PASSWORD_HASH|USER_PASSWORD_HASH)
                display_val="•••"
                ;;
            LUKS_PASSPHRASE|TPM_PIN)
                display_val="•••"
                ;;
            *)
                display_val="${val}"
                ;;
        esac
        summary="${summary}"$'\n'"$(printf '%-28s %s' "${key}" "${display_val}")"
    done < "${INSTALLER_ENV}"

    tui_message "Installation Summary" "${summary}"

    if ! tui_confirm "Summary" "Proceed with these settings? (no = abort)"; then
        tui_message "Aborted" \
            "Installation cancelled at summary.\nRe-run the installer to start over."
        die "Aborted by user at summary."
    fi

    # --------------------------------------------------------------------------
    # Step 23/23: Final destructive confirmation (skip for mode D)
    # --------------------------------------------------------------------------
    tui_step 23 "${TOTAL_STEPS}" "Final Confirmation"

    if [[ "${INSTALL_MODE}" != "D" ]]; then
        local disk_info
        disk_info=$(lsblk -o NAME,SIZE,MODEL "${TARGET_DISK}" 2>&1 || true)
        tui_message "WARNING — POINT OF NO RETURN" \
            "The following disk will be COMPLETELY AND IRREVERSIBLY ERASED:\n\n${disk_info}\n\nThis is the last chance to abort safely."

        local typed expected
        expected=$(basename "${TARGET_DISK}")
        while true; do
            tui_input "Final Confirmation" \
                "Type the device name (e.g. ${expected}) to confirm erasure — or leave empty to abort" \
                ""
            typed="${_TUI_RESULT}"
            if [[ -z "${typed}" ]]; then
                die "Confirmation skipped. Aborting for safety."
            elif [[ "${typed}" == "${expected}" ]]; then
                break
            else
                tui_message "Mismatch" \
                    "You typed '${typed}' but the disk is '${expected}'. Try again or leave empty to abort."
            fi
        done
    fi

    log_info "TUI complete — all answers saved to ${INSTALLER_ENV}"
}

main "$@"
