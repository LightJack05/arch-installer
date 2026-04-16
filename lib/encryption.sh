#!/bin/bash
# lib/encryption.sh — LUKS2 format + systemd-cryptenroll (passphrase + TPM2 PIN).
#
# Naming: the LUKS container is always opened as "cryptroot". Root FS lives
# directly on /dev/mapper/cryptroot — no LVM.
#
# Functions:
#   enc_format <dev> <passphrase>           — cryptsetup luksFormat (argon2id)
#   enc_open <dev> <passphrase>             — cryptsetup open → /dev/mapper/cryptroot
#   enc_tpm_wipe <dev>                      — systemd-cryptenroll --wipe-slot=tpm2 + tpm2_clear -c p
#   enc_tpm_enroll <dev> <pin> [<pcrs>]     — tpm2-device=auto, tpm2-with-pin=yes, pcrs=0+7 by default
#   enc_get_luks_uuid <dev>                 — echo LUKS header UUID

set -Eeuo pipefail

enc_format() {
    local dev="$1" passphrase="$2"
    # TODO: printf '%s' "$passphrase" | cryptsetup luksFormat --type luks2 --batch-mode "$dev" -
    # Never put the passphrase on the command line (ps visibility).
    :
}

enc_open() {
    local dev="$1" passphrase="$2" name="${3:-cryptroot}"
    # TODO: printf '%s' "$passphrase" | cryptsetup open "$dev" "$name" --key-file -
    :
}

enc_tpm_wipe() {
    local dev="$1"
    # TODO:
    #   systemd-cryptenroll --wipe-slot=tpm2 "$dev" || true   # no prior keyslot is OK
    #   tpm2_clear -c p || die "tpm2_clear failed — clear TPM from firmware and retry"
    :
}

enc_tpm_enroll() {
    local dev="$1" pin="$2" pcrs="${3:-0+7}"
    # TODO: PASSWORD="$pin" systemd-cryptenroll \
    #         --tpm2-device=auto --tpm2-with-pin=yes --tpm2-pcrs="$pcrs" "$dev"
    # NB: systemd-cryptenroll reads the PIN from stdin or env (see man page).
    :
}

enc_get_luks_uuid() {
    local dev="$1"
    # TODO: blkid -s UUID -o value "$dev"
    :
}
