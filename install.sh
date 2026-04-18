#!/bin/bash
# install.sh — single entrypoint for the Arch installer.
# Run from the Arch ISO (live environment).
#
# Flow:
#   00-precheck → iso-bootstrap-all → 10-tui → 20-disk → 25-swap → 30-pacstrap
#   → 40-chroot → (inside chroot) 50-system → 60-boot → 70-users → 80-packages
#   → 85-aur → 88-optional → 90-services → 95-dotfiles → 99-finalize
#
# Stages numbered <40 run on the live ISO.
# Stage 40 arch-chroots into /mnt, which re-invokes this script with
# INSTALLER_IN_CHROOT=1 so stages ≥50 run inside the new system.
#
# See PLAN.md for the full design.

set -Eeuo pipefail
shopt -s inherit_errexit

readonly INSTALLER_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export INSTALLER_ROOT

# shellcheck source=lib/common.sh
source "${INSTALLER_ROOT}/lib/common.sh"
# shellcheck source=lib/config.sh
source "${INSTALLER_ROOT}/lib/config.sh"
# shellcheck source=lib/iso-bootstrap.sh
source "${INSTALLER_ROOT}/lib/iso-bootstrap.sh"

# ISO-side stages (run on the live environment, after iso_bootstrap_all)
readonly ISO_STAGES=(
    "10-tui"
    "20-disk"
    "25-swap"
    "30-pacstrap"
    "40-chroot"
)

# Chroot-side stages (run inside the newly installed system)
readonly CHROOT_STAGES=(
    "50-system"
    "60-boot"
    "70-users"
    "80-packages"
    "85-aur"
    "88-optional"
    "90-services"
    "95-dotfiles"
    "99-finalize"
)

run_stage() {
    local stage="$1"
    local path="${INSTALLER_ROOT}/stages/${stage}.sh"
    [[ -x "${path}" ]] || die "stage ${stage} not found or not executable at ${path}"
    log_info "────── stage ${stage} ──────"
    "${path}"
}

main() {
    if [[ "${INSTALLER_IN_CHROOT:-0}" == "1" ]]; then
        log_info "Running chroot-side stages"
        for stage in "${CHROOT_STAGES[@]}"; do
            run_stage "${stage}"
        done
        return
    fi

    log_info "Arch installer starting on live ISO"
    run_stage "00-precheck"
    iso_bootstrap_all
    for stage in "${ISO_STAGES[@]}"; do
        run_stage "${stage}"
    done
}

main "$@"
