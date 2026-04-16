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
#   7.  swapfile size (default 1.5×RAM MiB)
#   8.  zram size (default min(RAM/2, 8192) MiB)
#   9.  hostname
#  10.  timezone
#  11.  locale
#  12.  console keymap
#  13.  username
#  14.  user full name (optional)
#  15.  user shell
#  16.  root password (twice, empty allowed → root login disabled)
#  17.  user password (twice, required)
#  18.  LUKS passphrase (twice)                  — B+C
#  19.  TPM2 PIN (twice) + TPM-wipe confirmation — C
#  20.  dotfiles opt-out (default on)
#        └─ if on: run `gh auth login`, capture token → /tmp/installer.ghtoken (0600)
#  21.  secure boot opt-in (warn if not in Setup Mode)
#  22.  surface kernel opt-in
#  23.  additional optional scripts (checklist from optional/)
#  24.  summary recap (go back to any screen)
#  25.  final destructive confirmation (only before scheme A/B/C wipes)
#
# Passwords are hashed via `openssl passwd -6` before cfg_set; plaintext
# never persists. GH token lives in its own 0600 file, not the env file.

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

# ==============================================================================
# Helper: compute_swap_defaults
# Reads /proc/meminfo MemTotal, sets SWAPFILE_SIZE_MIB and ZRAM_SIZE_MIB.
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
# Helper: hash_password <plaintext>
# Output openssl passwd -6 hash. Never logs the input.
# ==============================================================================
hash_password() {
    local plaintext="$1"
    run_quiet openssl passwd -6 "${plaintext}"
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

    while true; do
        local pw1 pw2
        pw1=$(tui_password "${title}" "${prompt}")
        pw2=$(tui_password "${title}" "Confirm ${prompt}")

        if [[ "${pw1}" != "${pw2}" ]]; then
            tui_message "Mismatch" "Passwords do not match. Please try again."
            continue
        fi

        if [[ -z "${pw1}" && "${allow_empty}" != "1" ]]; then
            tui_message "Empty" "Password cannot be empty. Please try again."
            continue
        fi

        printf '%s' "${pw1}"
        return 0
    done
}

