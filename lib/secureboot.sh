#!/bin/bash
# lib/secureboot.sh — sbctl key creation, enrollment, and UKI signing.
#
# Prerequisite: firmware in Setup Mode. Caller (optional/secure-boot.sh) surfaces
# `sbctl status` before invoking this to let the user verify.
#
# Ordering note: if scheme D (TPM2+PIN) is also selected, enroll SB keys and
# rebuild+sign the UKI BEFORE doing the TPM enrollment, so PCR 7 is stable.
#
# Functions:
#   sb_status                  — print sbctl status; non-zero if not in Setup Mode
#   sb_create_keys             — sbctl create-keys
#   sb_enroll_keys             — sbctl enroll-keys -m
#   sb_sign_all                — sbctl sign -s for UKI + fallback + any unsigned EFI binaries

set -Eeuo pipefail

sb_status() {
    sbctl status
}

sb_create_keys() {
    run sbctl create-keys
}

sb_enroll_keys() {
    run sbctl enroll-keys -m
}

sb_sign_all() {
    run sbctl sign -s /efi/EFI/BOOT/BOOTX64.EFI
    [[ -f /efi/EFI/Linux/arch-linux-fallback.efi ]] && \
        run sbctl sign -s /efi/EFI/Linux/arch-linux-fallback.efi || true
}
