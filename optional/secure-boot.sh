#!/bin/bash
# optional/secure-boot.sh — sbctl key creation, enrollment, and signing.
#
# Invoked from stage 60 when SECURE_BOOT=1. Precondition: firmware in Setup Mode.
# sbctl installs a pacman hook that re-signs UKI rebuilds automatically.

set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=../lib/secureboot.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/secureboot.sh"

main() {
    log_info "configuring secure boot (sbctl)"
    # TODO: sb_status || die "firmware not in Setup Mode — cannot enroll keys"
    # TODO: sb_create_keys
    # TODO: sb_enroll_keys
    # TODO: sb_sign_all
    :
}

main "$@"
