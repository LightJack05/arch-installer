#!/bin/bash
# stage 25-swap — create swapfile on the mounted root.
#
# zRAM is configured here (writes /mnt/etc/systemd/zram-generator.conf) but
# not activated; the generator runs at first boot of the installed system.
#
# Swapfile goes to /mnt/swap/swapfile. For btrfs, /mnt/swap is the @swap
# subvol (NOCOW + uncompressed, set up by fs.sh earlier).
# Hibernation is not supported (lockdown=confidentiality blocks it).

set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=../lib/config.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/config.sh"
# shellcheck source=../lib/swap.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/swap.sh"

main() {
    cfg_load
    cfg_require SWAPFILE_SIZE_MIB

    local target="/mnt"
    [[ "${INSTALL_MODE:-}" == "D" ]] && target="${MANUAL_MOUNT}"

    # For mode D the user pre-mounted their own partitions; FILESYSTEM is never
    # written to installer.env by stage 20 (which is skipped).  Detect it from
    # the live mount instead.  For modes A/B/C it is already in the environment
    # courtesy of cfg_load above.
    local filesystem="${FILESYSTEM:-}"
    if [[ "${INSTALL_MODE:-}" == "D" ]]; then
        filesystem="$(findmnt -no FSTYPE "${target}" 2>/dev/null || true)"
        if [[ -z "${filesystem}" ]]; then
            log_info "could not detect filesystem type at ${target}; assuming ext4"
            filesystem="ext4"
        fi
    fi
    if [[ -z "${filesystem}" ]]; then
        die "FILESYSTEM is unset and INSTALL_MODE is not D — check installer.env"
    fi

    local swapfile="${target}${SWAPFILE_RELPATH}"

    if [[ "${filesystem}" == "btrfs" ]]; then
        swap_create_swapfile_btrfs "${SWAPFILE_SIZE_MIB}" "${swapfile}"
    else
        swap_create_swapfile_ext4 "${SWAPFILE_SIZE_MIB}" "${swapfile}"
    fi

    swap_write_zram_conf "${target}"
    swap_append_fstab "${target}" "${SWAPFILE_RELPATH}"

    log_info "swapfile created at ${swapfile} (${SWAPFILE_SIZE_MIB} MiB)"
}

main "$@"
