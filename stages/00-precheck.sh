#!/bin/bash
# stage 00-precheck — verify the live ISO environment before starting.
#
# Checks:
#   - running as root
#   - UEFI boot (efivarfs populated)
#   - network reachable (best-effort: resolve archlinux.org)
#   - system clock sync'd (timedatectl)
#   - pacman keyring populated
#   - free RAM ≥ ~1 GiB before pulling extra ISO tooling

set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

main() {
    require_root
    log_info "running precheck"

    # TODO: [[ -d /sys/firmware/efi/efivars ]] || die "not booted in UEFI mode"
    # TODO: curl -fsS https://archlinux.org >/dev/null || log_warn "no network — some steps will fail"
    # TODO: timedatectl set-ntp true
    # TODO: pacman-key --init (if empty) + populate archlinux
    # TODO: awk '/MemAvailable/ {print $2}' /proc/meminfo  → gate ISO extras

    :
}

main "$@"