# ==============================================================================
# main
# ==============================================================================
main() {
    cfg_init
    compute_swap_defaults
    log_info "starting TUI (backend: ${INSTALLER_TUI_BACKEND})"

    # --------------------------------------------------------------------------
    # Step 1/25: Splash
    # --------------------------------------------------------------------------
    tui_step 1 25 "Splash"

    if command -v figlet >/dev/null 2>&1 && command -v lolcat >/dev/null 2>&1; then
        figlet "Arch Installer" | lolcat
    else
        tui_message "Arch Installer" "Opinionated Arch Linux installer\nSee PLAN.md for full details."
    fi

    # --------------------------------------------------------------------------
    # Step 2/25: Live keyboard layout
    # --------------------------------------------------------------------------
    tui_step 2 25 "Live Keyboard Layout"

    local ans
    ans=$(tui_input "Keyboard Layout" "Live keyboard layout (loadkeys)" "${KEYMAP:-us}")
    run loadkeys "${ans}" || log_warn "loadkeys failed for ${ans}"
    cfg_set KEYMAP "${ans}"

    # --------------------------------------------------------------------------
    # Step 3/25: Install mode
    # --------------------------------------------------------------------------
    tui_step 3 25 "Install Mode"

    ans=$(tui_choose "Install Mode" "Partitioning scheme" \
        "A - Bare (ESP + root)" \
        "B - LUKS passphrase" \
        "C - LUKS + TPM2-PIN" \
        "D - Manual (already mounted)")
    local INSTALL_MODE="${ans:0:1}"
    cfg_set INSTALL_MODE "${INSTALL_MODE}"

    # --------------------------------------------------------------------------
    # Step 4/25: Manual mount dir (mode D only)
    # --------------------------------------------------------------------------
    tui_step 4 25 "Manual Mount Directory"

    local MANUAL_MOUNT="/mnt"
    if [[ "${INSTALL_MODE}" == "D" ]]; then
        ans=$(tui_input "Manual Mode" "Mount root directory" "/mnt")
        [[ -d "${ans}" ]] || die "directory not found: ${ans}"
        MANUAL_MOUNT="${ans}"
        cfg_set MANUAL_MOUNT "${MANUAL_MOUNT}"
    fi

    # --------------------------------------------------------------------------
    # Step 5/25: Target disk (modes A/B/C)
    # --------------------------------------------------------------------------
    tui_step 5 25 "Target Disk"

    local TARGET_DISK=""
    if [[ "${INSTALL_MODE}" != "D" ]]; then
        # Build disk list from lsblk: show non-removable first
        local disk_items=()
        local disk_names=()

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
                # non-removable: put first
                disk_items=("${label}" "${disk_items[@]+"${disk_items[@]}"}")
                disk_names=("/dev/${name}" "${disk_names[@]+"${disk_names[@]}"}")
            else
                disk_items+=("${label}")
                disk_names+=("/dev/${name}")
            fi
        done < <(lsblk -ndo NAME,SIZE,MODEL,TYPE,RM)

        if (( ${#disk_items[@]} == 0 )); then
            die "No disks found. Cannot continue."
        fi

        ans=$(tui_choose "Target Disk" "Select installation disk" "${disk_items[@]}")

        # Extract /dev/NAME from the chosen line
        local disk_dev
        disk_dev=$(printf '%s' "${ans}" | awk '{print $1}')
        TARGET_DISK="${disk_dev}"
        cfg_set TARGET_DISK "${TARGET_DISK}"
    fi

    # --------------------------------------------------------------------------
    # Step 6/25: Filesystem (modes A/B/C)
    # --------------------------------------------------------------------------
    tui_step 6 25 "Filesystem"

    if [[ "${INSTALL_MODE}" != "D" ]]; then
        ans=$(tui_choose "Filesystem" "Root filesystem" "ext4" "btrfs")
        cfg_set FILESYSTEM "${ans}"
    fi

    # --------------------------------------------------------------------------
    # Step 7/25: Swapfile size
    # --------------------------------------------------------------------------
    tui_step 7 25 "Swapfile Size"

    validate_positive_int() { [[ "$1" =~ ^[1-9][0-9]*$ ]]; }
    ans=$(tui_input_validated "Swap" \
        "Swapfile size in MiB (1.5×RAM recommended)" \
        "${SWAPFILE_SIZE_MIB}" \
        validate_positive_int)
    cfg_set SWAPFILE_SIZE_MIB "${ans}"

    # --------------------------------------------------------------------------
    # Step 8/25: zRAM size
    # --------------------------------------------------------------------------
    tui_step 8 25 "zRAM Size"

    ans=$(tui_input_validated "zRAM" \
        "zRAM size in MiB" \
        "${ZRAM_SIZE_MIB}" \
        validate_positive_int)
    cfg_set ZRAM_SIZE_MIB "${ans}"

    # --------------------------------------------------------------------------
    # Step 9/25: Hostname
    # --------------------------------------------------------------------------
    tui_step 9 25 "Hostname"

    validate_hostname() { [[ "$1" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]]; }
    ans=$(tui_input_validated "Hostname" "Hostname" "${HOSTNAME:-archlinux}" validate_hostname)
    cfg_set HOSTNAME "${ans}"

    # --------------------------------------------------------------------------
    # Step 10/25: Timezone
    # --------------------------------------------------------------------------
    tui_step 10 25 "Timezone"

    validate_tz() { [[ -f "/usr/share/zoneinfo/$1" ]]; }
    ans=$(tui_input_validated "Timezone" "Timezone" "${TIMEZONE:-Europe/Berlin}" validate_tz)
    cfg_set TIMEZONE "${ans}"

    # --------------------------------------------------------------------------
    # Step 11/25: Locale
    # --------------------------------------------------------------------------
    tui_step 11 25 "Locale"

    validate_locale() {
        [[ -f "/usr/share/i18n/locales/$1" ]] || \
        grep -q "^$1 " /usr/share/i18n/SUPPORTED 2>/dev/null
    }
    ans=$(tui_input_validated "Locale" "Locale" "${LOCALE:-en_US.UTF-8}" validate_locale)
    cfg_set LOCALE "${ans}"

    # --------------------------------------------------------------------------
    # Step 12/25: Console keymap
    # --------------------------------------------------------------------------
    tui_step 12 25 "Console Keymap"

    ans=$(tui_input "Console Keymap" "Console keymap" "${KEYMAP:-us}")
    cfg_set KEYMAP "${ans}"

    # --------------------------------------------------------------------------
    # Step 13/25: Username
    # --------------------------------------------------------------------------
    tui_step 13 25 "Username"

    validate_user() { [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,30}$ ]]; }
    ans=$(tui_input_validated "Username" "Primary username" "${USERNAME:-LightJack05}" validate_user)
    local USERNAME="${ans}"
    cfg_set USERNAME "${USERNAME}"

    # --------------------------------------------------------------------------
    # Step 14/25: Full name (optional)
    # --------------------------------------------------------------------------
    tui_step 14 25 "Full Name"

    ans=$(tui_input "Full Name" "User's full name (optional, press Enter to skip)" "${USER_FULLNAME:-}")
    cfg_set USER_FULLNAME "${ans}"

    # --------------------------------------------------------------------------
    # Step 15/25: Shell
    # --------------------------------------------------------------------------
    tui_step 15 25 "User Shell"

    ans=$(tui_input "Shell" "User shell" "${USER_SHELL:-/usr/bin/zsh}")
    cfg_set USER_SHELL "${ans}"

    # --------------------------------------------------------------------------
    # Step 16/25: Root password (allow empty → disable root)
    # --------------------------------------------------------------------------
    tui_step 16 25 "Root Password"

    tui_message "Root Password" "Leave empty to disable root login (recommended)."
    local pw
    pw=$(prompt_password_twice "Root Password" "Root password" 1)
    if [[ -n "${pw}" ]]; then
        cfg_set ROOT_PASSWORD_HASH "$(run_quiet hash_password "${pw}")"
    fi
    unset pw

    # --------------------------------------------------------------------------
    # Step 17/25: User password (required)
    # --------------------------------------------------------------------------
    tui_step 17 25 "User Password"

    local pw2=""
    while true; do
        pw2=$(prompt_password_twice "User Password" "Password for ${USERNAME}" 0)
        [[ -n "${pw2}" ]] && break
        tui_message "Error" "User password cannot be empty."
    done
    cfg_set USER_PASSWORD_HASH "$(run_quiet hash_password "${pw2}")"
    unset pw2

    # --------------------------------------------------------------------------
    # Step 18/25: LUKS passphrase (modes B + C)
    # --------------------------------------------------------------------------
    tui_step 18 25 "LUKS Passphrase"

    local LUKS_PASSPHRASE=""
    if [[ "${INSTALL_MODE}" == "B" || "${INSTALL_MODE}" == "C" ]]; then
        tui_message "LUKS Passphrase" "This passphrase is the recovery method. Store it safely."
        while true; do
            local pp
            pp=$(prompt_password_twice "LUKS Passphrase" "Encryption passphrase" 0)
            [[ -n "${pp}" ]] && break
            tui_message "Error" "LUKS passphrase cannot be empty."
        done
        LUKS_PASSPHRASE="${pp}"
        cfg_set LUKS_PASSPHRASE "${LUKS_PASSPHRASE}"
        unset pp
    fi

    # --------------------------------------------------------------------------
    # Step 19/25: TPM2 PIN (mode C only)
    # --------------------------------------------------------------------------
    tui_step 19 25 "TPM2 PIN"

    if [[ "${INSTALL_MODE}" == "C" ]]; then
        tui_message "TPM2 PIN" "The TPM will be wiped and re-enrolled.\nA PIN is required on every boot (in addition to passphrase as recovery)."
        while true; do
            local pin
            pin=$(prompt_password_twice "TPM2 PIN" "TPM2 PIN" 0)
            [[ -n "${pin}" ]] && break
            tui_message "Error" "TPM2 PIN cannot be empty."
        done
        cfg_set TPM_PIN "${pin}"
        unset pin
    fi

    # --------------------------------------------------------------------------
    # Step 20/25: Dotfiles (default on)
    # --------------------------------------------------------------------------
    tui_step 20 25 "Dotfiles"

    if tui_confirm "Dotfiles" "Set up dotfiles automatically? (gh auth login will run now)"; then
        cfg_set DOTFILES_ENABLED 1
        log_info "running gh auth login..."
        run_quiet gh auth login </dev/tty
        run_quiet gh auth token > "${INSTALLER_GH_TOKEN_FILE}"
        chmod 0600 "${INSTALLER_GH_TOKEN_FILE}"
    else
        cfg_set DOTFILES_ENABLED 0
    fi

    # --------------------------------------------------------------------------
    # Step 21/25: Secure Boot (default off)
    # --------------------------------------------------------------------------
    tui_step 21 25 "Secure Boot"

    local sbctl_st
    sbctl_st=$(sbctl status 2>&1 || true)
    tui_message "Secure Boot Status" "${sbctl_st}"
    if tui_confirm "Secure Boot" "Enable Secure Boot (requires firmware in Setup Mode)?"; then
        cfg_set SECURE_BOOT 1
    else
        cfg_set SECURE_BOOT 0
    fi

    # --------------------------------------------------------------------------
    # Step 22/25: Surface kernel (default off)
    # --------------------------------------------------------------------------
    tui_step 22 25 "Surface Kernel"

    if tui_confirm "Surface Kernel" "Install linux-surface kernel? (for Microsoft Surface devices)"; then
        cfg_set SURFACE_KERNEL 1
    else
        cfg_set SURFACE_KERNEL 0
    fi

    # --------------------------------------------------------------------------
    # Step 23/25: Additional optional scripts
    # --------------------------------------------------------------------------
    tui_step 23 25 "Optional Scripts"

    local optional_dir
    optional_dir="$(dirname -- "${BASH_SOURCE[0]}")/../optional"

    # Collect optional scripts, excluding the ones handled by TUI steps above
    local optional_scripts=()
    local optional_tags=()
    local optional_states=()
    if [[ -d "${optional_dir}" ]]; then
        while IFS= read -r -d '' script; do
            local basename_script
            basename_script="$(basename "${script}")"
            # Skip the ones already managed by TUI
            if [[ "${basename_script}" == "secure-boot.sh" || \
                  "${basename_script}" == "surface-kernel.sh" ]]; then
                continue
            fi
            optional_scripts+=("${basename_script}")
            optional_tags+=("${basename_script}")
            optional_states+=("off")
        done < <(find "${optional_dir}" -maxdepth 1 -name "*.sh" -print0 | sort -z)
    fi

    if (( ${#optional_tags[@]} > 0 )); then
        # Build checklist args: tag on|off pairs
        local checklist_args=()
        local i
        for i in "${!optional_tags[@]}"; do
            checklist_args+=("${optional_tags[$i]}" "${optional_states[$i]}")
        done
        local selected_opts
        selected_opts=$(tui_checklist "Optional Scripts" \
            "Select additional optional scripts to run" \
            "${checklist_args[@]}")
        cfg_set OPTIONAL_SCRIPTS "${selected_opts}"
    else
        cfg_set OPTIONAL_SCRIPTS ""
    fi

    # --------------------------------------------------------------------------
    # Step 24/25: Summary recap
    # --------------------------------------------------------------------------
    tui_step 24 25 "Summary"

    # Source the env file so we have all current values
    cfg_load

    # Build summary table
    local summary=""
    local key val display_val
    while IFS='=' read -r key val; do
        [[ -z "${key}" || "${key}" =~ ^# ]] && continue
        # Strip surrounding quotes from val
        val="${val#\'}"
        val="${val%\'}"
        # Mask secrets
        case "${key}" in
            ROOT_PASSWORD_HASH|USER_PASSWORD_HASH|LUKS_PASSPHRASE|TPM_PIN)
                display_val="••••••••"
                ;;
            *)
                display_val="${val}"
                ;;
        esac
        summary="${summary}${key}: ${display_val}\n"
    done < "${INSTALLER_ENV}"

    tui_message "Installation Summary" "$(printf '%b' "${summary}")"

    if ! tui_confirm "Summary" "Proceed with these settings?"; then
        die "Aborted by user."
    fi

    # --------------------------------------------------------------------------
    # Step 25/25: Final destructive confirmation (skip for mode D)
    # --------------------------------------------------------------------------
    tui_step 25 25 "Final Confirmation"

    if [[ "${INSTALL_MODE}" != "D" ]]; then
        local disk_info
        disk_info=$(lsblk -o NAME,SIZE,MODEL "${TARGET_DISK}" 2>&1 || true)
        tui_message "WARNING" "The following disk will be completely erased:\n${disk_info}"

        local typed
        typed=$(tui_input "Final Confirmation" \
            "Type the device name (e.g. sda) to confirm erasure" "")
        local expected
        expected=$(basename "${TARGET_DISK}")
        [[ "${typed}" == "${expected}" ]] || die "Confirmation did not match. Aborting."
    fi

    log_info "TUI complete — all answers saved to ${INSTALLER_ENV}"
}

main "$@"
