#!/bin/bash
# stage 00-precheck — verify the live ISO environment before starting.
#
# Checks:
#   - running as root
#   - UEFI boot (efivarfs populated)
#   - network reachable (best-effort: resolve archlinux.org)
#   - system clock sync'd (timedatectl)
#   - pacman keyring populated
#   - free RAM ≥ ~512 MiB before pulling extra ISO tooling

set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

main() {
    require_root
    log_info "running precheck"

    # 1. UEFI check
    [[ -d /sys/firmware/efi/efivars ]] || die "not booted in UEFI mode — reboot with UEFI enabled"
    log_info "UEFI mode confirmed"

    # 2. Network check (best-effort)
    if ! curl -fsS --max-time 5 https://archlinux.org >/dev/null 2>&1; then
        log_warn "network check failed — some steps may not work"
    else
        log_info "network reachable"
    fi

    # 3. Clock sync
    run timedatectl set-ntp true
    log_info "waiting for clock sync..."
    for i in $(seq 1 10); do
        timedatectl show | grep -q 'NTPSynchronized=yes' && break
        sleep 1
    done
    timedatectl show | grep -q 'NTPSynchronized=yes' || log_warn "clock may not be synced"
    log_info "clock sync check done"

    # 4. Pacman keyring
    if [[ ! -f /etc/pacman.d/gnupg/pubring.gpg ]]; then
        run pacman-key --init
        run pacman-key --populate archlinux
    else
        log_info "pacman keyring already populated"
    fi

    # 5. RAM budget (for iso-bootstrap)
    local avail_mib
    avail_mib=$(awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo)
    if (( avail_mib < 512 )); then
        log_warn "only ${avail_mib} MiB RAM available — skipping extra ISO tooling"
        export INSTALLER_SKIP_ISO_EXTRAS=1
    fi
    log_info "available RAM: ${avail_mib} MiB"

    # 6. Log init
    mkdir -p "$(dirname "$INSTALLER_LOG")"
    touch "$INSTALLER_LOG"
    chmod 600 "$INSTALLER_LOG"
    log_info "log file: ${INSTALLER_LOG}"

    log_info "precheck complete"
}

main "$@"
