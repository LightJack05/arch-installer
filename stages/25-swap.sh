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
    cfg_require FILESYSTEM SWAPFILE_SIZE_MIB

    local target="/mnt"
    [[ "${INSTALL_MODE:-}" == "D" ]] && target="${MANUAL_MOUNT}"

    local swapfile="${target}${SWAPFILE_RELPATH}"

    if [[ "${FILESYSTEM}" == "btrfs" ]]; then
        swap_create_swapfile_btrfs "${SWAPFILE_SIZE_MIB}" "${swapfile}"
    else
        swap_create_swapfile_ext4 "${SWAPFILE_SIZE_MIB}" "${swapfile}"
    fi

    swap_write_zram_conf "${target}"
    swap_append_fstab "${target}" "${SWAPFILE_RELPATH}"

    log_info "swapfile created at ${swapfile} (${SWAPFILE_SIZE_MIB} MiB)"
}

main "$@"
