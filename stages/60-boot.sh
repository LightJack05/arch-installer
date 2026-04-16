#!/bin/bash
# stage 60-boot — initramfs hooks, kernel cmdline, UKI build, optional secure boot.
#
# Always:
#   - write HOOKS=(systemd autodetect modconf keyboard sd-vconsole block sd-encrypt filesystems fsck)
#   - write /etc/mkinitcpio.d/linux.preset for UKI output
#   - build cmdline with resume=/resume_offset (from /tmp/installer.env)
#   - mkinitcpio -P  →  /efi/EFI/BOOT/BOOTX64.EFI
#
# If SECURE_BOOT=1:
#   - run optional/secure-boot.sh  (creates keys, enrolls, signs)
#   - do this BEFORE TPM enrollment so PCR 7 is stable (scheme C note)
#
# For scheme D: derive UUIDs from the mounted filesystems via findmnt + blkid.

set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=../lib/config.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/config.sh"
# shellcheck source=../lib/bootloader.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/bootloader.sh"

main() {
    cfg_load
    cfg_require INSTALL_MODE RESUME_OFFSET

    # TODO: boot_write_mkinitcpio_conf
    # TODO: boot_write_preset

    local cmdline
    case "${INSTALL_MODE}" in
        A)
            # TODO: root_uuid=$(findmnt -no UUID /)
            # TODO: cmdline=$(boot_build_cmdline_scheme_a "$root_uuid" "$RESUME_OFFSET")
            ;;
        B)
            # TODO: luks_uuid=$LUKS_UUID  (set by stage 20) or derive via blkid
            # TODO: cmdline=$(boot_build_cmdline_scheme_b "$luks_uuid" "$RESUME_OFFSET")
            ;;
        C)
            # TODO: cmdline=$(boot_build_cmdline_scheme_c "$LUKS_UUID" "$RESUME_OFFSET")
            ;;
        D)
            # TODO: inspect /: plain → scheme A cmdline; /dev/mapper → scheme B or C
            ;;
    esac

    # TODO: boot_write_cmdline "$cmdline"
    # TODO: boot_rebuild_uki

    if [[ "${SECURE_BOOT:-0}" == "1" ]]; then
        "${INSTALLER_ROOT}/optional/secure-boot.sh"
        # TODO: boot_rebuild_uki  (re-sign is handled by sbctl pacman hook)
    fi
    :
}

main "$@"
