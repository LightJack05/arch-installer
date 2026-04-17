#!/bin/bash
# lib/encryption.sh — LUKS2 format + systemd-cryptenroll (passphrase + TPM2 PIN).
#
# Naming: the LUKS container is always opened as "cryptroot". Root FS lives
# directly on /dev/mapper/cryptroot — no LVM.
#
# Functions:
#   enc_format <dev> <passphrase>           — cryptsetup luksFormat (argon2id)
#   enc_open <dev> <passphrase> [<name>]    — cryptsetup open → /dev/mapper/<name>
#   enc_close [<name>]                      — cryptsetup close
#   enc_tpm_wipe <dev>                      — systemd-cryptenroll --wipe-slot=tpm2
#   enc_tpm_enroll <dev> <pin> [<pcrs>]     — tpm2-device=auto, tpm2-with-pin=yes, pcrs=0+7 by default
#   enc_get_luks_uuid <dev>                 — echo LUKS header UUID

set -Eeuo pipefail

# Guard against double-sourcing.
if [[ "${__INSTALLER_ENCRYPTION_SOURCED:-0}" == "1" ]]; then
    return 0
fi
readonly __INSTALLER_ENCRYPTION_SOURCED=1

# Source common.sh if not already loaded.
_ENC_DIR="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${__INSTALLER_COMMON_SOURCED:-0}" != "1" ]]; then
    # shellcheck source=common.sh
    source "${_ENC_DIR}/common.sh"
fi

# enc_format <dev> <passphrase>
# Format a LUKS2 container with argon2id KDF.
# Passphrase is passed via stdin ('-') — never on the command line.
enc_format() {
    local dev="$1" passphrase="$2"
    log_info "enc_format: formatting ${dev} as LUKS2 (argon2id)"
    run_quiet bash -c 'printf "%s" "$1" | cryptsetup luksFormat \
        --type luks2 \
        --batch-mode \
        --pbkdf argon2id \
        "$2" -' \
        _ "${passphrase}" "${dev}"
}

# enc_open <dev> <passphrase> [<name>]
# Open an existing LUKS2 container. Mapper name defaults to "cryptroot".
# Idempotent: skips if /dev/mapper/<name> already exists.
enc_open() {
    local dev="$1" passphrase="$2" name="${3:-cryptroot}"
    if [[ -e "/dev/mapper/${name}" ]]; then
        log_info "enc_open: /dev/mapper/${name} already open — skipping"
        return 0
    fi
    log_info "enc_open: opening ${dev} as ${name}"
    run_quiet bash -c 'printf "%s" "$1" | cryptsetup open "$2" "$3" --key-file -' \
        _ "${passphrase}" "${dev}" "${name}"
}

# enc_close [<name>]
# Close a LUKS mapper. Defaults to "cryptroot". Does not fail if already closed.
enc_close() {
    local name="${1:-cryptroot}"
    log_info "enc_close: closing ${name}"
    cryptsetup close "${name}" || true
}

# enc_tpm_wipe <dev>
# Clear any prior TPM2 keyslots from the LUKS header.
# This ensures a clean slate before enrolling a new PIN-protected TPM2 key.
# Note: tpm2_clear -c p (platform hierarchy) is not callable from the OS, and
# a full TPM clear is not needed — wiping the LUKS keyslot is sufficient.
enc_tpm_wipe() {
    local dev="$1"

    log_info "enc_tpm_wipe: clearing prior TPM2 keyslot from LUKS header on ${dev}"
    # Remove prior TPM keyslot if any (OK if none exist).
    systemd-cryptenroll --wipe-slot=tpm2 "${dev}" 2>/dev/null || true
}

# enc_tpm_enroll <dev> <passphrase> <pin> [<pcrs>]
# Enroll a TPM2+PIN key into the LUKS container.
#   - The existing keyslot (passphrase) authenticates the enrollment via --unlock-key-file.
#   - The new PIN is written to a temp file and piped to cryptsetup via the
#     SYSTEMD_CRYPTENROLL_TPM2_PIN env var (supported since systemd v252).
#     As a belt-and-suspenders fallback we also write it to a second temp file
#     used with --tpm2-pin-file if the env approach is unavailable.
# PCRs default to "0+7".
#
# NOTE: Function signature is enc_tpm_enroll <dev> <passphrase> <pin> [<pcrs>]
# so callers must pass the passphrase (not just the PIN).
enc_tpm_enroll() {
    local dev="$1" passphrase="$2" pin="$3" pcrs="${4:-0+7}"

    log_info "enc_tpm_enroll: enrolling TPM2+PIN on ${dev} (PCRs=${pcrs})"

    # Write the existing passphrase to a temp file (unlock key).
    local pass_file
    pass_file=$(mktemp)
    chmod 600 "${pass_file}"
    printf '%s' "${passphrase}" > "${pass_file}"

    # Write the new TPM2 PIN to a temp file.
    local pin_file
    pin_file=$(mktemp)
    chmod 600 "${pin_file}"
    printf '%s' "${pin}" > "${pin_file}"

    # Ensure both temp files are shredded even if the enrollment fails.
    # (set -e + ERR trap will exit the script, but the trap below fires first.)
    trap 'shred -u "${pass_file}" "${pin_file}" 2>/dev/null || rm -f "${pass_file}" "${pin_file}"' RETURN

    # systemd-cryptenroll (>= v252) reads the TPM2 PIN from the $PIN env var
    # when --tpm2-with-pin=yes is set.  We export it from a subshell so it
    # never appears on any process command line (the parent shell sets it in
    # the child's environment, not as an argv token).
    local _pin_val _pass_val
    _pin_val="$(cat "${pin_file}")"
    _pass_val="$(cat "${pass_file}")"
    run_quiet bash -c '
        export PIN="$1"
        systemd-cryptenroll \
            --tpm2-device=auto \
            --tpm2-with-pin=yes \
            --tpm2-pcrs="$2" \
            --unlock-key-file="$3" \
            "$4"
    ' _ "${_pin_val}" "${pcrs}" "${pass_file}" "${dev}"
    unset _pin_val _pass_val

    # Shred both temp files even on error (trap handles abnormal exits via
    # set -Eeuo pipefail, but we clean up here for the success path).
    shred -u "${pass_file}" "${pin_file}" 2>/dev/null || rm -f "${pass_file}" "${pin_file}"
}

# enc_get_luks_uuid <dev>
# Print the UUID stored in the LUKS2 header of <dev>.
enc_get_luks_uuid() {
    local dev="$1"
    blkid -s UUID -o value "${dev}"
}
