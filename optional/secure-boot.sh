#!/bin/bash
# optional/secure-boot.sh — sbctl key creation and enrollment.
#
# Invoked from stage 60 when SECURE_BOOT=1, BEFORE boot_rebuild_uki.
# Creates and enrolls keys only; signing happens in stage 60 AFTER the UKI
# is built (sb_sign_all), and future UKI rebuilds are covered by the sbctl
# pacman hook installed by the sbctl package.
#
# Precondition: firmware in Setup Mode.

set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=../lib/secureboot.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/secureboot.sh"

main() {
    log_info "configuring secure boot (sbctl)"

    sb_status || die "firmware not in Setup Mode — clear keys in UEFI setup and retry"

    sb_create_keys
    sb_enroll_keys

    log_info "secure boot keys enrolled — sbctl pacman hook will re-sign future UKI rebuilds"
}

main "$@"
